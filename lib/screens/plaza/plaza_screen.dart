import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/models/chat_room.dart';
import 'package:matching_app/screens/plaza/plaza_chat_screen.dart';

class PlazaScreen extends StatefulWidget {
  const PlazaScreen({super.key});

  @override
  State<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends State<PlazaScreen> {
  final String myUserId = FirebaseAuth.instance.currentUser?.uid ?? "user_me";

  // --- 部屋作成・自動遷移 ---
  void _showCreateRoomDialog() {
    final TextEditingController titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text(
          '新しく部屋を作る',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(hintText: "部屋のタイトルを入力"),
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              if (title.isNotEmpty) {
                // 💡 作成時は確実に1人
                final docRef = await FirebaseFirestore.instance
                    .collection('plaza_rooms')
                    .add({
                      'title': title,
                      'ownerId': myUserId,
                      'currentMemberCount': 1,
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                final newRoom = ChatRoom(
                  id: docRef.id,
                  title: title,
                  ownerId: myUserId,
                  currentMemberCount: 1,
                );

                if (!mounted) return;
                Navigator.pop(context);

                // チャット画面へ遷移
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PlazaChatScreen(room: newRoom),
                  ),
                );

                // 💡 自分が作った部屋から戻ってきた時も、等しく退室処理を実行
                _handleExitRoom(newRoom.id);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            child: const Text('作成', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // --- 🔥 確実な退室・部屋削除ロジック ---
  // トランザクションをシンプルにし、不整合を防ぎます
  Future<void> _handleExitRoom(String roomId) async {
    final docRef = FirebaseFirestore.instance
        .collection('plaza_rooms')
        .doc(roomId);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        int currentCount = snapshot.data()?['currentMemberCount'] ?? 0;
        int newCount = currentCount - 1;

        if (newCount <= 0) {
          // 💡 0人以下になるなら、この瞬間に部屋ごとコレクションから物理削除！
          transaction.delete(docRef);
        } else {
          // まだ人が残っているなら、人数を1減らす
          transaction.update(docRef, {'currentMemberCount': newCount});
        }
      });
    } catch (e) {
      debugPrint("退室処理エラー: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '広場',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: OutlinedButton.icon(
              onPressed: _showCreateRoomDialog,
              icon: const Icon(Icons.add, color: Colors.black, size: 18),
              label: const Text(
                '部屋を作る',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.black, width: 1.2),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('plaza_rooms')
            .where('currentMemberCount', isGreaterThan: 0) // 0人より多い部屋のみ
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('エラーが発生しました'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          // 10人未満の空きがある部屋だけをリスト化
          final docs = snapshot.data!.docs.where((doc) {
            final count = doc['currentMemberCount'] ?? 0;
            return count < 10;
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text('現在、入れる部屋はありません。'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final int currentCount = data['currentMemberCount'] ?? 0;

              final room = ChatRoom(
                id: doc.id,
                title: data['title'] ?? '無題',
                ownerId: data['ownerId'] ?? '',
                currentMemberCount: currentCount,
              );

              final bool isOwner = room.ownerId == myUserId;

              return GestureDetector(
                onTap: () async {
                  // 💡 罠修正：入室処理
                  // 先にFirestore側を+1する
                  await FirebaseFirestore.instance
                      .collection('plaza_rooms')
                      .doc(room.id)
                      .update({'currentMemberCount': FieldValue.increment(1)});

                  // 🔥 チャット画面に渡すroomオブジェクトのカウントも、ちゃんと+1した状態にして同期させる
                  final updatedRoom = ChatRoom(
                    id: room.id,
                    title: room.title,
                    ownerId: room.ownerId,
                    currentMemberCount: currentCount + 1,
                  );

                  if (!mounted) return;

                  // チャット画面へ遷移
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PlazaChatScreen(room: updatedRoom),
                    ),
                  );

                  // 💡 画面から戻ってきた（退室した）ら、人数を減らして0人なら消すロジックへ
                  _handleExitRoom(room.id);
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(
                            Icons.forum_rounded,
                            color: AppColors.point,
                            size: 22,
                          ),
                          if (isOwner)
                            GestureDetector(
                              onTap: () async {
                                // ゴミ箱ボタンを押した場合は即時削除
                                await FirebaseFirestore.instance
                                    .collection('plaza_rooms')
                                    .doc(room.id)
                                    .delete();
                              },
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        room.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            Icons.group_rounded,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$currentCount / 10',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.point,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
