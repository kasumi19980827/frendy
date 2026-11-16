import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/mypage/mypage_screen.dart';
import 'package:matching_app/screens/talk/talk_screen.dart';

// ============================================================================
// トーク一覧
//
// chat_rooms/{小さいuid}_{大きいuid} のフィールド:
//   users           : [uid, uid]
//   lastMessage     : String
//   lastMessageTime : Timestamp
//   unreadCount     : { uid: int }
//   messageCountBy  : { uid: int }        … Cloud Functions(onMessageCreated)が自動で数える
//   hiddenAt        : { uid: Timestamp }  … 「トークを非表示」にした時刻（自分の分だけ）
//   blockedBy       : [uid]               … Cloud Functions(blockUser)が書き込む
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const int _kRoomPageSize = 30;
const int _kWhereInLimit = 30;
const int _kRequiredMessages = 4; // 友達申請に必要な「お互いの送信数」
const int _kPeerCacheMax = 500;
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
      case 'already-exists':
        return e.message ?? fallback;
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

void _toast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.redAccent : null,
      ),
    );
}

bool _isNameInvalid(String name) =>
    name.trim().isEmpty || name.trim() == '名前未設定';

// ----------------------------------------------------------------------------
// モデル
// ----------------------------------------------------------------------------
class _Peer {
  const _Peer({required this.name, required this.imageUrl});

  final String name;
  final String imageUrl;

  factory _Peer.fromMap(Map<String, dynamic> d) {
    String url = '';
    final thumb = d['thumbnailUrl'];
    final images = d['imageUrls'];
    if (thumb is String && thumb.isNotEmpty) {
      url = thumb;
    } else if (images is List && images.isNotEmpty && images.first is String) {
      url = images.first as String;
    }
    if (!url.startsWith('https://')) url = '';

    final rawName = d['name'];
    return _Peer(
      name: rawName is String && rawName.trim().isNotEmpty ? rawName : 'ユーザー',
      imageUrl: url,
    );
  }
}

class _Room {
  const _Room({
    required this.id,
    required this.peerId,
    required this.lastMessage,
    required this.lastTime,
    required this.unreadCount,
    required this.myCount,
    required this.peerCount,
    required this.isBlocked,
    required this.hiddenAt,
  });

  final String id;
  final String peerId;
  final String lastMessage;
  final Timestamp? lastTime;
  final int unreadCount;
  final int myCount;
  final int peerCount;
  final bool isBlocked;
  final Timestamp? hiddenAt;

  bool get canSendRequest =>
      myCount >= _kRequiredMessages && peerCount >= _kRequiredMessages;

  static int _readInt(Object? map, String key) {
    if (map is Map && map[key] is num) return (map[key] as num).toInt();
    return 0;
  }

  static _Room? fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String myId,
  ) {
    final d = doc.data();
    final users = d['users'];
    if (users is! List) return null;

    final String peerId = users.whereType<String>().firstWhere(
      (id) => id != myId,
      orElse: () => '',
    );
    if (peerId.isEmpty) return null;

    final blockedBy = d['blockedBy'];
    final hidden = d['hiddenAt'];

    return _Room(
      id: doc.id,
      peerId: peerId,
      lastMessage: d['lastMessage'] is String ? d['lastMessage'] as String : '',
      lastTime: d['lastMessageTime'] is Timestamp
          ? d['lastMessageTime'] as Timestamp
          : null,
      unreadCount: _readInt(d['unreadCount'], myId),
      myCount: _readInt(d['messageCountBy'], myId),
      peerCount: _readInt(d['messageCountBy'], peerId),
      // 💡 どちらか一方でもブロックしていれば、お互いの一覧から消す
      isBlocked: blockedBy is List && blockedBy.isNotEmpty,
      hiddenAt: hidden is Map && hidden[myId] is Timestamp
          ? hidden[myId] as Timestamp
          : null,
    );
  }
}

// ----------------------------------------------------------------------------
// 画面
// ----------------------------------------------------------------------------
class MessageScreen extends StatefulWidget {
  const MessageScreen({super.key});

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  late final String _myId;
  String _myName = '';
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _mySub;

