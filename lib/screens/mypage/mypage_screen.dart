import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart'; // 💡 追加：Storage削除に必須
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/screens/auth/identity_verification_screen.dart';
import 'package:matching_app/screens/auth/login_screen.dart';
import 'package:matching_app/screens/profile/profile_setup_screen.dart';
import 'package:matching_app/screens/settings/help_support_screen.dart';
import 'package:matching_app/screens/subscription/subscription_screen.dart';
import 'package:matching_app/screens/settings/app_settings_screen.dart';

class MypageScreen extends StatelessWidget {
  const MypageScreen({super.key});

  // 💡 身分証画像などを格納するStorageバケット。
  //    他画面（profile_setup_screen.dart等）と共通の値。
  //    将来的には constants/app_config.dart 等に一元化することを推奨
  static const String _storageBucket =
      'gs://frendy-app-project.firebasestorage.app';

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'マイページ',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle, color: Colors.black87),
            tooltip: 'プロフィールを編集',
            // 💡 以前は何も起きないボタンだったため、
            //    プロフィール編集画面への導線として機能させる
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileSetupScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('エラーが発生しました'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // データ取得
          final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final List<dynamic> imageUrls = data['imageUrls'] ?? [];
          final String name = data['name'] ?? '名前未設定';
          final String fullId = currentUserId ?? '--------';
          final String shortId = fullId.length >= 8
              ? fullId.substring(0, 8)
              : fullId;

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // --- ヘッダーエリア：写真 ---
                Center(
                  child: ClipOval(
                    child: Container(
                      width: 110,
                      height: 110,
                      color: Colors.grey[200],
                      child: imageUrls.isNotEmpty
                          ? Image.network(
                              imageUrls[0],
                              fit: BoxFit.cover,
                              cacheWidth: 330,
                              cacheHeight: 330,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        value:
                                            loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                            : null,
                                        strokeWidth: 2,
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.error, color: Colors.red),
                            )
                          : Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.grey[400],
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 15),

                // --- 名前表示 ---
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 5),

                // --- ID表示 & コピー機能 ---
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: fullId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('ID: $shortId... をコピーしました'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ID: $shortId',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.copy, size: 14, color: Colors.grey),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                const Divider(thickness: 1, height: 1),

                // --- 設定項目リスト ---
                _buildSettingsItem(
                  icon: Icons.edit,
                  label: 'プロフィール編集',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ProfileSetupScreen(),
                      ),
                    );
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.card_membership,
                  label: 'サブスクリプション管理',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SubscriptionScreen(),
                      ),
                    );
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.verified_user,
                  label: '年齢確認・本人確認',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const IdentityVerificationScreen(),
                      ),
                    );
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.settings,
                  label: 'アプリ設定',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AppSettingsScreen(),
                      ),
                    );
                  },
                ),
                _buildSettingsItem(
                  icon: Icons.help_outline,
                  label: 'ヘルプ・お問い合わせ',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HelpSupportScreen(),
                      ),
                    );
                  },
                ),

                const Divider(),

                // ログアウト
                _buildSettingsItem(
                  icon: Icons.logout,
                  label: 'ログアウト',
                  labelColor: Colors.redAccent,
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      _forceNavigateToRoot(context, 'ログアウトしました');
                    }
                  },
                ),

                // 退会
                _buildSettingsItem(
                  icon: Icons.person_off,
                  label: '退会する',
                  labelColor: Colors.grey,
                  onTap: () => _showDeleteDialog(context),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  // 設定項目の共通ウィジェット
  Widget _buildSettingsItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color labelColor = Colors.black87,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(label, style: TextStyle(color: labelColor, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }

  // --- 🛠️ Storage内の指定フォルダを丸ごと削除するヘルパー（並列化） ---
  Future<void> _deleteStorageFolder(String path) async {
    try {
      final storageRef = FirebaseStorage.instanceFor(
        bucket: _storageBucket,
      ).ref().child(path);

      final listResult = await storageRef.listAll();
      // 💡 逐次削除ではなく並列削除にすることで、退会処理全体の待ち時間を短縮する
      await Future.wait(listResult.items.map((item) => item.delete()));
    } catch (e) {
      // 対象フォルダが存在しない（＝画像未登録）場合などはここに来るため無視して続行
      debugPrint("Storage削除スキップ ($path): $e");
    }
  }

  // --- 🛠️ 他ユーザーのドキュメントに残る自分への参照をクリーンアップ ---
  //    退会後も「友達一覧」「いいねした一覧」等に、存在しないはずのUIDが
  //    残り続けてしまうのを防ぐためのベストエフォート処理。
  //    一部が失敗しても、退会処理自体は継続する
  Future<void> _cleanupUserReferences(String uid) async {
    final firestore = FirebaseFirestore.instance;

    // 💡 自分のUIDが配列として含まれている可能性のあるフィールド一覧
    const List<String> arrayFields = [
      'friends',
      'likes',
      'likedBy',
      'blocks',
      'blockedBy',
      'footprints',
    ];

    for (final field in arrayFields) {
      try {
        final snapshot = await firestore
            .collection('users')
            .where(field, arrayContains: uid)
            .get();

        // 💡 Firestoreのバッチ上限（500件）を考慮し、100件ごとに分けて処理する
        const int chunkSize = 100;
        for (int i = 0; i < snapshot.docs.length; i += chunkSize) {
          final chunk = snapshot.docs.sublist(
            i,
            (i + chunkSize > snapshot.docs.length)
                ? snapshot.docs.length
                : i + chunkSize,
          );
          final batch = firestore.batch();
          for (final doc in chunk) {
            batch.update(doc.reference, {
              field: FieldValue.arrayRemove([uid]),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('関連データ削除エラー（$field）: $e');
        // 💡 1つのフィールドで失敗しても他のクリーンアップは続行する
      }
    }

    // 💡 自分が送信・受信した友達申請も削除する
    try {
      final fromRequests = await firestore
          .collection('friend_requests')
          .where('fromId', isEqualTo: uid)
          .get();
      final toRequests = await firestore
          .collection('friend_requests')
          .where('toId', isEqualTo: uid)
          .get();

      final batch = firestore.batch();
      for (final doc in [...fromRequests.docs, ...toRequests.docs]) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('友達申請の削除エラー: $e');
    }
  }

  // --- 🛠️ 統合版：退会・プロフィール＆画像完全削除処理 ---
  Future<void> _deleteAccount(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final String uid = user.uid;

    // 💡 連打・誤操作防止用のローディングインジケーターを表示
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Colors.redAccent),
      ),
    );

    try {
      // 1. Firebase Storage のデータを削除
      //    💡 プロフィール画像だけでなく、身分証明書の画像（user_verifications）も
      //       必ず削除する。ここを削除しないと、退会後も本人確認書類が
      //       Storageに残り続けてしまい、重大なプライバシー問題になる
      await Future.wait([
        _deleteStorageFolder('user_images/$uid'),
        _deleteStorageFolder('user_verifications/$uid'),
      ]);

      // 2. 他ユーザーのドキュメントに残る自分への参照をクリーンアップ
      //    （友達一覧・いいね・ブロック・足跡・友達申請から自分の痕跡を消す）
      await _cleanupUserReferences(uid);

      // 3. Firestore のユーザープロフィールドキュメントを削除
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 4. Firebase Auth のアカウント自体を削除
      try {
        await user.delete();
      } on FirebaseAuthException catch (authError) {
        // セキュリティ制限（requires-recent-login）への対処
        if (authError.code == 'requires-recent-login') {
          if (context.mounted) Navigator.pop(context); // ローディングを閉じる

          await FirebaseAuth.instance.signOut();
          await GoogleSignIn().signOut();

          if (context.mounted) {
            Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
            scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
            scaffoldMessengerKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('安全のため、一度再ログインしてから再度退会を行ってください。'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
        rethrow;
      }

      // 5. 各種サインアウト処理の実行
      await FirebaseAuth.instance.signOut();
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }

      // ローディングを閉じる
      if (context.mounted) Navigator.pop(context);

      // 6. ログイン画面へ完全リセット
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('退会およびプロフィールの削除が完了しました')),
        );
      }
    } catch (e) {
      debugPrint('退会処理エラー: $e');
      if (context.mounted) Navigator.pop(context); // ローディングを閉じる

      // 予期せぬエラー時のセーフティネット
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        // 💡 内部エラーの詳細($e)はユーザーへ見せず、ログにのみ残す
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('エラーが発生したためトップに戻りました。もう一度お試しください。')),
        );
      }
    }
  }

  // --- 🛠️ 強制画面遷移ロジック（ログアウトなど） ---
  void _forceNavigateToRoot(BuildContext context, String message) {
    if (!context.mounted) return;

    GoogleSignIn().signOut();

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );

    scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --- 退会確認ダイアログの表示 ---
  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '退会の確認',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          '本当に退会しますか？\nプロフィール・提出済みの本人確認書類を含むすべてのデータが完全に消去され、復旧できません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // ダイアログを閉じる
              _deleteAccount(context); // 退会処理（大元のcontextを渡す）
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text(
              '退会する',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
