import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/screens/auth/login_screen.dart';

class EmailVerificationPendingScreen extends StatefulWidget {
  const EmailVerificationPendingScreen({super.key});

  @override
  State<EmailVerificationPendingScreen> createState() =>
      _EmailVerificationPendingScreenState();
}

class _EmailVerificationPendingScreenState
    extends State<EmailVerificationPendingScreen>
    with WidgetsBindingObserver {
  bool _isSending = false;
  bool _isChecking = false;
  bool _isSigningOut = false;
  bool _hasNavigated = false; // 💡 二重の画面遷移を防ぐ

  // 💡 再送クールダウン管理用
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;
  int _resendAttempts = 0;
  bool _isLockedOut = false; // 💡 再送上限に達してロック中かどうか

  // 💡 再送の基本クールダウン（秒）。連打対策として、送信するたびに倍に延長する
  static const int _baseCooldownSeconds = 60;
  static const int _maxCooldownSeconds = 300; // 上限5分
  static const int _maxResendAttempts = 5; // ロックまでの再送回数
  static const int _lockoutSeconds = 600; // 上限到達後のロック時間（10分）

  // 💡 通信が固まったときに、ボタンが押せないまま止まらないようにするための制限時間
  static const Duration _networkTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    // 💡 メールアプリでリンクを押して戻ってきたタイミングで自動チェックする
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // 💡 登録直後は確認メールを送ったばかりなので、すぐに再送できないようにする
      //    （画面を開いた瞬間に再送を押されて、メールが2通届くのを防ぐ）
      _startCooldown(_baseCooldownSeconds);
      // 💡 アプリを開き直したときに、すでにブラウザ側で認証が済んでいれば
      //    ボタンを押さなくても自動で先へ進めるようにする
      _checkEmailVerified(showFeedback: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 💡 バックグラウンドから復帰した時だけ、静かに（メッセージを出さずに）自動チェックする
    if (state == AppLifecycleState.resumed) {
      _checkEmailVerified(showFeedback: false);
    }
  }

  // --- 認証状態のチェック ---
  Future<void> _checkEmailVerified({bool showFeedback = true}) async {
    if (_isChecking || _hasNavigated || _isSigningOut) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
      return;
    }

    setState(() => _isChecking = true);

    try {
      await user.reload().timeout(_networkTimeout);
      if (!mounted) return;

      final updatedUser = FirebaseAuth.instance.currentUser;

      if (updatedUser != null && updatedUser.emailVerified) {
        // 💡 ログイン情報（IDトークン）を最新にする。
        //    これをしないと、Firestoreのルール側では「まだメール未確認」と判定されたままになり、
        //    最初の数十分間データの読み書きが拒否されてしまう
        await updatedUser.getIdToken(true).timeout(_networkTimeout);
        if (!mounted || _hasNavigated) return;

        _hasNavigated = true;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MyHomePage()),
          (route) => false,
        );
        return;
      }

      if (showFeedback && mounted) {
        _showSnackBar('まだ認証が完了していないようです。メール内のリンクをタップしてから、もう一度お試しください。');
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-token-expired' ||
          e.code == 'user-not-found' ||
          e.code == 'user-disabled') {
        _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
        return;
      }
      if (showFeedback && mounted) {
        _showSnackBar('確認に失敗しました。通信環境をご確認のうえ、もう一度お試しください。');
      }
      debugPrint('EmailVerification check error: ${e.code}');
    } on TimeoutException {
      if (showFeedback && mounted) {
        _showSnackBar('通信がタイムアウトしました。電波の良い場所でもう一度お試しください。');
      }
    } catch (e) {
      if (showFeedback && mounted) {
        _showSnackBar('通信エラーが発生しました。もう一度お試しください。');
      }
      debugPrint('EmailVerification check unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  // --- 確認メールを再送する ---
  Future<void> _resendEmail() async {
    if (_isSending || _cooldownSeconds > 0 || _isLockedOut) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
      return;
    }

    setState(() => _isSending = true);
    try {
      await user.sendEmailVerification().timeout(_networkTimeout);
      if (!mounted) return;

      _resendAttempts += 1;
      _showSnackBar('確認メールを再送しました。');

      if (_resendAttempts >= _maxResendAttempts) {
        // 💡 上限に達したら10分ロックし、ロックが明けたら回数をリセットする
        setState(() => _isLockedOut = true);
        _startCooldown(
          _lockoutSeconds,
          onFinished: () {
            _resendAttempts = 0;
            _isLockedOut = false;
          },
        );
      } else {
        // 💡 送信回数に応じてクールダウンを倍々に延長する（60秒→120秒→240秒→300秒）
        final int cooldown =
            (_baseCooldownSeconds * (1 << (_resendAttempts - 1))).clamp(
              _baseCooldownSeconds,
              _maxCooldownSeconds,
            );
        _startCooldown(cooldown);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'too-many-requests':
          _showSnackBar('リクエストが多すぎます。しばらく時間をおいてからお試しください。');
          _startCooldown(_maxCooldownSeconds);
          break;
        case 'network-request-failed':
          _showSnackBar('通信エラーが発生しました。電波状況をご確認ください。');
          break;
        case 'user-token-expired':
        case 'user-not-found':
        case 'user-disabled':
          _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
          return;
        default:
          _showSnackBar('メールの送信に失敗しました。もう一度お試しください。');
      }
      debugPrint('EmailVerification resend error: ${e.code}');
    } on TimeoutException {
      if (mounted) {
        _showSnackBar('通信がタイムアウトしました。電波の良い場所でもう一度お試しください。');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('予期しないエラーが発生しました。もう一度お試しください。');
      }
      debugPrint('EmailVerification resend unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // --- クールダウンタイマーの開始 ---
  void _startCooldown(int seconds, {VoidCallback? onFinished}) {
    _cooldownTimer?.cancel();
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
          onFinished?.call();
        } else {
          _cooldownSeconds -= 1;
        }
      });
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // --- ログイン画面への安全なリダイレクト ---
  void _redirectToLogin({required String message}) {
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;

    // 💡 画面が切り替わる前に、アプリ全体で共有しているメッセンジャーを取っておく
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  // --- ログアウト確認ダイアログ ---
  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ログアウトしますか？'),
        content: const Text(
          'メール認証が完了していません。ログアウトすると、再度ログインが必要になります。\n\n'
          'メールアドレスを間違えて登録した場合は、ログアウトして登録し直してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _signOut();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text(
              'ログアウト',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      _cooldownTimer?.cancel();
      await FirebaseAuth.instance.signOut();
      if (!mounted || _hasNavigated) return;

      // 💡 ログイン画面から「push」でこの画面に来た場合、ログアウトしても
      //    この画面が上に残ったままになるため、明示的にログイン画面へ戻す
      _hasNavigated = true;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('SignOut error: $e');
      if (mounted) {
        _showSnackBar('ログアウトに失敗しました。もう一度お試しください。');
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canResend =
        !_isSending && _cooldownSeconds == 0 && !_isLockedOut;
    final String? email = FirebaseAuth.instance.currentUser?.email;

    // 💡 戻るボタン・スワイプで戻ろうとした場合は、ログアウトの確認を出す
    //    （ログインしたままログイン画面に戻ると、状態がちぐはぐになるため）
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_isSigningOut) _showSignOutDialog();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('メール認証'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'ログアウト',
              icon: _isSigningOut
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              onPressed: _isSigningOut ? null : _showSignOutDialog,
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 100,
                    color: AppColors.point,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '確認メールを送信しました',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),

                  // 💡 送信先のアドレスを表示して、打ち間違いに気づけるようにする
                  if (email != null && email.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.point.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        email,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Text(
                    '届いたメール内のリンクをタップして、認証を完了させてください。\n'
                    '※届かない場合は迷惑メールフォルダもご確認ください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                  const SizedBox(height: 32),

                  // 認証チェックボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isChecking || _isSigningOut)
                          ? null
                          : () => _checkEmailVerified(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.point,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      child: _isChecking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('認証を完了しました'),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 再送ボタン（クールダウン中は残り時間を表示）
                  TextButton(
                    onPressed: canResend ? _resendEmail : null,
                    child: Text(_resendButtonLabel()),
                  ),

                  if (_isLockedOut) ...[
                    const SizedBox(height: 8),
                    const Text(
                      '再送回数の上限に達しました。しばらく時間をおいてからお試しください。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _resendButtonLabel() {
    if (_isSending) return '送信中...';
    if (_cooldownSeconds > 0) {
      final int minutes = _cooldownSeconds ~/ 60;
      final int seconds = _cooldownSeconds % 60;
      final String time = minutes > 0
          ? '$minutes分${seconds.toString().padLeft(2, '0')}秒'
          : '$seconds秒';
      return '再送まで $time';
    }
    return 'メールを再送する';
  }
}
