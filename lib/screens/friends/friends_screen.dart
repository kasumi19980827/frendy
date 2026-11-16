import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/profile/profile_detail_screen.dart';
import 'package:matching_app/screens/subscription/subscription_screen.dart';

// ============================================================================
// データモデル（旧: users/{uid} 内の配列 → 新: サブコレクション）
//
//   users/{uid}                     公開プロフィール（name, imageUrls, gender ...）
//   users/{uid}/friends/{peerId}    友達        … 本人のみ読取 / 書込はFunctionsのみ
//   users/{uid}/likes/{peerId}      いいねした  … 本人のみ読取 / 書込はFunctionsのみ
//   users/{uid}/likedBy/{peerId}    いいねされた … 読取・書込ともFunctionsのみ（課金判定のため）
//   users/{uid}/footprints/{peerId} 足跡        … 読取・書込ともFunctionsのみ（課金判定のため）
//   users/{uid}/blocks/{peerId}     ブロック    … 本人のみ読取 / 書込はFunctionsのみ
//   friend_requests/{fromId}_{toId} 友達申請（決定的IDで重複申請を根本的に防止）
//   reports/{reporterId}_{reportedId} 通報（同一相手への連投を防止）
//
// 他人のドキュメントを書き換える操作（承認・解除・ブロック）はすべて
// Cloud Functions 経由で行い、クライアントからは一切書き込ませない。
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const int _kPageSize = 20;
const int _kWhereInLimit = 30; // Firestore whereIn の上限
const int _kBadgeLimit = 100; // バッジは「99+」表示で十分なので上限を設ける
const int _kProfileCacheMax = 500; // メモリ肥大化防止
const String _kFunctionsRegion = 'asia-northeast1';

FirebaseFirestore get _db => FirebaseFirestore.instance;

HttpsCallable _callable(String name) => FirebaseFunctions.instanceFor(
  region: _kFunctionsRegion,
).httpsCallable(name, options: HttpsCallableOptions(timeout: _kNetworkTimeout));

String _errorMessage(Object e, String fallback) {
  if (e is FirebaseFunctionsException) {
    switch (e.code) {
      case 'failed-precondition':
      case 'not-found':
      case 'invalid-argument':
      case 'permission-denied':
        return e.message ?? fallback; // サーバー側で用意した日本語メッセージ
      case 'unauthenticated':
        return 'ログインの有効期限が切れました。再度ログインしてください。';
      case 'resource-exhausted':
        return '操作が多すぎます。しばらく時間をおいてお試しください。';
      case 'deadline-exceeded':
      case 'unavailable':
        return '通信状況を確認して、もう一度お試しください。';
    }
  }
  if (e is TimeoutException) return '通信がタイムアウトしました。もう一度お試しください。';
  return fallback;
}

// ----------------------------------------------------------------------------
// モデル
// ----------------------------------------------------------------------------
class _UserSummary {
  const _UserSummary({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.gender,
  });

  final String id;
  final String name;
  final String imageUrl;
  final String? gender;

  factory _UserSummary.fromMap(String id, Map<String, dynamic> d) {
    String url = '';
    final thumb = d['thumbnailUrl'];
    final images = d['imageUrls'];
    if (thumb is String && thumb.isNotEmpty) {
      url = thumb;
    } else if (images is List && images.isNotEmpty && images.first is String) {
      url = images.first as String;
    }
    // 💡 https 以外のURLは表示しない（平文通信・不正スキームの読み込み防止）
    if (!url.startsWith('https://')) url = '';

    final rawName = d['name'];
    return _UserSummary(
      id: id,
      name: rawName is String && rawName.trim().isNotEmpty ? rawName : 'ユーザー',
      imageUrl: url,
      gender: d['gender'] is String ? d['gender'] as String : null,
    );
  }
}

// ----------------------------------------------------------------------------
// プロフィール取得（ページ単位でまとめて取得＋上限付きキャッシュ）
// ----------------------------------------------------------------------------
class _ProfileRepository {
  final Map<String, _UserSummary> _cache = {}; // 挿入順を保持（古い順に破棄）

