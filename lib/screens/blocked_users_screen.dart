import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

  // --- 🛠️ ブロック解除のロジック ---
  Future<void> _unblockUser(String peerId, String peerName) async {
    final batch = FirebaseFirestore.instance.batch();

    // 1. 自分の「blocks」から相手のIDを削除
    batch.update(FirebaseFirestore.instance.collection('users').doc(myId), {
      'blocks': FieldValue.arrayRemove([peerId]),
    });

    // 2. 相手の「blockedBy」から自分のIDを削除
    batch.update(FirebaseFirestore.instance.collection('users').doc(peerId), {
      'blockedBy': FieldValue.arrayRemove([myId]),
    });

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$peerName さんのブロックを解除しました'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Unblock Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('解除に失敗しました。もう一度お試しください。')));
      }
    }
  }

  // --- 解除の確認ダイアログ ---
  void _showUnblockDialog(String peerId, String peerName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ブロック解除'),
        content: Text(
          '$peerName さんのブロックを解除しますか？\n解除するとお互いのアプリに再度表示されるようになります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _unblockUser(peerId, peerName);
            },
            child: const Text(
              '解除する',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
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
        title: const Text(
          'ブロック中のユーザー',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      // 💡 自分のデータをリアルタイムに監視して、ブロックリストが空になったら自動で画面を更新します
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(myId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('エラーが発生しました'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final myData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final List<dynamic> blockedIds = myData['blocks'] ?? [];

          // ブロックしているユーザーがいない場合
          if (blockedIds.isEmpty) {
            return const Center(
              child: Text(
                'ブロック中のユーザーはいません',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            );
          }

          // ブロックしているユーザーをリスト表示
          return ListView.builder(
            itemCount: blockedIds.length,
            itemBuilder: (context, index) {
              final String peerId = blockedIds[index];

              // 💡 ブロック相手の「名前」と「写真」を1件ずつ取得する
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(peerId)
                    .get(),
                builder: (context, userSnap) {
                  if (userSnap.hasError) return const SizedBox();
                  if (!userSnap.hasData)
                    return const SizedBox(); // 読み込み中は何も出さない（チラつき防止）

                  final userData =
                      userSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final String name = userData['name'] ?? '退会済みユーザー';
                  final String imageUrl =
                      (userData['imageUrls'] as List?)?.isNotEmpty == true
                      ? userData['imageUrls'][0]
                      : '';

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: imageUrl.isNotEmpty
                          ? NetworkImage(imageUrl)
                          : null,
                      child: imageUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.grey)
                          : null,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    // 右側に小さく「解除」ボタンを配置
                    trailing: OutlinedButton(
                      onPressed: () => _showUnblockDialog(peerId, name),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(60, 32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        '解除',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
