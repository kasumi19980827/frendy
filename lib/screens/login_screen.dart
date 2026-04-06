import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  // ログイン・登録処理
  Future<void> _authAction(bool isLogin) async {
    setState(() => _isLoading = true);
    try {
      if (isLogin) {
        // ログイン
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        // 1. アカウント作成
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // 2. 確認メールを送信（ここを追加！）
        await userCredential.user?.sendEmailVerification();

        // 3. ユーザーに通知
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('確認メールを送信しました。メール内のリンクを確認してください。')),
        );
      }
    } on FirebaseAuthException catch (e) {
      // エラーメッセージを表示
      String message = 'エラーが発生しました';
      if (e.code == 'user-not-found') message = 'ユーザーが見つかりません';
      if (e.code == 'wrong-password') message = 'パスワードが違います';
      if (e.code == 'weak-password') message = 'パスワードが短すぎます';
      if (e.code == 'email-already-in-use') message = 'このメールは既に登録されています';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('frendy')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'メールアドレス',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'パスワード',
                border: OutlineInputBorder(),
              ),
              obscureText: true, // パスワードを伏せ字にする
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _authAction(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.bg,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ログイン'),
                ),
              ),
              TextButton(
                onPressed: () => _authAction(false),
                child: const Text('新規アカウント作成はこちら'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}