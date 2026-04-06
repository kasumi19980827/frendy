import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/models/chat_room.dart'; 
import 'package:matching_app/screens/plaza_screen.dart'; 

class PlazaChatScreen extends StatefulWidget {
  final ChatRoom room; 
  const PlazaChatScreen({super.key, required this.room});

  @override
  State<PlazaChatScreen> createState() => _PlazaChatScreenState();
}

class _PlazaChatScreenState extends State<PlazaChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _messages = ["こんにちは！", "誰か話そう！"];

  void _sendMessage() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        _messages.add(_controller.text);
        _controller.clear();
      });
    }
  }

  Color _getBackgroundImage(String title) {
    if (title.contains('勉強') || title.contains('USCPA')) {
      return Colors.blue[50]!;
    } else if (title.contains('飲み') || title.contains('女子会')) {
      return Colors.orange[50]!;
    } else {
      // green を使わず、汎用的な色か AppColors.bg にしておくと安全です
      return const Color(0xFFE8F5E9); 
    }
  }

  void _showMemberDialog() {
    final List<String> members = [
      "自分 (user_me)", "田中さん (24)", "佐藤さん (21)", 
      "鈴木さん (26)", "高橋さん (23)", "伊藤さん (25)",
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.people, color: AppColors.point),
            const SizedBox(width: 10),
            Text('参加メンバー (${widget.room.currentMemberCount}人)'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: ListView.builder(
            itemCount: widget.room.currentMemberCount,
            itemBuilder: (context, index) => ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(members[index]),
              dense: true,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('閉じる')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = _getBackgroundImage(widget.room.title);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(widget.room.title, style: const TextStyle(fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: GestureDetector(
              onTap: _showMemberDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.point.withOpacity(0.1),
                  border: Border.all(color: AppColors.point, width: 1.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.group, size: 16, color: AppColors.point),
                    const SizedBox(width: 6),
                    Text(
                      'メンバー ${widget.room.currentMemberCount} / 6',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.point),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(15),
                        topRight: Radius.circular(15),
                        bottomRight: Radius.circular(15),
                        bottomLeft: Radius.circular(0),
                      ),
                    ),
                    child: Text(
                      message, 
                      style: const TextStyle(color: AppColors.appbarText, fontSize: 15)
                    ),
                  ),
                );
              },
            ),
          ),
          
          const Divider(height: 1),

          // --- ここからトーク画面と同じデザインの入力欄 ---
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力...',
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none, // 枠線を消してスッキリ
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      maxLines: null,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
                    color: AppColors.point,
                  ),
                ],
              ),
            ),
          ),
          // --- ここまで ---
        ],
      ),
    );
  }
}