  Future<Map<String, _UserSummary>> fetchMany(Iterable<String> ids) async {
    final unique = ids.toSet();
    final missing = unique.where((id) => !_cache.containsKey(id)).toList();

    final chunks = <List<String>>[];
    for (var i = 0; i < missing.length; i += _kWhereInLimit) {
      chunks.add(
        missing.sublist(i, math.min(i + _kWhereInLimit, missing.length)),
      );
    }

    // 💡 チャンクは直列ではなく並列で取得する
    await Future.wait(
      chunks.map((chunk) async {
        try {
          final snap = await _db
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get()
              .timeout(_kNetworkTimeout);
          for (final doc in snap.docs) {
            _cache[doc.id] = _UserSummary.fromMap(doc.id, doc.data());
          }
        } catch (e) {
          debugPrint('ユーザー一括取得エラー: $e');
        }
      }),
    );

    while (_cache.length > _kProfileCacheMax) {
      _cache.remove(_cache.keys.first);
    }

    return {
      for (final id in unique)
        if (_cache[id] != null) id: _cache[id]!,
    };
  }

  void evict(String id) => _cache.remove(id);
}

// ----------------------------------------------------------------------------
// 画面
// ----------------------------------------------------------------------------
enum _Menu {
  friends('友達一覧', Icons.group),
  requests('友達申請', Icons.person_add),
  likes('いいねした', Icons.thumb_up_alt_outlined),
  likedBy('いいねされた', Icons.thumb_up_alt),
  footprints('足跡', Icons.visibility);

  const _Menu(this.label, this.icon);
  final String label;
  final IconData icon;
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  _Menu _selected = _Menu.friends;
  late final String _myId;

  final _ProfileRepository _repo = _ProfileRepository();
  final GlobalKey<_PaginatedUserListState> _friendsListKey = GlobalKey();
  final Set<String> _processingRequestIds = {};
  bool _openingProfile = false;

  // 💡 Streamは initState で一度だけ生成する。
  //    build内で .snapshots() を呼ぶと、再描画のたびに購読し直して読み取りが増える
  Stream<QuerySnapshot<Map<String, dynamic>>>? _badgeStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _requestsStream;

  String? _requestIdsSig;
  Future<Map<String, _UserSummary>>? _requestProfilesFuture;

  DocumentReference<Map<String, dynamic>> get _myRef =>
      _db.collection('users').doc(_myId);

  @override
  void initState() {
    super.initState();
    _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_myId.isNotEmpty) {
      final query = _db
          .collection('friend_requests')
          .where('toId', isEqualTo: _myId)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(_kBadgeLimit);
      // 同一クエリはSDK内部でリスナーが共有されるため、読み取りは二重にならない
      _badgeStream = query.snapshots();
      _requestsStream = query.snapshots();
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.redAccent : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (_myId.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: Text('ログインが必要です')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _selected.label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Row(
        children: [
          Container(
            width: 85,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                _buildMenuItem(_Menu.friends),
                _buildRequestMenuItem(),
                _buildMenuItem(_Menu.likes),
                _buildMenuItem(_Menu.likedBy),
                _buildMenuItem(_Menu.footprints),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // --- サイドメニュー ---
  Widget _buildMenuItem(_Menu menu, {int badge = 0}) {
    final bool isSelected = _selected == menu;
    return InkWell(
      onTap: () => setState(() => _selected = menu),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
            color: isSelected ? Colors.white : Colors.transparent,
            child: Column(
              children: [
                Icon(
                  menu.icon,
                  color: isSelected ? AppColors.point : AppColors.txt,
                ),
                const SizedBox(height: 5),
                Text(
                  menu.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? AppColors.point : AppColors.txt,
                  ),
                ),
              ],
            ),
          ),
          if (badge > 0)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRequestMenuItem() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _badgeStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('友達申請バッジ取得エラー: ${snapshot.error}');
        }
        final int count = snapshot.hasData && !snapshot.hasError
            ? snapshot.data!.docs.length
            : 0;
        return _buildMenuItem(_Menu.requests, badge: count);
      },
    );
  }

  // --- コンテンツ出し分け ---
  Widget _buildContent() {
    switch (_selected) {
      case _Menu.friends:
        return _PaginatedUserList(
          key: _friendsListKey,
          query: _myRef
              .collection('friends')
              .orderBy('createdAt', descending: true),
          repo: _repo,
          emptyMessage: 'まだ友達がいません',
          itemBuilder: (context, user) => _UserTile(
            user: user,
            onTap: () => _openProfile(user.id),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showActionSheet(user),
            ),
          ),
        );
      case _Menu.requests:
        return _buildRequestList();
      case _Menu.likes:
        return _PaginatedUserList(
          key: const ValueKey('likes'),
          query: _myRef
              .collection('likes')
              .orderBy('createdAt', descending: true),
          repo: _repo,
          emptyMessage: 'いいねしたユーザーはいません',
          itemBuilder: (context, user) =>
              _UserTile(user: user, onTap: () => _openProfile(user.id)),
        );
      case _Menu.likedBy:
        return _InboxList(
          key: const ValueKey('likedBy'),
          type: 'likedBy',
          emptyMessage: 'まだいいねが届いていません',
          lockedTitle: 'いいねは非表示中です',
          lockedMessage:
              '現在のプランでは、いいねをくれた相手はモザイク表示になっています。\n\n'
              '『スタンダードプラン』以降に登録すると、いいねをくれた相手をすべて確認できるようになります。',
          onOpenProfile: _openProfile,
        );
      case _Menu.footprints:
        return _InboxList(
          key: const ValueKey('footprints'),
          type: 'footprints',
          emptyMessage: 'まだ足跡はありません',
          lockedTitle: '足跡は非表示中です',
          lockedMessage:
              '現在フリープランをご利用中のため、あなたのプロフィールを見た人はモザイク表示になっています。\n\n'
              '『ライトプラン』以降に登録すると、足跡をつけた相手をすべて確認できるようになります。',
          onOpenProfile: _openProfile,
        );
    }
  }