  // 💡 Streamは build の外で一度だけ作る（再描画のたびに再購読しない）
  Stream<QuerySnapshot<Map<String, dynamic>>>? _roomsStream;
  int _limit = _kRoomPageSize;

  // 相手プロフィールのキャッシュ（ページ単位でまとめて取得）
  final Map<String, _Peer> _peers = {};
  String? _peerIdsSig;
  Future<void>? _peerFetch;

  // 非表示・ブロック直後に、サーバー反映を待たず一覧から消すための記録
  final Map<String, Timestamp?> _locallyHidden = {};
  final Set<String> _locallyBlocked = {};

  @override
  void initState() {
    super.initState();
    _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (_myId.isEmpty) return;

    _mySub = _db.collection('users').doc(_myId).snapshots().listen((snap) {
      final raw = snap.data()?['name'];
      final name = raw is String ? raw : '';
      if (mounted && name != _myName) setState(() => _myName = name);
    }, onError: (Object e) => debugPrint('自分のプロフィール取得エラー: $e'));
    _subscribeRooms();
  }

  @override
  void dispose() {
    _mySub?.cancel();
    super.dispose();
  }

  void _subscribeRooms() {
    _roomsStream = _db
        .collection('chat_rooms')
        .where('users', arrayContains: _myId)
        .where('lastMessageTime', isNull: false)
        .orderBy('lastMessageTime', descending: true)
        .limit(_limit)
        .snapshots();
  }

