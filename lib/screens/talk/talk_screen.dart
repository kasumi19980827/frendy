import 'dart:async';
import 'dart:ui'; // ぼかし効果（ImageFilter）

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/screens/auth/identity_verification_screen.dart';

// ============================================================================
// トーク画面（1対1のメッセージ）
//
// 💡 5万人規模を想定した作り
//  ・メッセージは新しい順に30件ずつ読み込む（上にスクロールすると続きを読む）
//  ・既読は「メッセージ1件ずつ」ではなく、トークルームの lastReadAt に
//    「どこまで読んだか（時刻）」を1回書くだけ
//  ・最新メッセージ・未読数・送信数はサーバー（onMessageCreated）が更新する
//    → アプリが書き込むのは「メッセージ本体」だけ
//
// 💡 セキュリティ
//  ・年齢確認・ブロック・本文の長さはセキュリティルールでも確認している
//    （改造アプリでこの画面のチェックを外しても送れない）
//  ・トークルームはサーバー（startTalk）だけが作れる（月間上限を回避させない）
// ============================================================================

const String _kFunctionsRegion = 'asia-northeast1';
const int _kPageSize = 30;
const int _kMaxLoaded = 2000; // 1つの画面で読み込むメッセージの上限
const int _kMaxLength = 1000; // 1通の最大文字数（ルールと同じ）
const Duration _kSendInterval = Duration(milliseconds: 700); // 連打防止
const Duration _kNetworkTimeout = Duration(seconds: 20);

FirebaseFirestore get _db => FirebaseFirestore.instance;

// トークルームの状態
enum _RoomState { loading, ready, starting, unavailable }

class TalkScreen extends StatefulWidget {
  final String userName;
  final String peerId;
  final String peerImageUrl;

  const TalkScreen({
    super.key,
    required this.userName,
    required this.peerId,
    required this.peerImageUrl,
  });

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final String _myId;
  late final String _chatRoomId;
  late final DocumentReference<Map<String, dynamic>> _roomRef;

  // 年齢確認
  String _ageStatus =
      'unsubmitted'; // unsubmitted / pending / verified / rejected
  bool _isCheckingVerification = true;
  bool get _isVerified => _ageStatus == 'verified';

  // トークルーム
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _roomSub;
  _RoomState _roomState = _RoomState.loading;
  String _unavailableMessage = '';
  bool _startTalkTried = false;
  bool _isBlocked = false;
  Timestamp? _peerLastReadAt;
  int _myUnread = 0;

  // メッセージ
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _messages = [];
  int _limit = _kPageSize;
  bool _messagesLoaded = false;
  bool _hasMore = false;
  bool _messagesError = false;

  // 既読・送信
  bool _isMarkingRead = false;
  bool _isForeground = true;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ids = [_myId, widget.peerId]..sort();
    _chatRoomId = ids.join('_');
    _roomRef = _db.collection('chat_rooms').doc(_chatRoomId);

    _scrollController.addListener(_onScroll);

    if (_myId.isEmpty || widget.peerId.isEmpty || widget.peerId == _myId) {
      _isCheckingVerification = false;
      _roomState = _RoomState.unavailable;
      _unavailableMessage = 'このトークは開けません';
      return;
    }

