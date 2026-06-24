import 'dart:ui'; // 💡 ぼかし効果(ImageFilter)を使用するためにインポート
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/models/chat_room.dart';
import 'package:matching_app/screens/identity_verification_screen.dart'; // 💡 年齢確認画面への遷移に必要

class PlazaChatScreen extends StatefulWidget {
  final ChatRoom room;
  const PlazaChatScreen({super.key, required this.room});

  @override
  State<PlazaChatScreen> createState() => _PlazaChatScreenState();
}

class _PlazaChatScreenState extends State<PlazaChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final String myId = FirebaseAuth.instance.currentUser?.uid ?? "";
  Timestamp? myJoinedAt;

  // 💡 追加：自分の年齢確認ステータス管理用の変数
  String _myAgeVerifiedStatus =
      'unsubmitted'; // 'unsubmitted', 'pending', 'verified', 'rejected'
  bool _isCheckingVerification = true;

  @override
  void initState() {
    super.initState();
    // 💡 まず最初に年齢確認状況を確認する
    _checkMyAgeVerification().then((_) {
      // 年齢確認が済んでいる場合のみ、広場への入室処理（メンバー追加）を行う
      if (_myAgeVerifiedStatus == 'verified') {
        _enterRoom();
      }
    });
  }

  // =========================
  // 💡 自分の年齢確認状況をチェックする
  // =========================
  Future<void> _checkMyAgeVerification() async {
    if (myId.isEmpty) return;
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

  Future<void> _enterRoom() async {
    // 💡 年齢確認が完了していない場合はメンバー追加処理（書き込み）を絶対に避ける
    if (_myAgeVerifiedStatus != 'verified') return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myId)
          .get();
      final userData = userDoc.data();

      List<dynamic> images = userData?['imageUrls'] ?? [];
      String myLatestPhoto = images.isNotEmpty ? images[0].toString() : "";
      String myName = userData?['name'] ?? "ユーザー";

      final memberRef = FirebaseFirestore.instance
          .collection('plaza_rooms')
          .doc(widget.room.id)
          .collection('members')
          .doc(myId);

      await memberRef.set({
        'userId': myId,
        'name': myName,
        'photoUrl': myLatestPhoto,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      final doc = await memberRef.get();
      if (mounted) {
        setState(() {
          myJoinedAt = doc.data()?['joinedAt'] as Timestamp?;
        });
      }
    } catch (e) {
      debugPrint("入室エラー: $e");
    }
  }

  Color _getBackgroundImage(String title) {
    if (title.contains('勉強') || title.contains('USCPA'))
      return Colors.blue[50]!;
    if (title.contains('飲み') || title.contains('女子会'))
      return Colors.orange[50]!;
    return const Color(0xFFE8F5E9);
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = _getBackgroundImage(widget.room.title);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          widget.room.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        // 右上のカウンターも、年齢確認が完了している場合のみ表示・タップ可能にする
        actions: [
          if (_myAgeVerifiedStatus == 'verified') _buildLiveMemberCounter(),
        ],
      ),
      // 💡 年齢確認の初期確認時はロードインジケータを、確認後はレイヤーを重ねるStackを使用
      body: _isCheckingVerification
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 1. チャットコンテンツのメインレイヤー
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        // 💡 年齢確認が完了していない場合は無駄な通信(メッセージ取得)を走らせない
                        stream:
                            _myAgeVerifiedStatus == 'verified' &&
                                myJoinedAt != null
                            ? FirebaseFirestore.instance
                                  .collection('plaza_rooms')
                                  .doc(widget.room.id)
                                  .collection('chats')
                                  .where(
                                    'createdAt',
                                    isGreaterThanOrEqualTo: myJoinedAt,
                                  )
                                  .orderBy('createdAt', descending: true)
                                  .snapshots()
                            : const Stream.empty(),
                        builder: (context, snapshot) {
                          // 未承認の場合はダミーのチャット背景UIを見せて雰囲気を作る
                          if (_myAgeVerifiedStatus != 'verified') {
                            return _buildDummyChatList();
                          }

                          if (!snapshot.hasData) return const SizedBox();
                          final messages = snapshot.data!.docs;

                          return Align(
                            alignment: Alignment.topCenter,
                            child: ListView.builder(
                              reverse: true,
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 20,
                              ),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final data =
                                    messages[index].data()
                                        as Map<String, dynamic>;
                                final bool isMe = data['senderId'] == myId;
                                final String? senderPhoto =
                                    data['senderPhotoUrl'];
                                final String senderName =
                                    data['senderName'] ?? "ユーザー";

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Row(
                                    mainAxisAlignment: isMe
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!isMe) ...[
                                        _buildAvatar(senderPhoto),
                                        const SizedBox(width: 8),
                                      ],
                                      Column(
                                        crossAxisAlignment: isMe
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          if (!isMe)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4,
                                                bottom: 4,
                                              ),
                                              child: Text(
                                                senderName,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ),
                                          Container(
                                            constraints: BoxConstraints(
                                              maxWidth:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.width *
                                                  0.7,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isMe
                                                  ? AppColors.point
                                                  : Colors.white,
                                              borderRadius: BorderRadius.only(
                                                topLeft: const Radius.circular(
                                                  16,
                                                ),
                                                topRight: const Radius.circular(
                                                  16,
                                                ),
                                                bottomRight: isMe
                                                    ? const Radius.circular(0)
                                                    : const Radius.circular(16),
                                                bottomLeft: isMe
                                                    ? const Radius.circular(16)
                                                    : const Radius.circular(0),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.05),
                                                  blurRadius: 5,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              data['text'] ?? '',
                                              style: TextStyle(
                                                color: isMe
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isMe) ...[
                                        const SizedBox(width: 8),
                                        _buildAvatar(senderPhoto),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    _buildInputArea(),
                  ],
                ),

                // 2. 💡 年齢確認が未完了（verified以外）の時の「ぼかし（ブラー）」と「警告カードレイヤー」
                if (_myAgeVerifiedStatus != 'verified')
                  Positioned.fill(
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: 8.0,
                          sigmaY: 8.0,
                        ), // ぼかし強度
                        child: Container(
                          color: Colors.black.withOpacity(0.12), // 薄暗い背景フィルム
                          child: Center(child: _buildVerificationPromptCard()),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // 💡 年齢確認前用の、背景に透けて見せるためのダミーメッセージ（審査＆リッチUI対策）
  Widget _buildDummyChatList() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      physics: const NeverScrollableScrollPhysics(), // スクロール不可
      children: [
        _buildDummyBubble(
          name: "タカシ",
          text: "今度の土曜、新宿周辺でカフェ会しませんか？☕",
          isMe: false,
        ),
        _buildDummyBubble(
          name: "マイ",
          text: "楽しそうですね！参加したいです！🙋‍♀️",
          isMe: false,
        ),
        _buildDummyBubble(name: "ユウタ", text: "あ、自分も空いてますー！", isMe: false),
      ],
    );
  }

  Widget _buildDummyBubble({
    required String name,
    required String text,
    required bool isMe,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[_buildAvatar(null), const SizedBox(width: 8)],
          Column(
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    name,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isMe ? AppColors.point : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  text,
                  style: TextStyle(
                    color: isMe ? Colors.white : Colors.black87,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 💡 画面中央に浮かび上がらせる年齢確認促し用カード
  Widget _buildVerificationPromptCard() {
    String message = '広場チャットで安全にみんなと会話するために、年齢確認・本人確認書類をご提出ください。';
    String btnText = '今すぐ年齢確認をする';

    if (_myAgeVerifiedStatus == 'pending') {
      message = '現在、運営チームで提出いただいた書類を確認中です。確認完了までしばらくお待ちください。(通常数分〜24時間以内)';
      btnText = '確認ステータスを見る';
    } else if (_myAgeVerifiedStatus == 'rejected') {
      message = '提出いただいた証明書が非承認となりました。\n内容をご確認の上、再提出をお願いします。';
      btnText = '証明書を再提出する';
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
          const Icon(Icons.gpp_maybe_rounded, size: 50, color: AppColors.point),
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
                  // 年齢確認画面から戻ってきた時に再度ステータスを読み込み直す
                  setState(() {
                    _isCheckingVerification = true;
                  });
                  _checkMyAgeVerification().then((_) {
                    if (_myAgeVerifiedStatus == 'verified') {
                      _enterRoom(); // 承認されていたらその場で入室処理を完了
                    }
                  });
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.point,
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

  Widget _buildAvatar(String? photoUrl, {double radius = 18}) {
    final bool hasImage =
        photoUrl != null && photoUrl.isNotEmpty && photoUrl.startsWith('http');
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      backgroundImage: hasImage ? NetworkImage(photoUrl) : null,
      child: !hasImage
          ? Icon(Icons.person, size: radius * 1.2, color: Colors.grey[400])
          : null,
    );
  }

  Widget _buildInputArea() {
    final bool isVerified = _myAgeVerifiedStatus == 'verified';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  enabled: isVerified, // 💡 未承認時は入力欄自体も完全にロック
                  decoration: InputDecoration(
                    hintText: isVerified ? 'メッセージを入力...' : '年齢確認を完了してください',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  maxLines: 5,
                  minLines: 1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Icons.send_rounded,
                color: isVerified ? AppColors.point : Colors.grey,
              ),
              onPressed: isVerified
                  ? _sendMessage
                  : null, // 💡 未承認時は送信アクションも無効化
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMessage() async {
    // 💡 念のため送信タップ時のダブルチェック
    if (_myAgeVerifiedStatus != 'verified') return;
    if (_controller.text.trim().isEmpty) return;

    final text = _controller.text;
    _controller.clear();

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .get();
    final userData = userDoc.data();
    final List<dynamic> images = userData?['imageUrls'] ?? [];
    final String myPhoto = images.isNotEmpty ? images[0].toString() : "";
    final String myName = userData?['name'] ?? "ユーザー";

    await FirebaseFirestore.instance
        .collection('plaza_rooms')
        .doc(widget.room.id)
        .collection('chats')
        .add({
          'text': text,
          'senderId': myId,
          'senderName': myName,
          'senderPhotoUrl': myPhoto,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Widget _buildLiveMemberCounter() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('plaza_rooms')
          .doc(widget.room.id)
          .collection('members')
          .snapshots(),
      builder: (context, snapshot) {
        final int count = snapshot.hasData
            ? snapshot.data!.docs.length
            : widget.room.currentMemberCount;

        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: GestureDetector(
            onTap: _showMemberDialog,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.point.withOpacity(0.1),
                  border: Border.all(color: AppColors.point, width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.group, size: 16, color: AppColors.point),
                    const SizedBox(width: 6),
                    Text(
                      '$count / 10',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.point,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMemberDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '参加メンバー',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('plaza_rooms')
                .doc(widget.room.id)
                .collection('members')
                .orderBy('joinedAt', descending: false)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final members = snapshot.data!.docs;
              return ListView.builder(
                itemCount: members.length,
                itemBuilder: (context, index) {
                  final data = members[index].data() as Map<String, dynamic>;
                  return ListTile(
                    leading: _buildAvatar(data['photoUrl'], radius: 16),
                    title: Text(
                      data['name'] ?? '不明',
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
