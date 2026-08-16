import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminMessagesScreen extends StatelessWidget {
  const AdminMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '運営からのメッセージ',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey[200], height: 1.0),
        ),
      ),
      // リストの一番下に余白を作るため、ListViewの外側をSafeAreaやPaddingで制御
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('admin_messages')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(child: Text('エラーが発生しました'));
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            List<DocumentSnapshot> messages = snapshot.data?.docs ?? [];

            // Firestoreが空なら、ダミーデータを表示
            if (messages.isEmpty) {
              return _buildDummyListView(context);
            }

            // 本番用（Firestoreにデータがある場合）
            return ListView.builder(
              padding: EdgeInsets.zero, // 上下の不要なパディングをリセット
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final data = messages[index].data() as Map<String, dynamic>;
                final String title = data['title'] ?? 'お知らせ';
                final String body = data['body'] ?? '';

                final Timestamp? createdAt = data['createdAt'] as Timestamp?;
                String dateStr = '';
                if (createdAt != null) {
                  dateStr = DateFormat(
                    'yyyy/MM/dd HH:mm',
                  ).format(createdAt.toDate());
                }

                return Container(
                  // 一番下の項目も含め、すべての要素の下に確実に線を引く
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                    ),
                  ),
                  child: ListTile(
                    title: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        dateStr,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                      size: 20,
                    ),
                    onTap: () =>
                        _showMessageDetail(context, title, body, dateStr),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // --- ★ダミーメッセージを表示するリストビュー（一番下にも確実に下線を引く仕様） ---
  Widget _buildDummyListView(BuildContext context) {
    final List<Map<String, String>> dummyData = [
      {
        'title': '【重要】安心・安全のためのパトロール強化について',
        'body':
            'いつもfrendyをごご利用いただきありがとうございます。\n\n運営事務局では、ユーザーの皆様に安心してご利用いただくため、24時間体制での通報確認およびプロフィール・メッセージのパトロールを強化しております。\n\n不適切な言動や規約違反を見かけた際は、お相手のプロフィール画面にある「通報」ボタンよりお知らせください。ご協力をお願いいたします。',
        'date': '2026/06/01 12:00',
      },
      {
        'title': 'プレミアム機能に新プランが登場しました！',
        'body':
            '会員の皆様のご要望にお応えし、新しく「ライト」「スタンダード」「プレミアム」の3つの選べるメンバーシッププランが登場しました！\n\nご自身の活動スタイルに合わせて、より効率よく素敵なお友達を探せるようになりました。詳細はマイページの「サブスクリプション管理」よりご確認ください！',
        'date': '2025/05/25 18:30',
      },
      {
        'title': 'frendyへようこそ！初めのステップガイド',
        'body':
            'ご登録ありがとうございます！frendy運営事務局です。\n\nまずは「プロフィール編集」から、あなたの趣味やハマっていること、普段見ているYouTubeチャンネルなどを詳しく書き込んでみましょう！\nプロフィールを充実させると、おすすめタブでのマッチング精度が大幅にアップします。素敵な繋がりが見つかることを応援しております！',
        'date': '2025/05/15 10:00',
      },
    ];

    return ListView.builder(
      padding: EdgeInsets.zero, // ★余白で線が隠れないよう完全にゼロにする
      itemCount: dummyData.length,
      itemBuilder: (context, index) {
        final item = dummyData[index];

        return Container(
          // ★最後の項目（index == 2）であっても、確実に bottom の枠線が描画される
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey[200]!, width: 1),
            ),
          ),
          child: ListTile(
            title: Text(
              item['title']!,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                item['date']!,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: Colors.grey,
              size: 20,
            ),
            onTap: () => _showMessageDetail(
              context,
              item['title']!,
              item['body']!,
              item['date']!,
            ),
          ),
        );
      },
    );
  }

  // 詳細ポップアップ
  void _showMessageDetail(
    BuildContext context,
    String title,
    String body,
    String date,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              date,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '閉じる',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
