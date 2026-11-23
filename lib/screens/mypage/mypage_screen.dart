import 'dart:async';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/screens/auth/identity_verification_screen.dart';
import 'package:matching_app/screens/profile/profile_setup_screen.dart';
import 'package:matching_app/screens/settings/about_frendy_screen.dart';
import 'package:matching_app/screens/settings/app_settings_screen.dart';
import 'package:matching_app/screens/settings/help_support_screen.dart';
import 'package:matching_app/screens/settings/privacy_policy_screen.dart';
import 'package:matching_app/screens/settings/terms_of_service_screen.dart';
import 'package:matching_app/screens/subscription/subscription_screen.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';

const String _kFunctionsRegion = 'asia-northeast1';

// 限定バッジの見た目（ホーム画面と同じ色にそろえる）
const Color _kSilverColor = Color(0xFF9E9E9E);
const Color _kGoldColor = Color(0xFFFFB300);

// 各ストアのサブスクリプション管理画面（解約はここで行う）
final Uri _kAppleSubscriptionsUrl = Uri.parse(
  'https://apps.apple.com/account/subscriptions',
);
final Uri _kGoogleSubscriptionsUrl = Uri.parse(
  'https://play.google.com/store/account/subscriptions',
);

class MypageScreen extends StatefulWidget {
  const MypageScreen({super.key});

  @override
  State<MypageScreen> createState() => _MypageScreenState();
}

class _MypageScreenState extends State<MypageScreen> {
  late final String? _uid;

  // 💡 Stream は一度だけ作る（再描画のたびに再購読しない）
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _myStream;

  bool _busy = false; // ログアウト・退会の多重実行防止

