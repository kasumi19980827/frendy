import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart'; // scaffoldMessengerKey を使うためにインポート
import 'package:matching_app/screens/email_verification_pending_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _invitationCodeController = TextEditingController();

  bool _isLoading = false;
  bool _isLoginMode = true; // true: ログイン, false: 新規登録

  // --- 📧 メール・パスワードでの認証処理 ---
  Future<void> _authAction() async {
    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        // 新規登録
        final String inputCode = _invitationCodeController.text.trim();
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        final String uid = userCredential.user?.uid ?? '';

        // Firestoreにユーザー作成
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': _emailController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'usedInvitationCode': inputCode.isNotEmpty ? inputCode : null,
          'friends': [],
          'myInvitationCode': uid.substring(0, 6).toUpperCase(),
          'isProfileCompleted': false,
        }, SetOptions(merge: true));

        await userCredential.user?.sendEmailVerification();

        if (mounted) {
          scaffoldMessengerKey.currentState?.showSnackBar(
            const SnackBar(content: Text('確認メールを送信しました。')),
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const EmailVerificationPendingScreen(),
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'エラーが発生しました';
      if (e.code == 'user-not-found') message = 'ユーザーが見つかりません';
      if (e.code == 'wrong-password') message = 'パスワードが違います';
      if (e.code == 'email-already-in-use') message = 'このメールは既に登録されています';

      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 🔴 Googleログイン処理 ---
  Future<void> _onGoogleButtonTapped() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        clientId:
            '982968813521-d13g927ltrui44d8s79fk6ogl7ft5n3o.apps.googleusercontent.com',
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      await _handleFirebaseUserNavigation(userCredential);
    } catch (e) {
      setState(() => _isLoading = false);
      scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Googleログイン失敗: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // --- 🍏 Appleログイン処理 ---
  Future<void> _onAppleButtonTapped() async {
    setState(() => _isLoading = true);
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final AuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      await _handleFirebaseUserNavigation(userCredential);
    } catch (e) {
      setState(() => _isLoading = false);
      scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Appleログイン失敗: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // --- 🚀 共通：ログイン・登録 制限ロジック ---
  Future<void> _handleFirebaseUserNavigation(
    UserCredential userCredential,
  ) async {
    final String uid = userCredential.user?.uid ?? '';
    final String email = userCredential.user?.email ?? '';

    // Firestoreにドキュメントがあるか確認
    final myDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    // 💡 1. 未登録ユーザーの場合（データが存在しない）
    if (!myDoc.exists) {
      if (_isLoginMode) {
        // 【ログインモード時】：未登録なので弾く
        await FirebaseAuth.instance.signOut();

        if (mounted) {
          setState(() => _isLoading = false);
        }

        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'ログインできません。アカウントが登録されていません。',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.fixed,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      } else {
        // 【新規登録モード時】：SNS経由で新規データをFirestoreに作成する
        final String finalCode = _invitationCodeController.text.trim();

        // Firestoreにユーザー作成
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'usedInvitationCode': finalCode.isNotEmpty ? finalCode : null,
          'friends': [],
          'myInvitationCode': uid.substring(0, 6).toUpperCase(),
          'isProfileCompleted': false,
        }, SetOptions(merge: true));

        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('アカウントを作成しました。')),
        );
      }
    }

    // 💡 2. 既存ユーザー、または今新規作成が完了したユーザーの場合：メイン画面へ
    if (mounted) {
      setState(() => _isLoading = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MyHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _isLoginMode ? 'ログイン' : '新規アカウント作成',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
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
                        obscureText: true,
                      ),

                      if (!_isLoginMode) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _invitationCodeController,
                          decoration: const InputDecoration(
                            labelText: '友達の招待コード（お持ちの方）',
                            hintText: '例: AB12CD',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(
                              Icons.card_giftcard,
                              color: Colors.orange,
                            ),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ],

                      const SizedBox(height: 32),

                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _authAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.bg,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _isLoginMode ? 'ログイン' : '新規アカウントを作成する',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            _isLoginMode = !_isLoginMode;
                            _invitationCodeController.clear();
                          }),
                          child: Text(
                            _isLoginMode
                                ? '新規アカウント作成はこちら'
                                : '既にアカウントをお持ちの方はこちら',
                          ),
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16.0),
                          child: Row(
                            children: [
                              Expanded(child: Divider()),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16.0),
                                child: Text(
                                  'または',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(child: Divider()),
                            ],
                          ),
                        ),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _onGoogleButtonTapped,
                            icon: const Icon(
                              Icons.account_circle,
                              color: Colors.redAccent,
                            ),
                            label: Text(
                              _isLoginMode ? 'Googleでログイン' : 'Googleで新規登録',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: _onAppleButtonTapped,
                            icon: const Icon(Icons.apple, color: Colors.black),
                            label: Text(
                              _isLoginMode ? 'Appleでログイン' : 'Appleで新規登録',
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey[300]!),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        // 💡 ✨ 【修正版：目立つ注意書きデザイン】
                        if (!_isLoginMode) ...[
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              // 薄いグレーの背景でカード化
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 💡 オレンジ色のインフォメーションアイコンで視線誘導
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '招待コードをお持ちの方は、SNS登録（Google/Apple）を使わず、画面上部の「メールアドレス・パスワード」に入力してご登録ください。',
                                    style: TextStyle(
                                      color: Colors.grey[800], // より読みやすい濃さに
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500, // 少し太めに
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }
}