  // --- 友達申請リスト ---
  Widget _buildRequestList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _requestsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          // 複合インデックス未作成の場合、ここにインデックス作成URLが出力される
          debugPrint('友達申請一覧の取得エラー: ${snapshot.error}');
          return const Center(
            child: Text('エラーが発生しました', style: TextStyle(color: Colors.grey)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // 決定的ID（fromId_toId）により重複は発生しないため、形式チェックのみ行う
        final docs = snapshot.data!.docs.where((d) {
          final fromId = d.data()['fromId'];
          return fromId is String && fromId.isNotEmpty;
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Text('届いている申請はありません', style: TextStyle(color: Colors.grey)),
          );
        }

        final fromIds = docs.map((d) => d.data()['fromId'] as String).toList();
        final sig = fromIds.join(',');
        if (sig != _requestIdsSig) {
          _requestIdsSig = sig;
          _requestProfilesFuture = _repo.fetchMany(fromIds);
        }

        return FutureBuilder<Map<String, _UserSummary>>(
          future: _requestProfilesFuture,
          builder: (context, profilesSnap) {
            if (!profilesSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final profiles = profilesSnap.data!;

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final String requestId = docs[index].id;
                final String fromId = fromIds[index];
                final user = profiles[fromId];
                if (user == null) return const SizedBox.shrink();

                final bool isProcessing = _processingRequestIds.contains(
                  requestId,
                );

                return _UserTile(
                  user: user,
                  onTap: () => _openProfile(user.id),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 20,
                              ),
                        onPressed: isProcessing
                            ? null
                            : () => _declineFriendRequest(user.name, requestId),
                        tooltip: '拒否する',
                      ),
                      SizedBox(
                        width: 64,
                        height: 30,
                        child: ElevatedButton(
                          onPressed: isProcessing
                              ? null
                              : () =>
                                    _acceptFriendRequest(user.name, requestId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.bg,
                            disabledBackgroundColor: Colors.grey[300],
                            elevation: 0,
                            minimumSize: const Size(64, 30),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: isProcessing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '承認',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- プロフィール遷移（タップ時にのみ詳細を取得） ---
  Future<void> _openProfile(String userId) async {
    if (_openingProfile) return; // 連打による多重遷移を防ぐ
    _openingProfile = true;
    try {
      final snap = await _db
          .collection('users')
          .doc(userId)
          .get()
          .timeout(_kNetworkTimeout);
      final data = snap.data();
      if (!mounted) return;
      if (data == null) {
        _toast('このユーザーは見つかりませんでした');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileDetailScreen(userData: data, userId: userId),
        ),
      );
    } catch (e) {
      debugPrint('プロフィール取得エラー: $e');
      _toast('プロフィールを読み込めませんでした', isError: true);
    } finally {
      _openingProfile = false;
    }
  }

  // --- アクションシート ---
  void _showActionSheet(_UserSummary user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              Text(
                user.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _ActionTile(
                icon: Icons.report_problem_outlined,
                title: '通報する',
                subtitle: '不適切な内容を報告',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReportDialog(user);
                },
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.block,
                title: 'ブロックする',
                subtitle: 'このユーザーを非表示',
                color: Colors.black87,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmAndBlock(user);
                },
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.person_remove_outlined,
                title: '友達解除',
                subtitle: '友達リストから削除します',
                color: Colors.redAccent,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmAndRemoveFriend(user);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  // --- 通報 ---
  Future<void> _showReportDialog(_UserSummary user) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(
        reporterId: _myId,
        peerId: user.id,
        peerName: user.name,
      ),
    );
    if (sent == true) _toast('報告ありがとうございます。運営で確認いたします。');
  }

  // --- 友達解除（Cloud Functions 経由） ---
  Future<void> _confirmAndRemoveFriend(_UserSummary user) async {
    final ok = await _confirm(
      title: '${user.name} さんを友達解除',
      message: '友達リストからお互いに削除されます。よろしいですか？',
      confirmLabel: '解除する',
    );
    if (!ok) return;

    try {
      await _callable('removeFriend').call({'peerId': user.id});
      _friendsListKey.currentState?.removeById(user.id);
      _toast('${user.name} さんの登録を解除しました');
    } catch (e) {
      debugPrint('友達解除エラー: $e');
      _toast(_errorMessage(e, '解除に失敗しました。もう一度お試しください。'), isError: true);
    }
  }

  // --- ブロック（Cloud Functions 経由） ---
  Future<void> _confirmAndBlock(_UserSummary user) async {
    final ok = await _confirm(
      title: '${user.name} さんをブロック',
      message: 'ブロックすると、お互いのリストに表示されなくなり、メッセージのやり取りもできなくなります。よろしいですか？',
      confirmLabel: 'ブロックする',
    );
    if (!ok) return;

    try {
      await _callable('blockUser').call({'peerId': user.id});
      _friendsListKey.currentState?.removeById(user.id);
      _repo.evict(user.id);
      _toast('${user.name} さんをブロックしました');
    } catch (e) {
      debugPrint('ブロックエラー: $e');
      _toast(_errorMessage(e, 'ブロックに失敗しました。もう一度お試しください。'), isError: true);
    }
  }

  // --- 友達申請の承認（Cloud Functions 内のトランザクションで処理） ---
  Future<void> _acceptFriendRequest(String name, String requestId) async {
    if (_processingRequestIds.contains(requestId)) return;
    setState(() => _processingRequestIds.add(requestId));

    try {
      await _callable('acceptFriendRequest').call({'requestId': requestId});
      _toast('$name さんと友達になりました');
      if (mounted) setState(() => _selected = _Menu.friends);
    } catch (e) {
      debugPrint('友達申請承認エラー: $e');
      _toast(_errorMessage(e, '申請の承認に失敗しました。もう一度お試しください。'), isError: true);
    } finally {
      if (mounted) setState(() => _processingRequestIds.remove(requestId));
    }
  }

  // --- 友達申請の拒否（自分宛ての申請の削除はルールで許可） ---
  Future<void> _declineFriendRequest(String name, String requestId) async {
    if (_processingRequestIds.contains(requestId)) return;
    setState(() => _processingRequestIds.add(requestId));

    try {
      await _db
          .collection('friend_requests')
          .doc(requestId)
          .delete()
          .timeout(_kNetworkTimeout);
      _toast('$name さんからの申請を削除しました');
    } on TimeoutException {
      // オフライン時は端末側で削除済みとして扱われ、接続回復後に送信される
      _toast('通信が不安定です。接続が回復すると反映されます。');
    } catch (e) {
      debugPrint('友達申請拒否エラー: $e');
      _toast('操作に失敗しました。もう一度お試しください。', isError: true);
    } finally {
      if (mounted) setState(() => _processingRequestIds.remove(requestId));
    }
  }
}

// ----------------------------------------------------------------------------
// ページング付きユーザー一覧（友達一覧・いいねした）
// ----------------------------------------------------------------------------
class _PaginatedUserList extends StatefulWidget {
  const _PaginatedUserList({
    super.key,
    required this.query,
    required this.repo,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  /// ドキュメントIDが相手のUIDであるサブコレクションへの並び替え済みクエリ
  final Query<Map<String, dynamic>> query;
  final _ProfileRepository repo;
  final String emptyMessage;
  final Widget Function(BuildContext, _UserSummary) itemBuilder;

  @override
  State<_PaginatedUserList> createState() => _PaginatedUserListState();
}

class _PaginatedUserListState extends State<_PaginatedUserList> {
  final List<_UserSummary> _items = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      Query<Map<String, dynamic>> q = widget.query.limit(_kPageSize);
      if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);

      final snap = await q.get().timeout(_kNetworkTimeout);
      final ids = snap.docs.map((d) => d.id).toList();
      final profiles = await widget.repo.fetchMany(ids);
      if (!mounted) return;

      setState(() {
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        _hasMore = snap.docs.length == _kPageSize;
        final existing = _items.map((e) => e.id).toSet();
        for (final id in ids) {
          final p = profiles[id];
          // 退会済み等でプロフィールが無いユーザーはスキップ
          if (p != null && existing.add(id)) _items.add(p);
        }
      });
    } catch (e) {
      debugPrint('一覧取得エラー: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    setState(() {
      _items.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    await _loadMore();
  }

  void removeById(String id) {
    if (!mounted) return;
    setState(() => _items.removeWhere((e) => e.id == id));
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _error != null) {
      return _RetryView(onRetry: refresh);
    }
    if (_items.isEmpty && (_loading || _hasMore)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: _EmptyScrollable(message: widget.emptyMessage),
      );
    }

    final bool showFooter = _hasMore || _error != null;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < _items.length) {
            return widget.itemBuilder(context, _items[index]);
          }
          if (_error != null) {
            return TextButton(onPressed: _loadMore, child: const Text('再読み込み'));
          }
          // 💡 末尾が表示されたら次ページを読み込む（無限スクロール）
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          return const _LoadingFooter();
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// いいねされた／足跡（プラン判定はサーバー側で実施）
// ----------------------------------------------------------------------------
class _InboxList extends StatefulWidget {
  const _InboxList({
    super.key,
    required this.type,
    required this.emptyMessage,
    required this.lockedTitle,
    required this.lockedMessage,
    required this.onOpenProfile,
  });

  final String type; // 'likedBy' | 'footprints'
  final String emptyMessage;
  final String lockedTitle;
  final String lockedMessage;
  final Future<void> Function(String userId) onOpenProfile;

  @override
  State<_InboxList> createState() => _InboxListState();
}

class _InboxListState extends State<_InboxList> {
  // null = モザイク対象（サーバーが相手のIDも名前も返さない）
  final List<_UserSummary?> _items = [];
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  bool _locked = false;
  int? _total;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _callable(
        'getInbox',
      ).call({'type': widget.type, if (_cursor != null) 'cursor': _cursor});
      final data = Map<String, dynamic>.from(res.data as Map);
      final rawItems = (data['items'] as List?) ?? const [];
      final parsed = rawItems.map<_UserSummary?>((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['id'];
        return id is String ? _UserSummary.fromMap(id, m) : null;
      }).toList();

      if (!mounted) return;
      setState(() {
        _locked = data['locked'] == true;
        final total = data['total'];
        if (total is num) _total = total.toInt();
        _items.addAll(parsed);
        _cursor = data['nextCursor'] as String?;
        _hasMore = _cursor != null;
      });
    } catch (e) {
      debugPrint('${widget.type} 取得エラー: $e');
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _items.clear();
      _cursor = null;
      _hasMore = true;
      _total = null;
    });
    await _loadMore();
  }

  Future<void> _showUpgradeDialog() async {
    final goToPlans = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          widget.lockedTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          widget.lockedMessage,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              '閉じる',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.point,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'プラン一覧を見る',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (goToPlans == true && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
      );
      // 💡 プラン変更後に戻ってきたら、サーバーに再判定させる
      if (mounted) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && _error != null) {
      return _RetryView(onRetry: _refresh);
    }
    if (_items.isEmpty && (_loading || _hasMore)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: _EmptyScrollable(message: widget.emptyMessage),
      );
    }

    final bool showFooter = _hasMore || _error != null;
    final int headerCount = _locked ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: headerCount + _items.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (_locked && index == 0) {
            return _LockedBanner(
              count: _total ?? _items.length,
              onTap: _showUpgradeDialog,
            );
          }
          final i = index - headerCount;
          if (i < _items.length) {
            final user = _items[i];
            if (user == null) return _MaskedTile(onTap: _showUpgradeDialog);
            return _UserTile(
              user: user,
              onTap: () => widget.onOpenProfile(user.id),
            );
          }
          if (_error != null) {
            return TextButton(onPressed: _loadMore, child: const Text('再読み込み'));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          return const _LoadingFooter();
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 通報ダイアログ（状態をWidget側で保持し、二重送信を確実に防ぐ）
// ----------------------------------------------------------------------------
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.reporterId,
    required this.peerId,
    required this.peerName,
  });

