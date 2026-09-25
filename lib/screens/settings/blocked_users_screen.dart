import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

// 💡 ユーザー一括取得結果のキャッシュ用コンテナ（friends_screen.dartと同じ考え方）。
//    同じID集合であれば再フェッチせず使い回す
class _CachedUserFetch {
  final String idsSignature;
  final Future<Map<String, Map<String, dynamic>>> future;
  _CachedUserFetch(this.idsSignature, this.future);
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  final String? myId = FirebaseAuth.instance.currentUser?.uid;

  static const Duration _networkTimeout = Duration(seconds: 20);
  static const int _whereInChunkSize = 30; // FirestoreのwhereIn上限

  _CachedUserFetch? _fetchCache;

  // 💡 処理中（解除リクエスト送信中）のユーザーIDを保持し、連打による重複送信を防ぐ
  final Set<String> _processingIds = {};

  // --- Firestoreからユーザー情報をまとめて取得する（N+1問題対策） ---
  Future<Map<String, Map<String, dynamic>>> _fetchUsersByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};

    final Map<String, Map<String, dynamic>> result = {};

    for (int i = 0; i < ids.length; i += _whereInChunkSize) {
      final int end = (i + _whereInChunkSize < ids.length)
          ? i + _whereInChunkSize
          : ids.length;
      final List<String> chunk = ids.sublist(i, end);

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(_networkTimeout);

        for (final doc in snapshot.docs) {
          result[doc.id] = doc.data();
        }
      } catch (e) {
        debugPrint('ブロック中ユーザー一括取得エラー: $e');
        // 💡 一部チャンクの取得に失敗しても、他の結果は表示できるよう処理を継続する
      }
    }
    return result;
  }

  // 💡 ID集合が前回と同じであれば、Futureを再生成せずキャッシュを返す
  Future<Map<String, Map<String, dynamic>>> _getUsersCached(List<String> ids) {
    final String idsSignature = (List<String>.from(ids)..sort()).join(',');
    final existing = _fetchCache;

    if (existing != null && existing.idsSignature == idsSignature) {
      return existing.future;
    }

    final future = _fetchUsersByIds(ids);
    _fetchCache = _CachedUserFetch(idsSignature, future);
    return future;
  }

  // --- 🛠️ ブロック解除のロジック ---
  Future<void> _unblockUser(String peerId, String peerName) async {
    final String? currentMyId = myId;
    if (currentMyId == null || _processingIds.contains(peerId)) return;

    setState(() => _processingIds.add(peerId));

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. 自分の「blocks」から相手のIDを削除
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(currentMyId),
        {
          'blocks': FieldValue.arrayRemove([peerId]),
        },
      );

      // 2. 相手の「blockedBy」から自分のIDを削除
      batch.update(FirebaseFirestore.instance.collection('users').doc(peerId), {
        'blockedBy': FieldValue.arrayRemove([currentMyId]),
      });

      await batch.commit().timeout(_networkTimeout);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$peerName さんのブロックを解除しました'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('ブロック解除エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('解除に失敗しました。もう一度お試しください。')));
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(peerId));
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
    // 💡 未ログイン状態で.doc('')を呼ぶとFirestoreが不正な参照として
    //    例外を投げてしまうため、ここで安全に止める
    if (myId == null || myId!.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'ログイン情報の確認中です。しばらくしてから再度お試しください。',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

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
          final List<String> blockedIds = List<String>.from(
            myData['blocks'] ?? [],
          );

          // ブロックしているユーザーがいない場合
          if (blockedIds.isEmpty) {
            return const Center(
              child: Text(
                'ブロック中のユーザーはいません',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            );
          }

          // 💡 1件ずつ取得するのではなく、まとめて取得してN+1問題を回避する
          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _getUsersCached(blockedIds),
            builder: (context, userMapSnap) {
              if (!userMapSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final Map<String, Map<String, dynamic>> userMap =
                  userMapSnap.data!;

              return ListView.builder(
                itemCount: blockedIds.length,
                itemBuilder: (context, index) {
                  final String peerId = blockedIds[index];
                  final userData = userMap[peerId];

                  // 💡 退会済み等でユーザー情報が取得できない場合も、
                  //    ブロック自体は解除できるよう最低限の表示は残す
                  final String name = userData?['name'] ?? '退会済みユーザー';
                  final String imageUrl =
                      (userData?['imageUrls'] as List?)?.isNotEmpty == true
                      ? userData!['imageUrls'][0]
                      : '';
                  final bool isProcessing = _processingIds.contains(peerId);

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
                      // 💡 画像の読み込みに失敗しても、未処理の例外として
                      //    ログに出続けないよう明示的に捕捉する
                      onBackgroundImageError: imageUrl.isNotEmpty
                          ? (exception, stackTrace) {
                              debugPrint('ブロックユーザー画像読み込みエラー: $exception');
                            }
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
                    trailing: SizedBox(
                      width: 64,
                      height: 32,
                      child: OutlinedButton(
                        onPressed: isProcessing
                            ? null
                            : () => _showUnblockDialog(peerId, name),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          disabledForegroundColor: Colors.grey,
                          side: BorderSide(
                            color: isProcessing
                                ? Colors.grey[300]!
                                : Colors.redAccent,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(60, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                '解除',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
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
