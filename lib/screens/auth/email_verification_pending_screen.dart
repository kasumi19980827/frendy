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

  // 💡 再送クールダウン管理用
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;
  int _resendAttempts = 0;

  // 💡 再送の基本クールダウン（秒）。連打対策として、送信するたびに指数関数的に延長する
  static const int _baseCooldownSeconds = 60;
  static const int _maxCooldownSeconds = 300; // 上限5分
  static const int _maxResendAttempts = 5; // 1セッションあたりの再送上限回数
  static const int _lockoutSeconds = 600; // 上限到達後のロック時間（10分）

  @override
  void initState() {
    super.initState();
    // 💡 アプリのライフサイクル（バックグラウンド→フォアグラウンド復帰）を監視する
    //    ユーザーがメールアプリを開いて戻ってきたタイミングで自動チェックすることで、
    //    手動タップの回数を減らし、サーバー負荷を抑える
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 💡 Timerとオブザーバーの解放を必ず行う。
    //    解放漏れは1画面あたりは軽微でも、1万人規模では
    //    メモリリークやdispose後のsetStateによるクラッシュの温床になる
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 💡 バックグラウンドから復帰した時だけ、静かに（エラーメッセージを出さずに）自動チェックする
    if (state == AppLifecycleState.resumed) {
      _checkEmailVerified(showFeedback: false);
    }
  }

  // --- 認証状態のチェック ---
  Future<void> _checkEmailVerified({bool showFeedback = true}) async {
    // 💡 連打・多重リクエスト防止
    if (_isChecking) return;

    final user = FirebaseAuth.instance.currentUser;

    // 💡 セッション切れ（他端末でのログアウト等）を考慮し、
    //    nullの場合は安全にログイン画面へ戻す
    if (user == null) {
      _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
      return;
    }

    setState(() => _isChecking = true);

    try {
      await user.reload(); // Firebaseサーバーの状態をアプリに同期
      if (!mounted) return;

      final updatedUser = FirebaseAuth.instance.currentUser;

      if (updatedUser != null && updatedUser.emailVerified) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MyHomePage()),
          (route) => false, // これまでの画面履歴（ログイン画面など）をすべて消去する
        );
        return;
      }

      // 自動チェック（バックグラウンド復帰時）では、未認証でも通知しない
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('まだ認証が完了していないようです。')));
      }
    } on FirebaseAuthException catch (e) {
      // 💡 セッション自体が無効になっているケース（トークン失効など）
      if (e.code == 'user-token-expired' || e.code == 'user-not-found') {
        _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
        return;
      }
      if (showFeedback && mounted) {
        _showErrorSnackBar('確認に失敗しました。通信環境をご確認のうえ、もう一度お試しください。');
      }
      debugPrint('EmailVerification check error: ${e.code} ${e.message}');
    } catch (e) {
      // 💡 内部エラー内容はユーザーに見せず、ログにのみ残す
      if (showFeedback && mounted) {
        _showErrorSnackBar('通信エラーが発生しました。もう一度お試しください。');
      }
      debugPrint('EmailVerification check unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  // --- 確認メールを再送する ---
  Future<void> _resendEmail() async {
    // 💡 クールダウン中・送信中・上限到達時は何もしない（多重送信防止）
    if (_isSending || _cooldownSeconds > 0) return;

    if (_resendAttempts >= _maxResendAttempts) {
      _showErrorSnackBar('再送回数の上限に達しました。しばらく時間をおいてから再度お試しください。');
      _startCooldown(_lockoutSeconds);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
      return;
    }

    setState(() => _isSending = true);
    try {
      await user.sendEmailVerification();
      if (!mounted) return;

      _resendAttempts += 1;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('確認メールを再送しました。')));

      // 💡 送信回数に応じてクールダウンを指数関数的に延長し、連打・乱用を抑止する
      final int cooldown = (_baseCooldownSeconds * (1 << (_resendAttempts - 1)))
          .clamp(_baseCooldownSeconds, _maxCooldownSeconds);
      _startCooldown(cooldown);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'too-many-requests':
          // 💡 Firebase側のレート制限に引っかかった場合は、長めのクールダウンを設定する
          _showErrorSnackBar('リクエストが多すぎます。しばらく時間をおいてからお試しください。');
          _startCooldown(_maxCooldownSeconds);
          break;
        case 'network-request-failed':
          _showErrorSnackBar('通信エラーが発生しました。電波状況をご確認ください。');
          break;
        case 'user-token-expired':
        case 'user-not-found':
          _redirectToLogin(message: 'セッションの有効期限が切れました。再度ログインしてください。');
          return;
        default:
          // 💡 内部の例外詳細はユーザーへ表示せず、ログにのみ記録する
          _showErrorSnackBar('メールの送信に失敗しました。もう一度お試しください。');
      }
      debugPrint('EmailVerification resend error: ${e.code} ${e.message}');
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('予期しないエラーが発生しました。もう一度お試しください。');
      }
      debugPrint('EmailVerification resend unexpected error: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  // --- クールダウンタイマーの開始 ---
  void _startCooldown(int seconds) {
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
        } else {
          _cooldownSeconds -= 1;
        }
      });
    });
  }

  // --- 汎用エラースナックバー（内部詳細を出さない） ---
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- ログイン画面への安全なリダイレクト ---
  void _redirectToLogin({required String message}) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  // --- ログアウト確認ダイアログ ---
  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ログアウトしますか？'),
        content: const Text('メール認証が完了していません。ログアウトすると、再度ログインが必要になります。'),
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
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('SignOut error: $e');
      if (mounted) {
        _showErrorSnackBar('ログアウトに失敗しました。もう一度お試しください。');
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canResend =
        !_isSending &&
        _cooldownSeconds == 0 &&
        _resendAttempts < _maxResendAttempts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('メール認証'),
        actions: [
          IconButton(
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
      body: Padding(
        padding: const EdgeInsets.all(24.0),
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
            const SizedBox(height: 16),
            const Text(
              '届いたメール内のリンクをタップ・ボタンをクリックして、認証を完了させてください。\n※届かない場合は迷惑メールフォルダも\nご確認ください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 32),

            // 認証チェックボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isChecking ? null : () => _checkEmailVerified(),
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

            // 再送ボタン（クールダウン中は残り秒数を表示）
            TextButton(
              onPressed: canResend ? _resendEmail : null,
              child: Text(_resendButtonLabel()),
            ),

            if (_resendAttempts >= _maxResendAttempts &&
                _cooldownSeconds > 0) ...[
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
    );
  }

  String _resendButtonLabel() {
    if (_isSending) return '送信中...';
    if (_cooldownSeconds > 0) return '再送まで ${_cooldownSeconds}秒';
    return 'メールを再送する';
  }
}