    _checkMyAgeVerification();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roomSub?.cancel();
    _messagesSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 💡 アプリが裏に回っている間は既読にしない
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) _markAsReadIfNeeded();
  }

  // ==========================================================================
  // 年齢確認
  // ==========================================================================
  Future<void> _checkMyAgeVerification() async {
    if (mounted) setState(() => _isCheckingVerification = true);
    String status = 'unsubmitted';
    try {
      final doc = await _db
          .collection('users')
          .doc(_myId)
          .get()
          .timeout(_kNetworkTimeout);
      final raw = doc.data()?['ageVerified'];
      if (raw is String) status = raw;
    } catch (e) {
      debugPrint('年齢確認チェックエラー: $e');
    }
    if (!mounted) return;

    setState(() {
      _ageStatus = status;
      _isCheckingVerification = false;
    });

    // 承認済みになったら、トークルームとメッセージの読み込みを始める
    if (_isVerified) _listenRoom();
  }

  void _openVerification() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const IdentityVerificationScreen()),
    ).then((_) {
      if (mounted && !_isVerified) _checkMyAgeVerification();
    });
  }

  // ==========================================================================
  // トークルーム
  // ==========================================================================
  void _listenRoom() {
    if (_roomSub != null) return;
    _roomSub = _roomRef.snapshots().listen(
      (snap) {
        if (!mounted) return;
        if (!snap.exists) {
          _startTalkIfNeeded();
          return;
        }

        final data = snap.data() ?? {};
        final blockedBy = data['blockedBy'];
        final unread = data['unreadCount'];
        final lastReadAt = data['lastReadAt'];

        setState(() {
          _roomState = _RoomState.ready;
          _isBlocked = blockedBy is List && blockedBy.isNotEmpty;
          _myUnread = unread is Map && unread[_myId] is num
              ? (unread[_myId] as num).toInt()
              : 0;
          _peerLastReadAt =
              lastReadAt is Map && lastReadAt[widget.peerId] is Timestamp
              ? lastReadAt[widget.peerId] as Timestamp
              : null;
        });

        _listenMessages();
        _markAsReadIfNeeded();
      },
      onError: (Object e) {
        debugPrint('トークルーム取得エラー: $e');
        if (!mounted) return;
        setState(() {
          _roomState = _RoomState.unavailable;
          _unavailableMessage = 'トークを読み込めませんでした';
        });
      },
    );
  }

  // 💡 ルームがまだない場合（古い画面から開いた場合など）は、サーバーで作る。
  //    月間のトーク開始上限もサーバーで確認される。
  Future<void> _startTalkIfNeeded() async {
    if (_startTalkTried) {
      setState(() {
        _roomState = _RoomState.unavailable;
        _unavailableMessage = 'トークを開始できませんでした';
      });
      return;
    }
    _startTalkTried = true;
    setState(() => _roomState = _RoomState.starting);

    try {
      await FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
          .httpsCallable(
            'startTalk',
            options: HttpsCallableOptions(timeout: _kNetworkTimeout),
          )
          .call({'peerId': widget.peerId});
      // 成功すると、ルームの監視が自動で ready に切り替わる
    } on FirebaseFunctionsException catch (e) {
      debugPrint('トーク開始エラー: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() {
        _roomState = _RoomState.unavailable;
        _unavailableMessage = switch (e.code) {
          'resource-exhausted' => e.message ?? '今月のトーク開始上限に達しました',
          'failed-precondition' => e.message ?? 'このユーザーとはやり取りできません',
          _ => 'トークを開始できませんでした。時間をおいてお試しください',
        };
      });
    } catch (e) {
      debugPrint('トーク開始エラー: $e');
      if (!mounted) return;
      setState(() {
        _roomState = _RoomState.unavailable;
        _unavailableMessage = 'トークを開始できませんでした。時間をおいてお試しください';
      });
    }
  }

  // ==========================================================================
  // メッセージ（新しい順に _limit 件だけ監視する）
  // ==========================================================================
  void _listenMessages() {
    if (_messagesSub != null) return;
    _subscribeMessages();
  }

  void _subscribeMessages() {
    _messagesSub?.cancel();
    _messagesSub = _roomRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(_limit)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            setState(() {
              _messages = snap.docs;
              _messagesLoaded = true;
              _messagesError = false;
              _hasMore = snap.docs.length >= _limit && _limit < _kMaxLoaded;
            });
          },
          onError: (Object e) {
            debugPrint('メッセージ取得エラー: $e');
            if (mounted) setState(() => _messagesError = true);
          },
        );
  }

  // 💡 一番上（古い方）まで近づいたら、30件追加で読み込む
  void _onScroll() {
    if (!_hasMore || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _hasMore = false; // 読み込み中に何度も呼ばれないようにする
      _limit = (_limit + _kPageSize).clamp(_kPageSize, _kMaxLoaded);
      _subscribeMessages();
    }
  }

  // ==========================================================================
  // 既読（未読があるときだけ、ルームに1回書き込む）
  // ==========================================================================
  Future<void> _markAsReadIfNeeded() async {
    if (!_isVerified ||
        !_isForeground ||
        _roomState != _RoomState.ready ||
        _myUnread <= 0 ||
        _isMarkingRead) {
      return;
    }
    _isMarkingRead = true;
    try {
      await _roomRef
          .update({
            'unreadCount.$_myId': 0,
            'lastReadAt.$_myId': FieldValue.serverTimestamp(),
          })
          .timeout(_kNetworkTimeout);
    } catch (e) {
      debugPrint('既読エラー: $e');
    } finally {
      _isMarkingRead = false;
    }
  }

  // ==========================================================================
  // 送信（アプリが書くのはメッセージ本体だけ）
  // ==========================================================================
  Future<void> _sendMessage() async {
    if (!_isVerified) {
      _showVerificationRequiredDialog();
      return;
    }
    if (_isBlocked || _roomState != _RoomState.ready) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (text.length > _kMaxLength) {
      _toast('メッセージは$_kMaxLength文字以内で入力してください');
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastSentAt) < _kSendInterval) return;
    _lastSentAt = now;

    _controller.clear();

    try {
      // 💡 オフラインでも端末に一時保存され、つながった時に自動で送られる
      await _roomRef.collection('messages').add({
        'text': text,
        'senderId': _myId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      debugPrint('送信エラー: ${e.code} ${e.message}');
      if (!mounted) return;
      // 入力欄が空のままなら、送れなかった文章を戻してあげる
      if (_controller.text.isEmpty) _controller.text = text;
      _toast(
        e.code == 'permission-denied'
            ? 'このユーザーにはメッセージを送れません'
            : '送信に失敗しました。もう一度お試しください',
      );
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  // ==========================================================================
  // 表示用ヘルパー
  // ==========================================================================
  DateTime _dateOf(Map<String, dynamic> data) {
    final t = data['createdAt'];
    // 送信直後（サーバー時刻が決まる前）は今の時刻として扱う
    return t is Timestamp ? t.toDate() : DateTime.now();
  }

  String _formatTime(DateTime date) =>
      '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // 相手が読んだか：新しい方式（lastReadAt）と古い方式（readBy）の両方を見る
  bool _isReadByPeer(Map<String, dynamic> data) {
    final t = data['createdAt'];
    final peerRead = _peerLastReadAt;
    if (t is Timestamp && peerRead != null && t.compareTo(peerRead) <= 0) {
      return true;
    }
    final readBy = data['readBy'];
    return readBy is List && readBy.contains(widget.peerId);
  }

  void _showVerificationRequiredDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '年齢確認が必要です',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'frendyでは安全なコミュニティづくりのため、メッセージの送信や閲覧には年齢確認・本人確認が必須となっております。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openVerification();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: const StadiumBorder(),
            ),
            child: const Text(
              '確認画面へ',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // 画面
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          widget.userName,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        elevation: 0.5,
        centerTitle: true,
      ),
      body: _isCheckingVerification
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(child: _buildMessageArea()),
                    _buildInputArea(),
                  ],
                ),
                // 年齢確認が済んでいないときは、ぼかしと案内を重ねる
                if (!_isVerified)
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.1),
                          child: Center(child: _buildVerificationPromptCard()),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMessageArea() {
    if (!_isVerified) return _buildDummyMessageList();

    switch (_roomState) {
      case _RoomState.loading:
      case _RoomState.starting:
        return const Center(child: CircularProgressIndicator());
      case _RoomState.unavailable:
        return _buildCenterNotice(_unavailableMessage);
      case _RoomState.ready:
        break;
    }

    if (_messagesError && !_messagesLoaded) {
      return _buildCenterNotice('メッセージを読み込めませんでした');
    }
    if (!_messagesLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_messages.isEmpty) {
      return _buildCenterNotice('メッセージを送ってみましょう！');
    }

    final docs = _messages;

    // 💡 メッセージが少ないうちは、画面の上に寄せて表示する。
    //    shrinkWrap（中身の高さに合わせる）は件数が多いと重くなるため、
    //    30件以下のときだけ使う（30件あれば画面は埋まるので、見た目は変わらない）
    final bool isShortList = docs.length <= _kPageSize;

    return Align(
      alignment: Alignment.topCenter,
      child: ListView.builder(
        reverse: true, // 新しいメッセージが一番下
        shrinkWrap: isShortList,
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: docs.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // 一番上：続きを読み込み中の表示
          if (index == docs.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final data = docs[index].data();
          final bool isMe = data['senderId'] == _myId;
          final DateTime date = _dateOf(data);
          final rawText = data['text'];

          // 1つ上（古い方）のメッセージと日付が違えば日付を表示
          final bool showDate = index == docs.length - 1
              ? !_hasMore
              : !_isSameDay(date, _dateOf(docs[index + 1].data()));

          return Column(
            children: [
              if (showDate) _buildDateHeader(date),
              _buildMessageBubble(
                text: rawText is String ? rawText : '',
                isMe: isMe,
                time: date,
                isRead: isMe && _isReadByPeer(data),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCenterNotice(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
        ),
      ),
    );
  }

  // 年齢確認前に、ぼかしの後ろに見せるダミーのメッセージ（実際のメッセージは読まない）
  Widget _buildDummyMessageList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildMessageBubble(
          text: 'はじめまして！よろしくお願いします！',
          isMe: false,
          time: null,
          isRead: false,
        ),
        _buildMessageBubble(
          text: 'よろしくお願いします！😊',
          isMe: true,
          time: null,
          isRead: false,
        ),
        _buildMessageBubble(
          text: '今週末ひまですか？もしよければ...',
          isMe: false,
          time: null,
          isRead: false,
        ),
      ],
    );
  }

  Widget _buildVerificationPromptCard() {
    String message = '安心・安全な友達づくりのため、メッセージの閲覧・送信には年齢確認が必要です。';
    String btnText = '今すぐ年齢確認をする';

    if (_ageStatus == 'pending') {
      message = 'ただいま身分証を確認中です。\n完了までしばらくお待ちください。(通常数分〜24時間以内)';
      btnText = '確認状況を見る';
    } else if (_ageStatus == 'rejected') {
      message = '提出いただいた身分証が非承認となりました。\n内容をご確認の上、再提出をお願いします。';
      btnText = '身分証を再提出する';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.gpp_maybe_rounded,
            size: 50,
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 16),
          const Text(
            '年齢確認が必要です',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _openVerification,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              child: Text(
                btnText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateHeader(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _formatDate(date),
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isMe,
    required DateTime? time,
    required bool isRead,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMe)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (isRead)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text(
                      '既読',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (time != null)
                  Text(
                    _formatTime(time),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
          const SizedBox(width: 4),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMe ? 14 : 2),
                  bottomRight: Radius.circular(isMe ? 2 : 14),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 15, height: 1.3),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (!isMe && time != null)
            Text(
              _formatTime(time),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    final bool canSend =
        _isVerified && !_isBlocked && _roomState == _RoomState.ready;
    final String hint = !_isVerified
        ? '年齢確認を完了してください'
        : _isBlocked
        ? 'このユーザーとはメッセージできません'
        : _roomState == _RoomState.ready
        ? 'メッセージ...'
        : '';

    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        bottom: MediaQuery.paddingOf(context).bottom + 8,
        left: 16,
        right: 8,
        top: 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 5,
              maxLength: _kMaxLength,
              enabled: canSend,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                counterText: '', // 文字数カウンターは表示しない
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: canSend ? Colors.blue : Colors.grey),
            onPressed: canSend ? _sendMessage : null,
          ),
        ],
      ),
    );
  }
}
