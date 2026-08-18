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
import 'package:matching_app/screens/settings/help_support_screen.dart';

class MypageScreen extends StatelessWidget {
  const MypageScreen({super.key});

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
            onPressed: () {
              debugPrint('アイコンがタップされました');
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
      // 1. Firebase Storage の画像データをすべて削除
      try {
        final storageRef = FirebaseStorage.instanceFor(
          bucket: 'gs://frendy-app-project.firebasestorage.app',
        ).ref().child('user_images/$uid');

        final listResult = await storageRef.listAll();
        for (var item in listResult.items) {
          await item.delete();
        }
      } catch (storageError) {
        // 画像がない等のエラーは無視して次に進む
        debugPrint("Storage画像削除スキップ (画像未登録の可能性): $storageError");
      }

      // 2. Firestore のユーザープロフィールドキュメントを削除
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();

      // 3. Firebase Auth のアカウント自体を削除
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

      // 4. 各種サインアウト処理の実行
      await FirebaseAuth.instance.signOut();
      final GoogleSignIn googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }

      // ローディングを閉じる
      if (context.mounted) Navigator.pop(context);

      // 5. ログイン画面へ完全リセット
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
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('エラーが発生したためトップに戻りました: $e')),
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
          '本当に退会しますか？\nアカウントを削除すると、プロフィールを含むすべてのデータが完全に消去され、復旧できません。',
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