  // 退会時の案内に使う（有料プランの人には、先に解約を案内する）
  String _plan = 'free';

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    if (_uid != null) {
      _myStream = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .snapshots();
    }
  }

  void _showGlobalSnack(String message, {bool isError = false}) {
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : null,
        ),
      );
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    // ログイン状態が切れた場合は main.dart の authStateChanges が
    // 自動でログイン画面に切り替えるので、ここでは待機表示だけにする
    if (_uid == null || _myStream == null) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
            onPressed: () => _push(const ProfileSetupScreen()),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _myStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            debugPrint('マイページ取得エラー: ${snapshot.error}');
            return const Center(child: Text('エラーが発生しました'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() ?? {};
          final images = data['imageUrls'];
          final String imageUrl =
              images is List && images.isNotEmpty && images.first is String
              ? images.first as String
              : '';
          final rawName = data['name'];
          final String name = rawName is String && rawName.trim().isNotEmpty
              ? rawName
              : '名前未設定';
          final rawBadge = data['badge'];
          final String badge = rawBadge == 'gold' || rawBadge == 'silver'
              ? rawBadge as String
              : '';
          final rawPlan = data['plan'];
          _plan = rawPlan is String ? rawPlan : 'free';
          final String fullId = _uid!;
          final String shortId = fullId.length >= 8
              ? fullId.substring(0, 8)
              : fullId;

          return LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: _buildBody(
                      name: name,
                      badge: badge,
                      fullId: fullId,
                      shortId: shortId,
                      imageUrl: imageUrl,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody({
    required String name,
    required String badge,
    required String fullId,
    required String shortId,
    required String imageUrl,
  }) {
    return Column(
      children: [
        const SizedBox(height: 16),

        // --- プロフィール写真 ---
        Center(
          child: ClipOval(
            child: Container(
              width: 96,
              height: 96,
              color: Colors.grey[200],
              // 💡 端末に画像を保存して使い回す（毎回ダウンロードしない）
              child: imageUrl.startsWith('https://')
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 330,
                      memCacheHeight: 330,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) =>
                          Icon(Icons.person, size: 50, color: Colors.grey[400]),
                    )
                  : Icon(Icons.person, size: 50, color: Colors.grey[400]),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // --- 名前 ＋ 限定バッジ ---
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (badge.isNotEmpty) ...[
                const SizedBox(width: 6),
                _BadgeIcon(badge: badge),
              ],
            ],
          ),
        ),

        const SizedBox(height: 4),

        // --- ID表示 & コピー ---
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
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.copy, size: 14, color: Colors.grey),
            ],
          ),
        ),

        const SizedBox(height: 10),
        const Divider(thickness: 1, height: 1),

        // --- 設定項目 ---
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSettingsItem(
                icon: Icons.edit,
                label: 'プロフィール編集',
                onTap: () => _push(const ProfileSetupScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.card_membership,
                label: 'サブスクリプション管理',
                onTap: () => _push(const SubscriptionScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.verified_user,
                label: '年齢確認・本人確認',
                onTap: () => _push(const IdentityVerificationScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.settings,
                label: 'アプリ設定',
                onTap: () => _push(const AppSettingsScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.info_outline,
                label: 'Frendyの説明',
                onTap: () => _push(const AboutFrendyScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.help_outline,
                label: 'ヘルプ・お問い合わせ',
                onTap: () => _push(const HelpSupportScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.privacy_tip_outlined,
                label: 'プライバシーポリシー',
                onTap: () => _push(const PrivacyPolicyScreen()),
              ),
              _buildSettingsItem(
                icon: Icons.description_outlined,
                label: '利用規約',
                onTap: () => _push(const TermsOfServiceScreen()),
              ),

              const Divider(),

              _buildSettingsItem(
                icon: Icons.logout,
                label: 'ログアウト',
                labelColor: Colors.redAccent,
                onTap: _logout,
              ),
              _buildSettingsItem(
                icon: Icons.person_off,
                label: '退会する',
                labelColor: Colors.grey,
                onTap: _showDeleteDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color labelColor = Colors.black87,
  }) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(label, style: TextStyle(color: labelColor, fontSize: 16)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: _busy ? null : onTap,
    );
  }

  // ==========================================================================
  // ログアウト
  // ==========================================================================

  // 💡 Firebase と Google の両方からサインアウトする
  Future<void> _signOutEverywhere() async {
    try {
      final google = GoogleSignIn();
      if (await google.isSignedIn()) await google.signOut();
    } catch (e) {
      debugPrint('Googleサインアウトエラー: $e');
    }
    await FirebaseAuth.instance.signOut();
  }

  // 💡 ログイン画面を手動で積み直すと、main.dart のログイン状態の監視が外れて
  //    再ログイン後にホームへ戻れなくなる。
  //    最初の画面まで戻すだけにして、表示の切り替えは main.dart に任せる
  void _backToRoot() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _signOutEverywhere();
      if (!mounted) return;
      _backToRoot();
      _showGlobalSnack('ログアウトしました');
    } catch (e) {
      debugPrint('ログアウトエラー: $e');
      _showGlobalSnack('ログアウトに失敗しました。もう一度お試しください。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ==========================================================================
  // 退会
  // ==========================================================================
  // 💡 有料プランの人は、退会してもストアの定期購入が続いてしまう。
  //    退会の確認の前に、解約の案内と管理画面を開くボタンを出す
  void _showDeleteDialog() {
    if (_plan != 'free') {
      _showCancelSubscriptionFirstDialog();
      return;
    }
    _showDeleteConfirmDialog();
  }

  Future<void> _openStoreSubscriptions() async {
    final Uri url = Platform.isIOS
        ? _kAppleSubscriptionsUrl
        : _kGoogleSubscriptionsUrl;
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launchUrl returned false');
    } catch (e) {
      debugPrint('サブスクリプション管理画面の起動エラー: $e');
      _showGlobalSnack(
        Platform.isIOS
            ? '「設定」アプリ →「自分の名前」→「サブスクリプション」から解約できます'
            : 'Google Play ストア →「お支払いと定期購入」→「定期購入」から解約できます',
      );
    }
  }

  void _showCancelSubscriptionFirstDialog() {
    final String steps = Platform.isIOS
        ? '【iPhone の解約方法】\n'
              '1.「設定」アプリを開く\n'
              '2. いちばん上の「自分の名前」をタップ\n'
              '3.「サブスクリプション」をタップ\n'
              '4.「frendy」を選び、「サブスクリプションをキャンセルする」をタップ'
        : '【Android の解約方法】\n'
              '1.「Google Play ストア」アプリを開く\n'
              '2. 右上のプロフィールアイコンをタップ\n'
              '3.「お支払いと定期購入」→「定期購入」をタップ\n'
              '4.「frendy」を選び、「定期購入を解約」をタップ';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '先に有料プランの解約を',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Text(
            '有料プランをご利用中です。\n'
            '退会しても、${Platform.isIOS ? 'App Store' : 'Google Play'} の定期購入は自動では解約されず、料金の請求が続きます。'
            '退会の前に、必ず解約の手続きをしてください。\n\n$steps',
            style: const TextStyle(height: 1.6),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _showDeleteConfirmDialog();
            },
            child: const Text(
              '解約済み・退会へ進む',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openStoreSubscriptions();
            },
            child: const Text(
              '解約画面を開く',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog() {
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
          '本当に退会しますか？\n'
          'プロフィール・トーク・友達・いいね・提出済みの本人確認書類を含むすべてのデータが完全に消去され、復旧できません。\n\n'
          '※ 有料プランをご利用中の場合、退会しても App Store / Google Play の定期購入は自動で解約されません。'
          '先にストアの設定から解約してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deleteAccount();
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

  // 💡 Apple でログインしたユーザーは、退会時に Apple 側の連携も解除する必要がある
  //    （App Store の審査ガイドラインで必須）。
  //    解除には本人による Apple の再認証が必要なため、ここで Apple のサインイン画面を出す
  Future<void> _revokeAppleIfNeeded(User user) async {
    final bool isApple = user.providerData.any(
      (p) => p.providerId == 'apple.com',
    );
    if (!isApple || defaultTargetPlatform != TargetPlatform.iOS) return;

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [],
    );
    await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(
      credential.authorizationCode,
    );
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        ),
      ),
    );
  }

  // サーバーでアカウントが削除済みかどうかを確認する
  Future<bool> _isAccountGone() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      return FirebaseAuth.instance.currentUser == null;
    } on FirebaseAuthException catch (e) {
      return e.code == 'user-not-found' || e.code == 'user-disabled';
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _busy) return;
    setState(() => _busy = true);

    bool loadingShown = false;
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    try {
      // 1. Apple の連携解除（Apple ログインのユーザーのみ）
      await _revokeAppleIfNeeded(user);

      // 2. サーバーでデータとアカウントを削除
      //    （他のユーザーのデータから自分を消す処理は、権限上アプリからはできない）
      if (!mounted) return;
      _showLoading();
      loadingShown = true;

      try {
        await FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
            .httpsCallable(
              'deleteAccount',
              options: HttpsCallableOptions(
                timeout: const Duration(minutes: 3),
              ),
            )
            .call();
      } on FirebaseFunctionsException catch (e) {
        // 💡 通信が途中で切れたりタイムアウトしたりしても、サーバー側では削除が
        //    最後まで進んでいることがある。アカウントがもう存在しなければ「成功」と扱う
        if (!await _isAccountGone()) rethrow;
        debugPrint('退会：応答は失敗したが、アカウントは削除済み（${e.code}）');
      }

      // 3. ローディングを閉じてから、端末側のサインアウト
      //    （先に閉じておくと、ログイン画面への切り替わりと重ならない）
      rootNavigator.pop();
      loadingShown = false;
      await _signOutEverywhere();

      rootNavigator.popUntil((route) => route.isFirst);
      _showGlobalSnack('退会およびデータの削除が完了しました');
    } on SignInWithAppleAuthorizationException catch (e) {
      // Apple の再認証をキャンセルした場合は、何もせずマイページに留まる
      debugPrint('Apple再認証の中断: $e');
      if (e.code != AuthorizationErrorCode.canceled) {
        _showGlobalSnack('Appleの認証に失敗しました。もう一度お試しください。', isError: true);
      }
    } catch (e) {
      debugPrint('退会処理エラー: $e');
      if (loadingShown) {
        rootNavigator.pop();
        loadingShown = false;
      }
      // 💡 失敗時はログアウトさせない。ログイン状態のまま、もう一度退会を試せるようにする
      //    （サーバー側の削除は、途中で失敗しても再実行すれば続きから消える）
      _showGlobalSnack('退会処理に失敗しました。通信環境を確認して、もう一度お試しください。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ----------------------------------------------------------------------------
// 限定バッジのアイコン（タップすると説明が出る）
// ----------------------------------------------------------------------------
class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.badge});

  final String badge; // 'silver' または 'gold'

  @override
  Widget build(BuildContext context) {
    final bool isGold = badge == 'gold';
    final Color color = isGold ? _kGoldColor : _kSilverColor;
    final String label = isGold ? '金バッジ' : '銀バッジ';
    final String desc = isGold
        ? '10人にメッセージを送って獲得した限定バッジです'
        : '5人にメッセージを送って獲得した限定バッジです';

    return Tooltip(
      message: '$label：$desc',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 3),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Icon(Icons.military_tech_rounded, color: color, size: 20),
      ),
    );
  }
}
