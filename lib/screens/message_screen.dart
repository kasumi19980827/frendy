import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/screens/mypage_screen.dart';
import 'package:matching_app/screens/talk_screen.dart';

class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(myId)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final myData =
              userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final List<dynamic> myFriends = myData['friends'] ?? [];

          // 💡 ユーザー自身の現在のブロック状態を取得
          final List<dynamic> myBlocks = myData['blocks'] ?? [];

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('chat_rooms')
                .where('users', arrayContains: myId)
                .where('lastMessageTime', isNull: false) // 💡 タイムスタンプがあるものだけ
                .orderBy('lastMessageTime', descending: true)
                .snapshots(),
            builder: (context, chatSnapshot) {
              if (chatSnapshot.hasError) {
                return Center(child: Text("エラー: ${chatSnapshot.error}"));
              }
              if (!chatSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final allDocs = chatSnapshot.data!.docs;
              final docs = allDocs.where((doc) {
                final chatData = doc.data() as Map<String, dynamic>;
                final List<dynamic> users = chatData['users'] ?? [];

                final String peerId = users.firstWhere(
                  (id) => id != myId,
                  orElse: () => '',
                );

                // 💡 【超重要】自分が現在進行形でブロックしている相手、
                // またはルーム自体で非表示フラグ（blockedBy）が有効な場合は除外
                final List<dynamic> roomBlockedBy = chatData['blockedBy'] ?? [];
                if (myBlocks.contains(peerId) || roomBlockedBy.contains(myId)) {
                  return false;
                }
                return true;
              }).toList();

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    "まだトークがありません🌿",
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final chatData = docs[index].data() as Map<String, dynamic>;
                  final List<dynamic> users = chatData['users'];
                  final String peerId = users.firstWhere(
                    (id) => id != myId,
                    orElse: () => '',
                  );
                  final String lastMessage = chatData['lastMessage'] ?? '';
                  final Timestamp? lastTime =
                      chatData['lastMessageTime'] as Timestamp?;
                  final int unreadCount = chatData['unreadCount']?[myId] ?? 0;
                  final int messageCount = chatData['messageCount'] ?? 0;
                  final bool isFriend = myFriends.contains(peerId);

                  // 💡 【修正版】MessageScreenのListView.builder内のFutureBuilder周辺
                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(peerId)
                        .get(),
                    builder: (context, peerSnapshot) {
                      if (!peerSnapshot.hasData) return const SizedBox();
                      final data =
                          peerSnapshot.data!.data() as Map<String, dynamic>? ??
                          {};

                      if (data.isEmpty) return const SizedBox();

                      // 相手側のブロックリストに自分が含まれているかチェック
                      final List<dynamic> peerBlocks = data['blocks'] ?? [];
                      if (peerBlocks.contains(myId)) {
                        return const SizedBox();
                      }

                      final String name = data['name'] ?? 'ユーザー';
                      final String image =
                          (data['imageUrls'] as List?)?.isNotEmpty == true
                          ? data['imageUrls'][0]
                          : '';

                      // 🔥 【ここを追加】自分と相手のメッセージ送信数をリアルタイム/またはFutureでカウントする
                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('chat_rooms')
                            .doc(docs[index].id)
                            .collection('messages')
                            .snapshots(),
                        builder: (context, msgSnapshot) {
                          int myMsgCount = 0;
                          int peerMsgCount = 0;

                          if (msgSnapshot.hasData) {
                            for (var doc in msgSnapshot.data!.docs) {
                              final msgData =
                                  doc.data() as Map<String, dynamic>;
                              final senderId = msgData['senderId'] ?? '';
                              if (senderId == myId) {
                                myMsgCount++;
                              } else if (senderId == peerId) {
                                peerMsgCount++;
                              }
                            }
                          }

                          // 🔥 自分>=4 かつ 相手>=4 の時にボタンを出現させるフラグ
                          final bool canSendRequest =
                              myMsgCount >= 4 && peerMsgCount >= 4;

                          return Column(
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.only(
                                  left: 16,
                                  right: 8,
                                ),
                                leading: CircleAvatar(
                                  radius: 28,
                                  backgroundColor: Colors.grey[200],
                                  backgroundImage: image.isNotEmpty
                                      ? NetworkImage(image)
                                      : null,
                                  child: image.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.grey,
                                        )
                                      : null,
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  lastMessage.isEmpty
                                      ? 'メッセージはありません'
                                      : lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 🔥 条件を変更：お互いが4通以上送信しており、かつ友達ではない場合
                                    if (!isFriend && canSendRequest)
                                      _buildRequestStatusWrapper(
                                        myId,
                                        peerId,
                                        myData['name'] ?? '',
                                        name,
                                      ),
                                    const SizedBox(width: 6),
                                    _buildTimeBadge(lastTime, unreadCount),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.grey,
                                      ),
                                      onPressed: () => _showActionSheet(
                                        context,
                                        peerId,
                                        name,
                                        docs[index].id,
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TalkScreen(
                                        userName: name,
                                        peerId: peerId,
                                        peerImageUrl: image,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // 申請状況を監視してボタンか「申請中」を出し分けるラッパー
  Widget _buildRequestStatusWrapper(
    String myId,
    String peerId,
    String myName,
    String peerName,
  ) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('fromId', isEqualTo: myId)
          .where('toId', isEqualTo: peerId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();

        if (snapshot.data!.docs.isNotEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '申請中',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          );
        }

        return _buildFriendButton(context, myId, peerId, myName, peerName);
      },
    );
  }

  Widget _buildFriendButton(
    BuildContext context,
    String myId,
    String peerId,
    String myName,
    String peerName,
  ) {
    final bool isMyNameInvalid = myName.trim().isEmpty || myName == '名前未設定';

    return ElevatedButton(
      onPressed: () {
        if (isMyNameInvalid) {
          _showProfileSetupDialog(context);
        } else {
          _sendFriendRequest(context, myId, peerId, peerName);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isMyNameInvalid ? Colors.grey[400] : AppColors.bg,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(50, 30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: const Text(
        '友達申請',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _showProfileSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('プロフィールを確認'),
        content: const Text('友達申請をするには、先にプロフィールで名前を設定してください！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.point),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const MypageScreen()),
                (route) => false,
              );
            },
            child: const Text('設定する', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBadge(Timestamp? t, int unreadCount) {
    if (t == null) return const SizedBox();
    final date = t.toDate();
    final timeStr = "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        if (unreadCount > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$unreadCount',
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

  void _showActionSheet(
    BuildContext context,
    String peerId,
    String name,
    String roomId,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
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
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _tile(
              icon: Icons.report_problem_outlined,
              title: '通報する',
              subtitle: '不適切な内容を報告',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(context, peerId, name);
              },
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.block,
              title: 'ブロックする',
              subtitle: 'このユーザーを非表示',
              color: Colors.black87,
              onTap: () {
                Navigator.pop(context);
                _blockUser(context, peerId, name);
              },
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.visibility_off_outlined,
              title: 'トークを非表示',
              subtitle: '一覧から非表示にします',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _deleteChatRoom(context, roomId);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
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
                  color: color.withOpacity(0.12),
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

  // --- 機能ロジック群 ---

  Future<void> _sendFriendRequest(
    BuildContext context,
    String myId,
    String peerId,
    String name,
  ) async {
    await FirebaseFirestore.instance.collection('friend_requests').add({
      'fromId': myId,
      'toId': peerId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$nameさんに友達申請を送りました')));
  }

  void _showReportDialog(BuildContext context, String peerId, String name) {
    final TextEditingController reportController = TextEditingController();
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '$name さんを通報',
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
              controller: reportController,
              maxLines: 4,
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
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
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
                  onPressed: () async {
                    final String reason = reportController.text.trim();
                    if (reason.isEmpty) return;

                    await FirebaseFirestore.instance.collection('reports').add({
                      'reporterId': currentUserId,
                      'reportedId': peerId,
                      'reason': reason,
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('報告ありがとうございます。運営で確認いたします。'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '通報する',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 💡 修正箇所: ブロック実行時の処理
  void _blockUser(BuildContext context, String peerId, String name) async {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '$name さんをブロックしますか？',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('お互いにメッセージの送受信ができなくなり、トーク一覧や友達リストからも削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ブロック',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final batch = FirebaseFirestore.instance.batch();

        final myRef = FirebaseFirestore.instance.collection('users').doc(myId);
        batch.update(myRef, {
          'blocks': FieldValue.arrayUnion([peerId]),
          'friends': FieldValue.arrayRemove([peerId]),
        });

        final peerRef = FirebaseFirestore.instance
            .collection('users')
            .doc(peerId);
        batch.update(peerRef, {
          'blockedBy': FieldValue.arrayUnion([myId]),
          'friends': FieldValue.arrayRemove([myId]),
        });

        final String chatRoomId = ([myId, peerId]..sort()).join("_");
        final roomRef = FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(chatRoomId);

        // 💡 チャットルームに「自分が非表示にしたマーク」を刻みます。
        // これによりブロックした瞬間、リストからパッと消えます。
        batch.update(roomRef, {
          'blockedBy': FieldValue.arrayUnion([myId]),
        });

        await batch.commit();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ブロックして友達解除しました'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint("ブロックエラー: $e");
      }
    }
  }

  Future<void> _deleteChatRoom(BuildContext context, String roomId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'トークを非表示にしますか？',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('一覧から非表示になります。\n新しいメッセージが届くと再度表示されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '非表示',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('chat_rooms')
            .doc(roomId)
            .update({
              'lastMessage': '',
              'lastMessageTime': null,
              'messageCount': 0,
            });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('トークを非表示にしました'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        debugPrint("非表示処理エラー: $e");
      }
    }
  }
}