  void _loadMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _limit += _kRoomPageSize;
        _subscribeRooms();
      });
    });
  }

  Future<void> _fetchPeers(List<String> ids) async {
    final missing = ids.where((id) => !_peers.containsKey(id)).toSet().toList();
    final chunks = <List<String>>[];
    for (var i = 0; i < missing.length; i += _kWhereInLimit) {
      chunks.add(
        missing.sublist(i, math.min(i + _kWhereInLimit, missing.length)),
      );
    }

    // 💡 1人ずつ get() せず、30人ずつまとめて並列取得する
    await Future.wait(
      chunks.map((chunk) async {
        try {
          final snap = await _db
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get()
              .timeout(_kNetworkTimeout);
          for (final doc in snap.docs) {
            _peers[doc.id] = _Peer.fromMap(doc.data());
          }
        } catch (e) {
          debugPrint('相手プロフィール取得エラー: $e');
        }
      }),
    );

    while (_peers.length > _kPeerCacheMax) {
      _peers.remove(_peers.keys.first);
    }
  }

  bool _isVisible(_Room room) {
    if (room.isBlocked || _locallyBlocked.contains(room.peerId)) return false;

    // 非表示にした時刻より後に新しいメッセージが来ていれば再表示する
    final hiddenAt = room.hiddenAt;
    if (hiddenAt != null &&
        (room.lastTime == null || room.lastTime!.compareTo(hiddenAt) <= 0)) {
      return false;
    }

    if (_locallyHidden.containsKey(room.id) &&
        _locallyHidden[room.id] == room.lastTime) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'トーク一覧',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _myId.isEmpty
          ? const Center(child: Text('ログインが必要です'))
          : _buildRoomList(),
    );
  }

  Widget _buildRoomList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _roomsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('トーク一覧取得エラー: ${snapshot.error}');
          return const Center(
            child: Text('読み込みに失敗しました', style: TextStyle(color: Colors.grey)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rawDocs = snapshot.data!.docs;
        final bool hasMore = rawDocs.length >= _limit;

        final rooms = rawDocs
            .map((d) => _Room.fromDoc(d, _myId))
            .whereType<_Room>()
            .where(_isVisible)
            .toList();

        if (rooms.isEmpty && !hasMore) {
          return const Center(
            child: Text('まだトークがありません🌿', style: TextStyle(color: Colors.grey)),
          );
        }

        final peerIds = rooms.map((r) => r.peerId).toList();
        final sig = peerIds.join(',');
        if (sig != _peerIdsSig) {
          _peerIdsSig = sig;
          _peerFetch = _fetchPeers(peerIds);
        }

        return FutureBuilder<void>(
          future: _peerFetch,
          builder: (context, fetchSnap) {
            final bool loadingPeers =
                fetchSnap.connectionState != ConnectionState.done;
            final visible = rooms
                .where((r) => _peers.containsKey(r.peerId))
                .toList();

            if (visible.isEmpty && loadingPeers) {
              return const Center(child: CircularProgressIndicator());
            }
            if (visible.isEmpty && !hasMore) {
              return const Center(
                child: Text(
                  'まだトークがありません🌿',
                  style: TextStyle(color: Colors.grey),
                ),
              );
            }

            return ListView.builder(
              itemCount: visible.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= visible.length) {
                  _loadMore(); // 末尾まで来たら次の30件を読み込む
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
                final room = visible[index];
                return _buildRoomTile(room, _peers[room.peerId]!);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRoomTile(_Room room, _Peer peer) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 8),
      leading: CircleAvatar(
        radius: 28,
        backgroundColor: Colors.grey[200],
        backgroundImage: peer.imageUrl.isNotEmpty
            ? ResizeImage(NetworkImage(peer.imageUrl), width: 168)
            : null,
        onBackgroundImageError: peer.imageUrl.isNotEmpty ? (_, __) {} : null,
        child: peer.imageUrl.isEmpty
            ? const Icon(Icons.person, color: Colors.grey)
            : null,
      ),
      title: Text(
        peer.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        room.lastMessage.isEmpty ? 'メッセージはありません' : room.lastMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 💡 お互いが4通以上送ったときだけ表示（条件はサーバー側でも再確認する）
          if (room.canSendRequest)
            _FriendRequestButton(
              key: ValueKey('req_${room.peerId}'),
              myId: _myId,
              myName: _myName,
              peerId: room.peerId,
              peerName: peer.name,
            ),
          const SizedBox(width: 6),
          _TimeBadge(time: room.lastTime, unreadCount: room.unreadCount),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.grey),
            onPressed: () => _showActionSheet(room, peer),
          ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TalkScreen(
              userName: peer.name,
              peerId: room.peerId,
              peerImageUrl: peer.imageUrl,
            ),
          ),
        );
      },
    );
  }

  // --- アクションシート ---
  void _showActionSheet(_Room room, _Peer peer) {
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
                peer.name,
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
                  _showReportDialog(room.peerId, peer.name);
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
                  _confirmAndBlock(room.peerId, peer.name);
                },
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.visibility_off_outlined,
                title: 'トークを非表示',
                subtitle: '一覧から非表示にします',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmAndHide(room);
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _showReportDialog(String peerId, String peerName) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _ReportDialog(reporterId: _myId, peerId: peerId, peerName: peerName),
    );
    if (sent == true && mounted) {
      _toast(context, '報告ありがとうございます。運営で確認いたします。');
    }
  }

  // --- ブロック（Cloud Functions 経由。相手のデータには直接触らない） ---
  Future<void> _confirmAndBlock(String peerId, String peerName) async {
    final ok = await _confirm(
      title: '$peerName さんをブロックしますか？',
      message: 'お互いにメッセージの送受信ができなくなり、トーク一覧や友達リストからも削除されます。',
      confirmLabel: 'ブロック',
    );
    if (!ok) return;

    try {
      await _callable('blockUser').call({'peerId': peerId});
      if (!mounted) return;
      setState(() => _locallyBlocked.add(peerId));
      _toast(context, 'ブロックして友達解除しました');
    } catch (e) {
      debugPrint('ブロックエラー: $e');
      if (mounted) {
        _toast(
          context,
          _errorMessage(e, 'ブロックに失敗しました。もう一度お試しください。'),
          isError: true,
        );
      }
    }
  }

  // --- トークを非表示（自分の画面からだけ消す。相手側には影響させない） ---
  Future<void> _confirmAndHide(_Room room) async {
    final ok = await _confirm(
      title: 'トークを非表示にしますか？',
      message: '一覧から非表示になります。\n新しいメッセージが届くと再度表示されます。',
      confirmLabel: '非表示',
    );
    if (!ok) return;

    setState(() => _locallyHidden[room.id] = room.lastTime);

    try {
      await _db
          .collection('chat_rooms')
          .doc(room.id)
          .update({'hiddenAt.$_myId': FieldValue.serverTimestamp()})
          .timeout(_kNetworkTimeout);
      if (mounted) _toast(context, 'トークを非表示にしました');
    } on TimeoutException {
      if (mounted) _toast(context, '通信が不安定です。接続が回復すると反映されます。');
    } catch (e) {
      debugPrint('非表示処理エラー: $e');
      if (!mounted) return;
      setState(() => _locallyHidden.remove(room.id));
      _toast(context, '非表示にできませんでした。もう一度お試しください。', isError: true);
    }
  }
}

