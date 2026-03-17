import 'package:flutter/material.dart';

class TalkScreen extends StatefulWidget {
  final String userName;
  const TalkScreen({super.key, required this.userName});

  @override
  State<TalkScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<TalkScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<String> _messages = []; // メッセージを保存するリスト

  void _sendMessage() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        _messages.add(_controller.text); // リストに追加
        _controller.clear(); // 入力欄を空にする
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.userName)),
      body: Column(
        children: [
          // メッセージ表示エリア
          Expanded(
            child: ListView.builder(
              reverse: true, // 最新のメッセージを下に表示
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                // 配列を逆順に表示
                final message = _messages[_messages.length - 1 - index];
                return ListTile(
                  title: Align(
                    alignment: Alignment.centerRight, // 自分のメッセージを右寄せ
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.inversePrimary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(message),
                    ),
                  ),
                );
              },
            ),
          ),
          // 入力エリア
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.pinkAccent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}