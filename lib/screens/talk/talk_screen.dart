import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui'; // 💡 ぼかし効果(ImageFilter)を使用するためにインポート
import 'package:matching_app/screens/auth/identity_verification_screen.dart'; // 💡 年齢確認画面への遷移に必要

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

class _TalkScreenState extends State<TalkScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final String myId = FirebaseAuth.instance.currentUser!.uid;
  late String chatRoomId;
  bool _isUpdatingRead = false;

  // 💡 追加：自分の年齢確認ステータス管理用の変数
  String _myAgeVerifiedStatus =
      'unsubmitted'; // 'unsubmitted', 'pending', 'verified', 'rejected'
  bool _isCheckingVerification = true;

  @override
  void initState() {
    super.initState();
    final ids = [myId, widget.peerId]..sort();
    chatRoomId = ids.join("_");

    // 💡 年齢確認ステータスの確認を最初に行う
    _checkMyAgeVerification().then((_) {
      if (_myAgeVerifiedStatus == 'verified') {
        _resetUnreadCount();
      }
    });
  }

  // =========================
  // 💡 自分の年齢確認状況をチェックする
  // =========================
  Future<void> _checkMyAgeVerification() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _myAgeVerifiedStatus = data['ageVerified'] ?? 'unsubmitted';
            _isCheckingVerification = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isCheckingVerification = false;
          });
        }
      }
    } catch (e) {
      debugPrint("年齢確認チェックエラー: $e");
      if (mounted) {
        setState(() {
          _isCheckingVerification = false;
        });
      }
    }
  }

  // =========================
  // 未読リセット & 既読更新
  // =========================
  Future<void> _resetUnreadCount() async {
    // 💡 承認済みでない場合は未読リセット等のFirebase処理をスキップ
    if (_myAgeVerifiedStatus != 'verified') return;

    await FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(chatRoomId)
        .set({
          'users': [myId, widget.peerId],
          'unreadCount': {myId: 0},
          'blockedBy': FieldValue.arrayRemove([myId]),
        }, SetOptions(merge: true));

    await _markMessagesAsRead();
  }

  // =========================
  // メッセージ送信（復活ロジック込み）
  // =========================
  Future<void> _sendMessage() async {
    // 💡 念のため送信時にも再度年齢確認ステータスを確認・ブロック
    if (_myAgeVerifiedStatus != 'verified') {
      _showVerificationRequiredDialog();
      return;
    }

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final roomRef = FirebaseFirestore.instance
        .collection('chat_rooms')
        .doc(chatRoomId);
    final messageRef = roomRef.collection('messages').doc();
    final batch = FirebaseFirestore.instance.batch();

    // 1. メッセージの保存
    batch.set(messageRef, {
      'text': text,
      'senderId': myId,
      'createdAt': FieldValue.serverTimestamp(),
      'readBy': <String>[myId],
    });

    // 2. チャットルームの更新
    batch.set(roomRef, {
      'users': [myId, widget.peerId],
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'messageCount': FieldValue.increment(1),
      'unreadCount': {widget.peerId: FieldValue.increment(1)},
      'blockedBy': FieldValue.arrayRemove([myId]),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // =========================
  // 既読処理の最適化
  // =========================
  Future<void> _markMessagesAsRead() async {
    // 💡 承認済みでない場合は既読処理を実行しない
    if (_myAgeVerifiedStatus != 'verified') return;
    if (_isUpdatingRead) return;
    _isUpdatingRead = true;

    try {
      final messagesRef = FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .collection('messages');

      final snapshot = await messagesRef
          .where('senderId', isEqualTo: widget.peerId)
          .get();

      if (snapshot.docs.isEmpty) {
        _isUpdatingRead = false;
        return;
      }

      final batch = FirebaseFirestore.instance.batch();
      bool needUpdate = false;

      for (final doc in snapshot.docs) {
        final List<dynamic> readBy = List<dynamic>.from(
          doc.data()['readBy'] ?? [],
        );
        if (!readBy.contains(myId)) {
          batch.update(doc.reference, {
            'readBy': FieldValue.arrayUnion([myId]),
          });
          needUpdate = true;
        }
      }

      if (needUpdate) {
        await batch.commit();
      }

      await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .set({
            'unreadCount': {myId: 0},
            'blockedBy': FieldValue.arrayRemove([myId]),
          }, SetOptions(merge: true));

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("既読エラー: $e");
    } finally {
      _isUpdatingRead = false;
    }
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return "";
    final date = timestamp.toDate();
    return "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return "";
    final date = timestamp.toDate();
    return "${date.year}年${date.month}月${date.day}日";
  }

  // 💡 年齢確認を促す警告用ダイアログ表示メソッド
  void _showVerificationRequiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // ダイアログを閉じる
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const IdentityVerificationScreen(),
                ),
              ).then((_) {
                // 年齢確認画面から戻ってきた時に再度ステータスを読み込み直す
                setState(() {
                  _isCheckingVerification = true;
                });
                _checkMyAgeVerification().then((_) => _resetUnreadCount());
              });
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
        ),
        elevation: 0.5,
        centerTitle: true,
      ),
      // 💡 ステータス確認のロード中はインジケータを、確認後はレイヤーを重ねるStackを使用
      body: _isCheckingVerification
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 1. チャットコンテンツのメイン画面
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        // 💡 年齢確認が済んでいない場合はメッセージのStream監視を止めて通信負荷を減らす
                        stream: _myAgeVerifiedStatus == 'verified'
                            ? FirebaseFirestore.instance
                                  .collection('chat_rooms')
                                  .doc(chatRoomId)
                                  .collection('messages')
                                  .orderBy('createdAt', descending: true)
                                  .snapshots()
                            : const Stream.empty(),
                        builder: (context, snapshot) {
                          // 未承認の場合はダミー用のUIか空のメッセージボックスを表示
                          if (_myAgeVerifiedStatus != 'verified') {
                            return _buildDummyMessageList();
                          }

                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          _markMessagesAsRead();

                          final docs = snapshot.data!.docs;
                          return Align(
                            alignment: Alignment.topCenter,
                            child: ListView.builder(
                              reverse: true,
                              shrinkWrap: true,
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              itemCount: docs.length,
                              itemBuilder: (context, index) {
                                final data =
                                    docs[index].data() as Map<String, dynamic>;
                                final bool isMe = data['senderId'] == myId;
                                final Timestamp? time = data['createdAt'];
                                final List<dynamic> readBy = List<dynamic>.from(
                                  data['readBy'] ?? [],
                                );
                                final bool isRead =
                                    isMe && readBy.contains(widget.peerId);

                                bool showDate = false;

                                if (index == docs.length - 1) {
                                  showDate = true;
                                } else {
                                  final nextData =
                                      docs[index + 1].data()
                                          as Map<String, dynamic>;
                                  final Timestamp? nextTime =
                                      nextData['createdAt'];
                                  if (time != null && nextTime != null) {
                                    final d1 = time.toDate();
                                    final d2 = nextTime.toDate();
                                    if (d1.year != d2.year ||
                                        d1.month != d2.month ||
                                        d1.day != d2.day) {
                                      showDate = true;
                                    }
                                  }
                                }

                                return Column(
                                  children: [
                                    if (showDate) _buildDateHeader(time),
                                    _buildMessageBubble(
                                      text: data['text'] ?? "",
                                      isMe: isMe,
                                      time: time,
                                      isRead: isRead,
                                    ),
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    _buildInputArea(),
                  ],
                ),

                // 2. 💡 年齢確認が未完了（verified以外）の時の「ぼかし（ブラー）」と「警告オーバーレイ」
                if (_myAgeVerifiedStatus != 'verified')
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 8.0,
                          sigmaY: 8.0,
                        ), // ぼかし強度
                        child: Container(
                          color: Colors.black.withOpacity(0.1), // 薄暗い背景
                          child: Center(child: _buildVerificationPromptCard()),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // 💡 年齢確認前用の、背景に透けて見せるためのダミーメッセージ（審査・見た目用）
  Widget _buildDummyMessageList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(), // スクロール不可
      children: [
        _buildMessageBubble(
          text: "はじめまして！よろしくお願いします！",
          isMe: false,
          time: null,
          isRead: false,
        ),
        _buildMessageBubble(
          text: "よろしくお願いします！😊",
          isMe: true,
          time: null,
          isRead: false,
        ),
        _buildMessageBubble(
          text: "今週末ひまですか？もしよければ...",
          isMe: false,
          time: null,
          isRead: false,
        ),
      ],
    );
  }

  // 💡 画面中央に配置する年齢確認誘導カード
  Widget _buildVerificationPromptCard() {
    String message = '安心・安全な友達づくりのため、メッセージの閲覧・送信には年齢確認が必要です。';
    String btnText = '今すぐ年齢確認をする';

    if (_myAgeVerifiedStatus == 'pending') {
      message = 'ただいま身分証を確認中です。\n完了までしばらくお待ちください。(通常数分〜24時間以内)';
      btnText = '確認状況を見る';
    } else if (_myAgeVerifiedStatus == 'rejected') {
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
            color: Colors.black.withOpacity(0.15),
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
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const IdentityVerificationScreen(),
                  ),
                ).then((_) {
                  setState(() {
                    _isCheckingVerification = true;
                  });
                  _checkMyAgeVerification().then((_) => _resetUnreadCount());
                });
              },
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

  Widget _buildDateHeader(Timestamp? time) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _formatDate(time),
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    );
  }

  Widget _buildMessageBubble({
    required String text,
    required bool isMe,
    required Timestamp? time,
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
          if (isMe) ...[
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
          ],
          const SizedBox(width: 4),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMe ? Colors.white : Colors.white.withOpacity(0.85),
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
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
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
              enabled: _myAgeVerifiedStatus == 'verified', // 💡 未承認時は入力自体もロックする
              decoration: InputDecoration(
                hintText: _myAgeVerifiedStatus == 'verified'
                    ? 'メッセージ...'
                    : '年齢確認を完了してください',
                border: InputBorder.none,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.send,
              color: _myAgeVerifiedStatus == 'verified'
                  ? Colors.blue
                  : Colors.grey,
            ),
            onPressed: _myAgeVerifiedStatus == 'verified' ? _sendMessage : null,
          ),
        ],
      ),
    );
  }
}