// ----------------------------------------------------------------------------
// 友達申請ボタン（友達状態・送信済み・受信済みをリアルタイムで出し分け）
// ----------------------------------------------------------------------------
class _FriendRequestButton extends StatefulWidget {
  const _FriendRequestButton({
    super.key,
    required this.myId,
    required this.myName,
    required this.peerId,
    required this.peerName,
  });

  final String myId;
  final String myName;
  final String peerId;
  final String peerName;

  @override
  State<_FriendRequestButton> createState() => _FriendRequestButtonState();
}

class _FriendRequestButtonState extends State<_FriendRequestButton> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _friendStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _outgoingStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _incomingStream;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _friendStream = _db
        .collection('users')
        .doc(widget.myId)
        .collection('friends')
        .doc(widget.peerId)
        .snapshots();
    // 💡 申請IDは {送信者}_{受信者} に固定しているので、検索せず1件を直接見る
    _outgoingStream = _db
        .collection('friend_requests')
        .doc('${widget.myId}_${widget.peerId}')
        .snapshots();
    _incomingStream = _db
        .collection('friend_requests')
        .doc('${widget.peerId}_${widget.myId}')
        .snapshots();
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_isNameInvalid(widget.myName)) {
      _showProfileSetupDialog();
      return;
    }

    setState(() => _sending = true);
    try {
      await _callable('sendFriendRequest').call({'peerId': widget.peerId});
      if (mounted) _toast(context, '${widget.peerName}さんに友達申請を送りました');
    } catch (e) {
      debugPrint('友達申請エラー: $e');
      if (mounted) {
        _toast(
          context,
          _errorMessage(e, '友達申請に失敗しました。もう一度お試しください。'),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showProfileSetupDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('プロフィールを確認'),
        content: const Text('友達申請をするには、先にプロフィールで名前を設定してください！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.point),
            onPressed: () {
              Navigator.pop(dialogContext);
              // 💡 pushAndRemoveUntil だと下のタブバーごと消えてしまうため push にする
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MypageScreen()),
              );
            },
            child: const Text('設定する', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _friendStream,
      builder: (context, friendSnap) {
        if (!friendSnap.hasData || friendSnap.hasError) {
          return const SizedBox.shrink();
        }
        if (friendSnap.data!.exists) return const SizedBox.shrink(); // 既に友達

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _outgoingStream,
          builder: (context, outSnap) {
            if (!outSnap.hasData || outSnap.hasError) {
              return const SizedBox.shrink();
            }
            if (outSnap.data!.exists) return _label('申請中');

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _incomingStream,
              builder: (context, inSnap) {
                if (!inSnap.hasData || inSnap.hasError) {
                  return const SizedBox.shrink();
                }
                if (inSnap.data!.exists) return _label('申請あり');

                final bool nameInvalid = _isNameInvalid(widget.myName);
                return ElevatedButton(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: nameInvalid
                        ? Colors.grey[400]
                        : AppColors.bg,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(50, 30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '友達申請',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// 時刻と未読バッジ
// ----------------------------------------------------------------------------
class _TimeBadge extends StatelessWidget {
  const _TimeBadge({required this.time, required this.unreadCount});

  final Timestamp? time;
  final int unreadCount;

  String _format(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    }
    if (d.year == now.year) return '${d.month}/${d.day}';
    return '${d.year}/${d.month}/${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (time == null) return const SizedBox.shrink();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _format(time!.toDate()),
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        if (unreadCount > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              unreadCount > 99 ? '99+' : '$unreadCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 通報ダイアログ（二重送信防止・入力上限・連投防止つき）
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
