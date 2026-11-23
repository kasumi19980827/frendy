import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// ============================================================================
// ブロック中のユーザー
//
// 💡 ブロックの保存場所は2つある（移行期間中）
//    ・新しい方式：users/{自分}/blocks/{相手}（Cloud Functions の blockUser が作る）
//    ・古い方式  ：users/{自分} の blocks 配列
//    両方を合わせて表示し、解除はサーバー（unblockUser）で両方まとめて行う。
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const int _kWhereInLimit = 30;
const int _kMaxBlocksShown = 300; // ブロック数が極端に多い場合でも読み込みすぎない
const String _kFunctionsRegion = 'asia-northeast1';

FirebaseFirestore get _db => FirebaseFirestore.instance;

class _BlockedUser {
  const _BlockedUser({
    required this.id,
    required this.name,
    required this.imageUrl,
  });
  final String id;
  final String name;
  final String imageUrl;
}

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  late final String _myId;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _legacySub;

  // 新しい方式（新しい順）と古い方式のID
  List<String> _newIds = [];
  List<String> _legacyIds = [];
  bool _newLoaded = false;
  bool _legacyLoaded = false;
  Object? _error;

  final Map<String, _BlockedUser> _profiles = {};
  String? _fetchedSig;
  bool _fetchingProfiles = false;
  bool _profileFetchFailed = false; // 一部でも取得に失敗したら「再読み込み」を出す

  final Set<String> _processingIds = {};
  final Set<String> _removedIds = {}; // 解除直後に、反映を待たず一覧から消す

  @override
  void initState() {
    super.initState();
    _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_myId.isEmpty) return;

    final myRef = _db.collection('users').doc(_myId);

    _newSub = myRef
        .collection('blocks')
        .orderBy('createdAt', descending: true)
        .limit(_kMaxBlocksShown)
        .snapshots()
        .listen(
          (snap) {
            _newIds = snap.docs.map((d) => d.id).toList();
            _newLoaded = true;
            _onIdsChanged();
          },
          onError: (Object e) {
            debugPrint('ブロック一覧（新）取得エラー: $e');
            if (mounted) setState(() => _error = e);
          },
        );

    // ⚠️ 移行用：古い方式の配列も読む（データ移行が終わったら削除する）
    _legacySub = myRef.snapshots().listen(
      (snap) {
        final raw = snap.data()?['blocks'];
        _legacyIds = raw is List ? raw.whereType<String>().toList() : [];
        _legacyLoaded = true;
        _onIdsChanged();
      },
      onError: (Object e) {
        debugPrint('ブロック一覧（旧）取得エラー: $e');
        if (mounted) setState(() => _error = e);
      },
    );
  }

  @override
  void dispose() {
    _newSub?.cancel();
    _legacySub?.cancel();
    super.dispose();
  }

  List<String> get _allIds {
    final seen = <String>{};
    return [..._newIds, ..._legacyIds]
        .where(
          (id) => id.isNotEmpty && !_removedIds.contains(id) && seen.add(id),
        )
        .toList();
  }

  void _onIdsChanged() {
    if (!mounted) return;
    setState(() {});
    final ids = _allIds;
    final sig = ids.join(',');
    if (sig != _fetchedSig) {
      _fetchedSig = sig;
      _fetchProfiles(ids);
    }
  }

  // 失敗した分をもう一度取りに行く
  void _retryProfiles() {
    setState(() => _profileFetchFailed = false);
    _fetchedSig = null;
    _onIdsChanged();
  }

  // 💡 30人ずつまとめて並列で取得する
  Future<void> _fetchProfiles(List<String> ids) async {
    final missing = ids.where((id) => !_profiles.containsKey(id)).toList();
    if (missing.isEmpty) return;
    if (mounted) {
      setState(() {
        _fetchingProfiles = true;
        _profileFetchFailed = false;
      });
    }
    bool failed = false;
    final chunks = <List<String>>[];
    for (var i = 0; i < missing.length; i += _kWhereInLimit) {
      chunks.add(
        missing.sublist(i, math.min(i + _kWhereInLimit, missing.length)),
      );
    }

    await Future.wait(
      chunks.map((chunk) async {
        try {
          final snap = await _db
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get()
              .timeout(_kNetworkTimeout);
          final found = <String>{};
          for (final doc in snap.docs) {
            found.add(doc.id);
            final d = doc.data();
            final images = d['imageUrls'];
            String url =
                images is List && images.isNotEmpty && images.first is String
                ? images.first as String
                : '';
            if (!url.startsWith('https://')) url = '';
            final rawName = d['name'];
            _profiles[doc.id] = _BlockedUser(
              id: doc.id,
              name: rawName is String && rawName.trim().isNotEmpty
                  ? rawName
                  : 'ユーザー',
              imageUrl: url,
            );
          }
          // 💡 退会済みのユーザーも、ブロック自体は解除できるよう表示は残す
          for (final id in chunk.where((id) => !found.contains(id))) {
            _profiles[id] = _BlockedUser(
              id: id,
              name: '退会済みユーザー',
              imageUrl: '',
            );
          }
        } catch (e) {
          debugPrint('ブロック中ユーザー取得エラー: $e');
          failed = true;
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      _fetchingProfiles = false;
      _profileFetchFailed = failed;
      // 💡 失敗したときは、次の変化や「再読み込み」で取り直せるようにする
      if (failed) _fetchedSig = null;
    });
  }

  String _unblockErrorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      switch (e.code) {
        case 'unauthenticated':
          return 'ログインの有効期限が切れました。再度ログインしてください。';
        case 'deadline-exceeded':
        case 'unavailable':
          return '通信状況を確認して、もう一度お試しください。';
        case 'invalid-argument':
        case 'failed-precondition':
          return e.message ?? '解除に失敗しました。もう一度お試しください。';
      }
    }
    if (e is TimeoutException) return '通信がタイムアウトしました。もう一度お試しください。';
    return '解除に失敗しました。もう一度お試しください。';
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

  // --- ブロック解除（サーバーで新旧両方の保存場所から消す） ---
  Future<void> _unblockUser(_BlockedUser user) async {
    if (_processingIds.contains(user.id)) return;
    setState(() => _processingIds.add(user.id));

    try {
      await FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
          .httpsCallable(
            'unblockUser',
            options: HttpsCallableOptions(timeout: _kNetworkTimeout),
          )
          .call({'peerId': user.id});
      if (!mounted) return;
      setState(() => _removedIds.add(user.id));
      _toast('${user.name} さんのブロックを解除しました');
    } catch (e) {
      debugPrint('ブロック解除エラー: $e');
      _toast(_unblockErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _processingIds.remove(user.id));
    }
  }

  void _showUnblockDialog(_BlockedUser user) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ブロック解除'),
        content: Text(
          '${user.name} さんのブロックを解除しますか？\n解除するとお互いのアプリに再度表示されるようになります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _unblockUser(user);
            },
            child: const Text(
              '解除する',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'ブロック中のユーザー',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_myId.isEmpty) {
      return const Center(
        child: Text('ログインが必要です', style: TextStyle(color: Colors.grey)),
      );
    }
    if (_error != null && !(_newLoaded && _legacyLoaded)) {
      return const Center(
        child: Text('読み込みに失敗しました', style: TextStyle(color: Colors.grey)),
      );
    }
    if (!_newLoaded || !_legacyLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final ids = _allIds;
    if (ids.isEmpty) {
      return const Center(
        child: Text(
          'ブロック中のユーザーはいません',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    final users = ids
        .map((id) => _profiles[id])
        .whereType<_BlockedUser>()
        .toList();
    if (users.isEmpty) {
      // 💡 取得に失敗したときは、ぐるぐるを出し続けず再読み込みボタンを出す
      if (_profileFetchFailed && !_fetchingProfiles) return _buildRetry();
      return const Center(child: CircularProgressIndicator());
    }

    final bool showRetryFooter = _profileFetchFailed && !_fetchingProfiles;

    return ListView.builder(
      itemCount: users.length + (showRetryFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= users.length) return _buildRetry();
        final user = users[index];
        final bool isProcessing = _processingIds.contains(user.id);
        final bool hasImage = user.imageUrl.isNotEmpty;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[200],
            // 💡 一度読んだアイコンは端末に保存し、次回からダウンロードしない
            backgroundImage: hasImage
                ? ResizeImage(
                    CachedNetworkImageProvider(user.imageUrl),
                    width: 144,
                  )
                : null,
            onBackgroundImageError: hasImage ? (_, __) {} : null,
            child: hasImage
                ? null
                : const Icon(Icons.person, color: Colors.grey),
          ),
          title: Text(
            user.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SizedBox(
            width: 64,
            height: 32,
            child: OutlinedButton(
              onPressed: isProcessing ? null : () => _showUnblockDialog(user),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                disabledForegroundColor: Colors.grey,
                side: BorderSide(
                  color: isProcessing ? Colors.grey[300]! : Colors.redAccent,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(60, 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isProcessing
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '解除',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRetry() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '一部のユーザー情報を読み込めませんでした',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            TextButton(onPressed: _retryProfiles, child: const Text('再読み込み')),
          ],
        ),
      ),
    );
  }
}
