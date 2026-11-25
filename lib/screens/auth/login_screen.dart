import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart'; // scaffoldMessengerKey・MyHomePage を使うためにインポート
import 'package:matching_app/screens/auth/email_verification_pending_screen.dart';
import 'package:matching_app/screens/settings/privacy_policy_screen.dart';
import 'package:matching_app/screens/settings/terms_of_service_screen.dart';

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
  bool _agreedToTerms = false; // 💡 新規登録時の「18歳以上・利用規約・プライバシーポリシー」への同意
  bool _obscurePassword = true;

  // 💡 GoogleSignInはボタンを押すたびに生成するのではなく、使い回す
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '982968813521-d13g927ltrui44d8s79fk6ogl7ft5n3o.apps.googleusercontent.com',
  );

  // 💡 ブルートフォース対策：ログイン失敗が続いた場合のクールダウン管理
  //    （本当の歯止めはFirebase側の制限。こちらは画面上で連打を防ぐためのもの）
  int _failedLoginAttempts = 0;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  static const int _attemptsPerLockout = 5;
  static const int _baseCooldownSeconds = 30;
  static const int _maxCooldownSeconds = 300; // 上限5分

  // 💡 新規登録時のパスワードの最低文字数
  static const int _minPasswordLength = 8;

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

  // ==========================================
  // 入力チェック
  // ==========================================
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

    if (!_isLoginMode && password.length < _minPasswordLength) {
      _showMessage('パスワードは$_minPasswordLength文字以上で入力してください。');
      return false;
    }

    return true;
  }

  // 💡 新規登録の前に、同意のチェックが入っているかを確認する
  bool _checkAgreement() {
    if (_isLoginMode || _agreedToTerms) return true;
    _showMessage('18歳以上であることと、利用規約・プライバシーポリシーへの同意が必要です。');
    return false;
  }

  // 💡 招待コードは英数字のみ・8文字（サーバーが発行するコードの長さ）に整える
  static const int _inviteCodeLength = 8;

  String? _sanitizedInvitationCode() {
    final raw = _invitationCodeController.text.trim();
    if (raw.isEmpty) return null;
    final sanitized = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (sanitized.isEmpty) return null;
    return sanitized.length > _inviteCodeLength
        ? sanitized.substring(0, _inviteCodeLength)
        : sanitized;
  }

  // 💡 招待コードはサーバー（redeemInviteCode）に送って登録する。
  //    コードが間違っていても、アカウント登録自体は止めない
  //    （ホームの招待バナーの「詳細」から、登録後7日以内ならもう一度入力できる）
  Future<void> _redeemInvitationCode(String? code) async {
    if (code == null) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast1')
          .httpsCallable(
            'redeemInviteCode',
            options: HttpsCallableOptions(timeout: _authTimeout),
          )
          .call({'code': code});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('招待コード登録エラー: ${e.code} ${e.message}');
      if (e.code == 'already-exists') return;
      _showMessage(
        '${e.message ?? '招待コードを登録できませんでした'}。'
        'ホームの招待バナーの「詳細」から、もう一度入力できます。',
      );
    } catch (e) {
      debugPrint('招待コード登録エラー: $e');
      _showMessage('招待コードを登録できませんでした。ホームの招待バナーの「詳細」から、もう一度入力できます。');
    }
  }

  // ==========================================
  // ユーザー情報（Firestore）の作成
  // ==========================================
  //    メール登録・Google/Apple登録・「登録途中で失敗した人の修復」で共通して使う
  //
  // 💡 users/{uid} はログインしている人なら誰でも読める（プロフィールを見せるため）。
  //    そのためメールアドレスなどの個人情報は、本人だけが読める
  //    users/{uid}/private/account に分けて保存する。
  //    招待コードはサーバー（redeemInviteCode）で登録し、ここには書かない。
  //    （以前の「ユーザーIDの先頭8文字を招待コードにする」方式は、IDの一部が漏れるため廃止）
  Future<void> _createUserDoc({
    required String uid,
    required String email,
    required bool agreed,
  }) async {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);
    final batch = db.batch();
    batch.set(userRef, {
      'createdAt': FieldValue.serverTimestamp(),
      'isProfileCompleted': false,
    });
    batch.set(userRef.collection('private').doc('account'), {
      'email': email,
      // 💡 いつ利用規約に同意したかを記録しておく（トラブル時の証拠になる）
      if (agreed) 'agreedToTermsAt': FieldValue.serverTimestamp(),
    });
    await batch.commit().timeout(_authTimeout);
  }

  // ==========================================
  // 📧 メール・パスワードでの認証処理
  // ==========================================
  Future<void> _authAction() async {
    if (_isLoading || _cooldownSeconds > 0) return;
    if (!_validateEmailPassword()) return;
    if (!_checkAgreement()) return;

    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    // 💡 入力内容は最初に取り出しておく
    //    （途中で画面が自動で差し替えられると、入力欄が破棄されて読めなくなるため）
    final String email = _emailController.text.trim();
    final String password = _passwordController.text.trim();
    final String? invitationCode = _sanitizedInvitationCode();

    try {
      if (_isLoginMode) {
        final UserCredential credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password)
            .timeout(_authTimeout);

        // 💡 ログイン成功時は失敗カウントをリセットする
        _failedLoginAttempts = 0;
        _cooldownTimer?.cancel();
        if (mounted) setState(() => _cooldownSeconds = 0);

        final User? user = credential.user;
        if (user != null) await _completeEmailLogin(user, email);
      } else {
        // --- 新規登録 ---
        final UserCredential credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password)
            .timeout(_authTimeout);

        final User? user = credential.user;
        if (user == null) throw Exception('ユーザー作成に失敗しました');

        await _createUserDoc(uid: user.uid, email: email, agreed: true);
        await _redeemInvitationCode(invitationCode);

        // 💡 確認メールの送信に失敗しても、次の画面から再送できるので登録自体は続行する
        try {
          await user.sendEmailVerification().timeout(_authTimeout);
        } catch (e) {
          debugPrint('確認メール送信エラー: $e');
        }

        _showMessage('確認メールを送信しました。');
        _goTo(const EmailVerificationPendingScreen());
      }
    } on FirebaseAuthException catch (e) {
      _handleAuthError(e);
    } on TimeoutException {
      _showMessage('通信がタイムアウトしました。電波の良い場所でもう一度お試しください。');
    } catch (e) {
      // 💡 Firestoreの保存失敗など、想定外のエラーでも画面が固まらないようにする
      debugPrint('Auth unexpected error: $e');
      _showMessage('エラーが発生しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 💡 メールでログインした後の行き先を決める
  //    （ログアウト後はこの画面が一番下に来るため、ログインしただけでは
  //      画面が切り替わらない。行き先を明示的に指定する）
  Future<void> _completeEmailLogin(User user, String typedEmail) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .timeout(_authTimeout);

    // 💡 登録の途中（ユーザー情報の保存前）で通信が切れた人を救済する
    //    （画面が自動で差し替えられていても、ここは最後まで実行する）
    if (!doc.exists) {
      await _createUserDoc(
        uid: user.uid,
        email: user.email ?? typedEmail,
        agreed: false,
      );
    }

    if (user.emailVerified) {
      _goTo(const MyHomePage());
    } else {
      _showMessage('メール認証が完了していません。届いたメールのリンクをタップしてください。');
      _goTo(const EmailVerificationPendingScreen());
    }
  }

  // 💡 これまでの画面履歴を消して移動する（戻るボタンでログイン画面に戻らないように）
  void _goTo(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  // 💡 エラーコードごとの分岐。ログイン時は「ユーザー列挙」を防ぐため、
  //    存在有無に関わらず同じ汎用メッセージを返す
  void _handleAuthError(FirebaseAuthException e) {
    debugPrint('Auth error: ${e.code}');

    String message;

    if (_isLoginMode) {
      switch (e.code) {
        case 'too-many-requests':
          message = 'ログイン試行が多すぎます。しばらく時間をおいてからお試しください。';
          break;
        case 'user-disabled':
          message = 'このアカウントは現在ご利用いただけません。';
          break;
        case 'network-request-failed':
          message = '通信エラーが発生しました。電波状況をご確認ください。';
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
          message = 'このメールアドレスは既に登録されています。ログイン画面からお試しください。';
          break;
        case 'weak-password':
          message = 'より強固なパスワードを設定してください。';
          break;
        case 'invalid-email':
          message = 'メールアドレスの形式が正しくありません。';
          break;
        case 'network-request-failed':
          message = '通信エラーが発生しました。電波状況をご確認ください。';
          break;
        default:
          message = 'アカウント作成に失敗しました。もう一度お試しください。';
      }
    }

    _showMessage(message);
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

  void _showMessage(String message, {Color? backgroundColor}) {
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: backgroundColor),
      );
  }

  // ==========================================
  // 🔴 Googleログイン
  // ==========================================
  Future<void> _onGoogleButtonTapped() async {
    if (_isLoading || _cooldownSeconds > 0) return;
    if (!_checkAgreement()) return;
    final String? invitationCode = _sanitizedInvitationCode();
    setState(() => _isLoading = true);

    try {
      // 💡 前回選んだアカウントが自動で使われないよう、一度サインアウトしてから選ばせる
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? googleUser = await _googleSignIn
          .signIn()
          .timeout(const Duration(minutes: 2)); // アカウント選択画面で迷う時間も考慮
      if (googleUser == null) return; // ユーザーがキャンセルした

      final GoogleSignInAuthentication googleAuth = await googleUser
          .authentication
          .timeout(_authTimeout);
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(_authTimeout);
      await _handleSocialSignIn(userCredential, invitationCode);
    } on FirebaseAuthException catch (e) {
      _handleSocialAuthError(e, 'Google');
    } on TimeoutException {
      _showMessage('通信がタイムアウトしました。もう一度お試しください。');
    } catch (e) {
      debugPrint('Google login error: $e');
      _showMessage(
        'Googleログインに失敗しました。もう一度お試しください。',
        backgroundColor: Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================
  // 🍏 Appleログイン
  // ==========================================
  Future<void> _onAppleButtonTapped() async {
    if (_isLoading || _cooldownSeconds > 0) return;
    if (!_checkAgreement()) return;
    final String? invitationCode = _sanitizedInvitationCode();
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

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(_authTimeout);
      await _handleSocialSignIn(userCredential, invitationCode);
    } on SignInWithAppleAuthorizationException catch (e) {
      // 💡 ユーザーが自分でキャンセルした場合は、エラーを出さない
      if (e.code != AuthorizationErrorCode.canceled) {
        debugPrint('Apple authorization error: ${e.code}');
        _showMessage(
          'Appleログインに失敗しました。もう一度お試しください。',
          backgroundColor: Colors.redAccent,
        );
      }
    } on FirebaseAuthException catch (e) {
      _handleSocialAuthError(e, 'Apple');
    } on TimeoutException {
      _showMessage('通信がタイムアウトしました。もう一度お試しください。');
    } catch (e) {
      debugPrint('Apple login error: $e');
      _showMessage(
        'Appleログインに失敗しました。もう一度お試しください。',
        backgroundColor: Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleSocialAuthError(FirebaseAuthException e, String provider) {
    debugPrint('$provider auth error: ${e.code}');
    switch (e.code) {
      case 'account-exists-with-different-credential':
        _showMessage('このメールアドレスは別の方法で登録されています。最初に登録した方法でログインしてください。');
        break;
      case 'user-disabled':
        _showMessage('このアカウントは現在ご利用いただけません。');
        break;
      case 'network-request-failed':
        _showMessage('通信エラーが発生しました。電波状況をご確認ください。');
        break;
      default:
        _showMessage(
          '$providerログインに失敗しました。もう一度お試しください。',
          backgroundColor: Colors.redAccent,
        );
    }
  }

  // 💡 暗号学的に安全な乱数文字列を生成する（Sign in with Appleのnonce用）
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
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

  // ==========================================
  // 🚀 Google/Appleでログインした後の共通処理
  // ==========================================
  Future<void> _handleSocialSignIn(
    UserCredential userCredential,
    String? invitationCode,
  ) async {
    final User? user = userCredential.user;
    if (user == null) throw Exception('ユーザー情報を取得できませんでした');

    // 💡 ここから先は「画面が閉じられていても」最後まで実行する。
    //    アプリを初めて開いたときはmain.dartがログイン状態を見張っていて、
    //    ログインした瞬間にこの画面を自動でホーム画面に差し替えてしまう。
    //    以前はそこで処理が止まり、ユーザー情報が作られないままホームに入っていた
    final myDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .timeout(_authTimeout);

    if (!myDoc.exists) {
      if (_isLoginMode) {
        // 【ログインモード】未登録なので弾く
        // 💡 Google/Appleでのログインは、その瞬間にFirebase側のアカウントが作られてしまう。
        //    今作られたばかりのアカウントなら削除して、使われないアカウントが溜まらないようにする
        if (userCredential.additionalUserInfo?.isNewUser == true) {
          try {
            await user.delete();
          } catch (e) {
            debugPrint('未登録アカウントの削除エラー: $e');
          }
        }
        await FirebaseAuth.instance.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {}

        _showMessage(
          'アカウントが登録されていません。「新規アカウント作成はこちら」から登録してください。',
          backgroundColor: Colors.redAccent,
        );
        return;
      }

      // 【新規登録モード】ユーザー情報を作成する
      try {
        await _createUserDoc(
          uid: user.uid,
          email: user.email ?? '',
          agreed: true,
        );
      } catch (e) {
        // 💡 ユーザー情報の保存に失敗したら、ログインした状態のまま放置せずに
        //    ログアウトして、最初からやり直してもらう（中途半端な状態でホームに入らないように）
        await FirebaseAuth.instance.signOut();
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
        rethrow;
      }
      _showMessage('アカウントを作成しました。');
      await _redeemInvitationCode(invitationCode);
    }

    // 💡 Google・Appleのアカウントはメール確認済みとして扱われるので、そのままホームへ
    _goTo(const MyHomePage());
  }

  // ==========================================
  // 画面
  // ==========================================
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
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 24.0,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 💡 新規登録のときは、招待コードと同意を一番上に置く。
                      //    メール・Google・Apple のどの方法で登録しても使われる
                      if (!_isLoginMode) ...[
                        _buildSignupCommonSection(),
                        const SizedBox(height: 24),
                      ],
                      TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'メールアドレス',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'パスワード',
                          helperText: _isLoginMode
                              ? null
                              : '$_minPasswordLength文字以上で入力してください',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        // 💡 パスワードはキーボードの予測変換・自動補完の学習対象から除外する
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _isLoginMode
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!isAuthDisabled) _authAction();
                        },
                      ),

                      const SizedBox(height: 24),

                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...[
                        if (_cooldownSeconds > 0) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'ログイン試行が多いため、$_cooldownSeconds秒後に再度お試しください。',
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
                            _agreedToTerms = false;
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
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 💡 新規登録で共通の欄（招待コード・同意）。どの登録方法でも使われる
  Widget _buildSignupCommonSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _invitationCodeController,
            decoration: const InputDecoration(
              labelText: '友達の招待コード（お持ちの方）',
              hintText: '例: AB12CD34',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(Icons.card_giftcard, color: Colors.orange),
            ),
            textCapitalization: TextCapitalization.characters,
            maxLength: _inviteCodeLength,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            ],
          ),
          Text(
            'メール・Google・Apple のどの方法で登録しても使えます。'
            'あとから入力する場合は、登録後7日以内にホームの招待バナーの「詳細」から入力できます。',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              height: 1.5,
            ),
          ),
          _buildAgreementCheckbox(),
        ],
      ),
    );
  }

  // 💡 新規登録時の同意チェック（App Storeの審査でも、利用規約への同意が求められる）
  Widget _buildAgreementCheckbox() {
    const TextStyle normal = TextStyle(fontSize: 13, color: Colors.black87);
    const TextStyle link = TextStyle(
      fontSize: 13,
      color: AppColors.point,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.underline,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: _agreedToTerms,
            activeColor: AppColors.point,
            onChanged: (value) =>
                setState(() => _agreedToTerms = value ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                children: [
                  const Text('18歳以上であり、', style: normal),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TermsOfServiceScreen(),
                      ),
                    ),
                    child: const Text('利用規約', style: link),
                  ),
                  const Text('と', style: normal),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
                    child: const Text('プライバシーポリシー', style: link),
                  ),
                  const Text('に同意します', style: normal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
