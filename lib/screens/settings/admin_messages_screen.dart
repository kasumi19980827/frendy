import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminMessagesScreen extends StatelessWidget {
  const AdminMessagesScreen({super.key});

  // 💡 お知らせが増え続けても無制限に全件取得しないよう上限を設ける
  static const int _messageFetchLimit = 100;

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
              .limit(_messageFetchLimit)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return const Center(child: Text('エラーが発生しました'));
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final List<DocumentSnapshot> messages = snapshot.data?.docs ?? [];

            // 💡 ダミー（架空）のお知らせを表示するのは、実在しない公式情報を
            //    ユーザーに見せてしまうことになり、Apple審査でも問題視される。
            //    実データが1件もない場合は、正直に「お知らせはありません」と表示する
            if (messages.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mail_outline, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        '現在、お知らせはありません',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }

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
