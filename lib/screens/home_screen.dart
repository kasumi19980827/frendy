import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).colorScheme.primary;
    final primaryColor =Theme.of(context).colorScheme.inversePrimary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('frendy', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- お知らせセクション ---
            const Row(
              children: [
                Icon(Icons.campaign, color: Colors.orange),
                SizedBox(width: 8),
                Text('運営からのお知らせ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            _buildNoticeCard('2026/03/10', '新機能「ギフト機能」が追加されました！'),
            _buildNoticeCard('2026/03/05', 'サーバーメンテナンスのお知らせ'),
            
            const SizedBox(height: 30),
            
            // --- 意見送信フォームセクション ---
            const Row(
              children: [
                Icon(Icons.rate_review, color: Colors.blue),
                SizedBox(width: 8),
                Text('運営へのご意見・ご要望', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              elevation: 0,
              color: Colors.grey[100],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const TextField(
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: '「こんな機能が欲しい！」「ここを直してほしい」など、お気軽にお書きください。',
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // ここに送信処理（ダミー）
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ご意見ありがとうございます！')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF8A80),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('送信する'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // お知らせカードの部品化
  Widget _buildNoticeCard(String date, String title) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(date, style: const TextStyle(fontSize: 12)),
        onTap: () { /* 詳細画面への遷移など */ },
      ),
    );
  }
}