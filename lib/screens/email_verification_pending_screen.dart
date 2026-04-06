import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';

class EmailVerificationPendingScreen extends StatefulWidget {
  const EmailVerificationPendingScreen({super.key});

  @override
  State<EmailVerificationPendingScreen> createState() => _EmailVerificationPendingScreenState();
}

class _EmailVerificationPendingScreenState extends State<EmailVerificationPendingScreen> {
  bool _isSending = false;

  // 最新のユーザー情報を取得して、認証済みか確認する
  Future<void> _checkEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    await user?.reload(); // Firebaseサーバーの状態をアプリに同期

    final updatedUser = FirebaseAuth.instance.currentUser;

    if (updatedUser != null && updatedUser.emailVerified) {
    Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const MyHomePage()),
        (route) => false, // これまでの画面履歴（ログイン画面など）をすべて消去する
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('まだ認証が完了していないようです。')),
      );
    }
  }

  // 確認メールを再送する
  Future<void> _resendEmail() async {
    setState(() => _isSending = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('確認メールを再送しました。')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('メール認証'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 100, color: AppColors.point),
            const SizedBox(height: 24),
            const Text(
              '確認メールを送信しました',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              '届いたメール内のリンクをタップして、\n認証を完了させてください。\n※届かない場合は迷惑メールフォルダも\nご確認ください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 32),
            
            // 認証チェックボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _checkEmailVerified,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.point,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('認証を完了しました'),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 再送ボタン
            TextButton(
              onPressed: _isSending ? null : _resendEmail,
              child: Text(_isSending ? '送信中...' : 'メールを再送する'),
            ),
          ],
        ),
      ),
    );
  }
}