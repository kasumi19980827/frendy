import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/models/chat_room.dart';
import 'package:matching_app/screens/plaza_chat_screen.dart'; 

class PlazaScreen extends StatefulWidget {
  const PlazaScreen({super.key});

  @override
  State<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends State<PlazaScreen> {
  final String myUserId = "user_me";
  
  // ダミーの部屋リスト
  final List<ChatRoom> _rooms = [
    ChatRoom(id: "1", title: "プログラミング勉強会", ownerId: "other1", currentMemberCount: 5),
    ChatRoom(id: "2", title: "今夜飲みに行ける人！", ownerId: "other2", currentMemberCount: 2),
    ChatRoom(id: "3", title: "USCPA受験生集まれ", ownerId: "other3", currentMemberCount: 1),
    ChatRoom(id: "4", title: "ゼルダの伝説 攻略雑談", ownerId: "user_me", currentMemberCount: 6),
  ];

  void _showCreateRoomDialog() {
    if (_rooms.length >= 50) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('部屋が満杯です（最大50個）')));
      return;
    }

    final TextEditingController titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しく部屋を作る'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(hintText: "部屋のタイトルを入力"),
          maxLength: 20,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty) {
                setState(() {
                  _rooms.insert(0, ChatRoom(
                    id: DateTime.now().toString(),
                    title: titleController.text,
                    ownerId: myUserId,
                    currentMemberCount: 1,
                  ));
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.point),
            child: const Text('作成', style: TextStyle(color: Colors.white)),
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
        title: const Text('frendy'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton.icon(
              onPressed: _showCreateRoomDialog,
              icon: const Icon(Icons.add_box, color: AppColors.appbarText),
              label: const Text('部屋を作る', style: TextStyle(color: AppColors.appbarText, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.5)),
            ),
          ),
        ],
      ),
      body: _rooms.isEmpty
          ? const Center(child: Text('現在、部屋はありません。'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, // 二列のグリッド
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.2,
              ),
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                final bool isOwner = room.ownerId == myUserId;

                return InkWell(
                  onTap: () {
                    if (room.currentMemberCount >= 6) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('この部屋は満員です (最大6人)')));
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlazaChatScreen(room: room),
                        ),
                      );
                    }
                  },
                  child: Card(
                    elevation: 2,
                    color: isOwner ? AppColors.point.withOpacity(0.1) : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(Icons.meeting_room, color: AppColors.point, size: 20),
                              if (isOwner)
                                GestureDetector(
                                  onTap: () {
                                    setState(() => _rooms.removeAt(index));
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('部屋を消去しました')));
                                  },
                                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            room.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              const Icon(Icons.group, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text(
                                '${room.currentMemberCount} / 6',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: room.currentMemberCount >= 6 ? Colors.red : AppColors.point,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}