import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart'; // scaffoldMessengerKey を使うためにインポート
import 'package:matching_app/screens/auth/email_verification_pending_screen.dart';

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

  // 💡 GoogleSignInはボタンを押すたびに生成するのではなく、使い回す
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '982968813521-d13g927ltrui44d8s79fk6ogl7ft5n3o.apps.googleusercontent.com',
  );

  // 💡 ブルートフォース対策：ログイン失敗が続いた場合のクールダウン管理
  int _failedLoginAttempts = 0;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  static const int _attemptsPerLockout = 5;
  static const int _baseCooldownSeconds = 30;
  static const int _maxCooldownSeconds = 300; // 上限5分

  // 💡 通信が固まってしまうのを防ぐタイムアウト
  static const Duration _authTimeout = Duration(seconds: 20);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _invitationCodeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  // --- 入力バリデーション ---
  bool _validateEmailPassword() {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('メールアドレスとパスワードを入力してください。');
      return false;
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      _showMessage('メールアドレスの形式が正しくありません。');
      return false;
    }

    if (!_isLoginMode && password.length < 6) {
      _showMessage('パスワードは6文字以上で入力してください。');
      return false;
    }

    return true;
  }

  // 💡 招待コードは英数字のみ・上限10文字に正規化してからFirestoreへ保存する
  String? _sanitizedInvitationCode() {
    final raw = _invitationCodeController.text.trim();
    if (raw.isEmpty) return null;
    final sanitized = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (sanitized.isEmpty) return null;
    return sanitized.length > 10 ? sanitized.substring(0, 10) : sanitized;
  }

  // --- 📧 メール・パスワードでの認証処理 ---
  Future<void> _authAction() async {
    // 💡 連打・多重リクエスト防止、クールダウン中は弾く
    if (_isLoading || _cooldownSeconds > 0) return;
    if (!_validateEmailPassword()) return;

    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            )
            .timeout(_authTimeout);

        // 💡 ログイン成功時は失敗カウントをリセットする
        _failedLoginAttempts = 0;
        _cooldownTimer?.cancel();
        if (mounted) setState(() => _cooldownSeconds = 0);
      } else {
        // 新規登録
        final String? sanitizedCode = _sanitizedInvitationCode();
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            )
            .timeout(_authTimeout);

        final String uid = userCredential.user?.uid ?? '';

        // Firestoreにユーザー作成
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': _emailController.text.trim(),
          'createdAt': FieldValue.serverTimestamp(),
          'usedInvitationCode': sanitizedCode,
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
      _handleAuthError(e);
    } on TimeoutException {
      if (mounted) {
        _showMessage('通信がタイムアウトしました。もう一度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💡 エラーコードごとの分岐。ログイン時は「ユーザー列挙」を防ぐため、
  //    存在有無に関わらず同じ汎用メッセージを返す
  void _handleAuthError(FirebaseAuthException e) {
    debugPrint('Auth error: ${e.code} ${e.message}');

    String message;

    if (_isLoginMode) {
      switch (e.code) {
        case 'too-many-requests':
          message = 'ログイン試行が多すぎます。しばらく時間をおいてからお試しください。';
          break;
        case 'user-disabled':
          message = 'このアカウントは現在ご利用いただけません。';
          break;
        default:
          // 💡 'user-not-found' と 'wrong-password' 等をあえて区別せず、
          //    第三者にアカウントの存在有無を推測されないようにする
          message = 'メールアドレスまたはパスワードが正しくありません。';
          _registerFailedLoginAttempt();
      }
    } else {
      switch (e.code) {
        case 'email-already-in-use':
          message = 'このメールアドレスは既に登録されています。';
          break;
        case 'weak-password':
          message = 'より強固なパスワードを設定してください。';
          break;
        case 'invalid-email':
          message = 'メールアドレスの形式が正しくありません。';
          break;
        default:
          message = 'アカウント作成に失敗しました。もう一度お試しください。';
      }
    }

    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --- ブルートフォース対策：失敗回数に応じたクールダウン ---
  void _registerFailedLoginAttempt() {
    _failedLoginAttempts += 1;

    if (_failedLoginAttempts % _attemptsPerLockout == 0) {
      final int lockoutLevel = _failedLoginAttempts ~/ _attemptsPerLockout;
      final int cooldown = (_baseCooldownSeconds * lockoutLevel).clamp(
        _baseCooldownSeconds,
        _maxCooldownSeconds,
      );
      _startCooldown(cooldown);
    }
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (!mounted) return;
    setState(() => _cooldownSeconds = seconds);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds <= 1) {
          _cooldownSeconds = 0;
          timer.cancel();
        } else {
          _cooldownSeconds -= 1;
        }
      });
    });
  }

  void _showMessage(String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // --- 🔴 Googleログイン処理 ---
  Future<void> _onGoogleButtonTapped() async {
    if (_isLoading || _cooldownSeconds > 0) return;
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn
          .signIn()
          .timeout(_authTimeout);
      if (googleUser == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(_authTimeout);
      await _handleFirebaseUserNavigation(userCredential);
    } on TimeoutException {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('通信がタイムアウトしました。もう一度お試しください。');
      }
    } catch (e) {
      debugPrint('Google login error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Googleログインに失敗しました。もう一度お試しください。'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // --- 🍏 Appleログイン処理 ---
  Future<void> _onAppleButtonTapped() async {
    if (_isLoading || _cooldownSeconds > 0) return;
    setState(() => _isLoading = true);
    try {
      // 💡 リプレイ攻撃対策：暗号学的に安全な乱数からnonceを生成し、
      //    そのSHA-256ハッシュをAppleに送る。Firebase側では元のnonceで検証する
      final String rawNonce = _generateNonce();
      final String hashedNonce = _sha256OfString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final OAuthProvider oAuthProvider = OAuthProvider('apple.com');
      final AuthCredential credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(_authTimeout);
      await _handleFirebaseUserNavigation(userCredential);
    } on TimeoutException {
      if (mounted) {
        setState(() => _isLoading = false);
        _showMessage('通信がタイムアウトしました。もう一度お試しください。');
      }
    } catch (e) {
      debugPrint('Apple login error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Appleログインに失敗しました。もう一度お試しください。'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // 💡 暗号学的に安全な乱数文字列を生成する（Sign in with Appleのnonce用）
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final Random random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256OfString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
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

    if (!mounted) return;

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
        final String? sanitizedCode = _sanitizedInvitationCode();

        // Firestoreにユーザー作成
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'usedInvitationCode': sanitizedCode,
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
    final bool isAuthDisabled = _isLoading || _cooldownSeconds > 0;

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
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: 'パスワード',
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        // 💡 パスワードはキーボードの予測変換・自動補完の学習対象から除外する
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!isAuthDisabled) _authAction();
                        },
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
                          maxLength: 10,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9]'),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 32),

                      if (_isLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        if (_cooldownSeconds > 0) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'ログイン試行が多いため、${_cooldownSeconds}秒後に再度お試しください。',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isAuthDisabled ? null : _authAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.bg,
                              disabledBackgroundColor: Colors.grey[300],
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
                            onPressed: isAuthDisabled
                                ? null
                                : _onGoogleButtonTapped,
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
                            onPressed: isAuthDisabled
                                ? null
                                : _onAppleButtonTapped,
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
}