  final String reporterId;
  final String peerId;
  final String peerName;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _controller.text.trim();
    if (reason.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // 💡 決定的IDにより、同じ相手への通報の連投をルールで弾く
      await _db
          .collection('reports')
          .doc('${widget.reporterId}_${widget.peerId}')
          .set({
            'reporterId': widget.reporterId,
            'reportedId': widget.peerId,
            'reason': reason,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(_kNetworkTimeout);
      if (mounted) Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      debugPrint('通報送信エラー: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.code == 'permission-denied'
            ? 'このユーザーは既に通報済みです。'
            : '通報の送信に失敗しました。もう一度お試しください。';
      });
    } catch (e) {
      debugPrint('通報送信エラー: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorMessage(e, '通報の送信に失敗しました。もう一度お試しください。');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        '${widget.peerName} さんを通報',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '不適切な言動や規約違反がありましたか？\n理由を詳しく教えてください。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            enabled: !_submitting,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '通報理由を入力...',
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.all(16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text(
                  'キャンセル',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '通報する',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 小さな共通ウィジェット
// ----------------------------------------------------------------------------
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.onTap, this.trailing});

  final _UserSummary user;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _Avatar(url: user.imageUrl),
      title: Row(
        children: [
          Flexible(child: Text(user.name, overflow: TextOverflow.ellipsis)),
          if (user.gender != null) ...[
            const SizedBox(width: 6),
            _GenderBadge(gender: user.gender!),
          ],
        ],
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final hasImage = url.isNotEmpty;
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.grey[200],
      // 💡 一覧ではフルサイズ画像をデコードせず縮小してメモリを節約する
      backgroundImage: hasImage
          ? ResizeImage(NetworkImage(url), width: 132)
          : null,
      onBackgroundImageError: hasImage ? (_, __) {} : null,
      child: hasImage ? null : const Icon(Icons.person, color: Colors.grey),
    );
  }
}

class _GenderBadge extends StatelessWidget {
  const _GenderBadge({required this.gender});
  final String gender;

  @override
  Widget build(BuildContext context) {
    final Color base = gender == '男性'
        ? Colors.blue
        : (gender == '女性' ? Colors.pink : Colors.grey);
    final IconData icon = gender == '男性'
        ? Icons.male
        : (gender == '女性' ? Icons.female : Icons.transgender);

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: base, size: 12),
    );
  }
}

