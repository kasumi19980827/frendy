// トークしてる人の一覧の画面

import 'package:flutter/material.dart';
import 'package:matching_app/screens/talk_screen.dart';

class MessageScreen extends StatelessWidget {
  const MessageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('frendy'),
      ),
      body: ListView.separated(
        itemCount: 10, // ダミーで10件表示
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          return ListTile(
            leading: const CircleAvatar(
              radius: 28,
              backgroundImage: NetworkImage('https://via.placeholder.com/150'),
            ),
            title: Text(
              'ユーザー ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              '最近のメッセージがここに表示されます。お元気ですか？',
              maxLines: 1,
              overflow: TextOverflow.ellipsis, // 長いメッセージを「...」にする
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('12:34', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                // 未読がある場合のバッジ（例）
                if (index % 3 == 0)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle),
                    child: const Text('1', style: TextStyle(color: Colors.white, fontSize: 10)),
                  ),
              ],
            ),
            onTap: () {
              // Navigator を使って画面遷移
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TalkScreen(
                    userName: 'ユーザー ${index + 1}', // タップした相手の名前を渡す
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