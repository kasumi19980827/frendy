import 'package:flutter/material.dart';

class ProfileDetailScreen extends StatelessWidget {
  final String userName; // 渡された名前を受け取る変数

  const ProfileDetailScreen({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$userNameさんのプロフ')),
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(radius: 80, child: Icon(Icons.person, size: 80)),
            const SizedBox(height: 20),
            Text(userName, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('趣味：プログラミング、Flutter\nよろしくお願いします！'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context), // 前の画面に戻る
              child: const Text('戻る'),
            ),
          ],
        ),
      ),
    );
  }
}