class _MaskedTile extends StatelessWidget {
  const _MaskedTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: CircleAvatar(
          radius: 22,
          backgroundColor: Colors.grey[300],
          child: const Icon(Icons.person, color: Colors.white),
        ),
      ),
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('●●●●', style: TextStyle(color: Colors.grey, letterSpacing: 2)),
          SizedBox(width: 6),
          Icon(Icons.lock, size: 14, color: Colors.grey),
        ],
      ),
      subtitle: const Text(
        'プラン登録で誰か確認できます',
        style: TextStyle(fontSize: 11, color: Colors.grey),
      ),
      onTap: onTap,
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Material(
        color: AppColors.point.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.lock, color: AppColors.point, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$count 人が表示待ちです',
                    style: TextStyle(
                      color: AppColors.point,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 12, color: AppColors.point),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyScrollable extends StatelessWidget {
  const _EmptyScrollable({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    // RefreshIndicator を効かせるためにスクロール可能にしておく
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 160),
        Center(
          child: Text(message, style: const TextStyle(color: Colors.grey)),
        ),
      ],
    );
  }
}

class _RetryView extends StatelessWidget {
  const _RetryView({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('読み込みに失敗しました', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('再読み込み')),
        ],
      ),
    );
  }
}

class _LoadingFooter extends StatelessWidget {
  const _LoadingFooter();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
