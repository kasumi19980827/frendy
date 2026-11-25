import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/settings/privacy_policy_screen.dart';
import 'package:matching_app/screens/settings/terms_of_service_screen.dart';
import 'package:matching_app/screens/settings/tokushoho_screen.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// メンバーシッププラン（サブスクリプション管理）
//
// 💡 現在の状態
//  ・plan は「サーバーだけが書き換えられる」項目（セキュリティルールで保護済み）。
//    以前のようにアプリから plan を書き換えて、お金を払わずに有料プランに
//    なることはできない。
//  ・本物の課金（App Store / Google Play）はまだ組み込んでいない。
//    そのため「〇〇プランにする」ボタンは、今は「準備中」の案内を出すだけ。
//
// 💡 本物の課金を組み込むときの流れ（次の作業）
//  1. App Store Connect / Google Play Console で4つの商品を登録
//  2. in_app_purchase パッケージで購入
//  3. Cloud Functions でレシート（購入証明）を検証し、サーバーが plan を書き換える
//  4. この画面は users/{自分} を監視しているので、plan が変われば自動で表示が変わる
//
// 💡 5万人規模：この画面が読むのは自分のドキュメント1件だけ（変化があったときだけ通知）
// ============================================================================

// ⚠️ 本物の課金を組み込んだら true にする
const bool _kPurchaseAvailable = false;

class _Feature {
  const _Feature(this.title, this.desc);
  final String title;
  final String desc;
}

class _Plan {
  const _Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.color,
    required this.features,
    this.isPopular = false,
  });
  final String id;
  final String name;
  final int price; // 税込・月額（円）
  final Color color;
  final List<_Feature> features;
  final bool isPopular;
}

// 💡 料金プラン（2026年11月25日改定）
//    サーバー側の判定（index.ts の TALK_LIMITS と LOCKED_PLANS）、
//    特商法表記・Frendyの説明・ヘルプと必ずそろえること
const List<_Plan> _plans = [
  _Plan(
    id: 'free',
    name: 'フリー',
    price: 0,
    color: Colors.grey,
    features: [_Feature('メッセージ最大5人／月', '最大5人の気になる相手と会話を始めることができます。')],
  ),
  _Plan(
    id: 'light',
    name: 'ライト',
    price: 250,
    color: Color(0xFFFF9800),
    features: [
      _Feature('メッセージ最大15人／月', '最大15人の気になる相手と会話を始めることができます。'),
      _Feature('足跡の表示', 'あなたのプロフィールを見た人がわかります。'),
      _Feature('いいねされた人を見れる', 'あなたにいいねしたお相手を確認できます。'),
    ],
  ),
  _Plan(
    id: 'standard',
    name: 'スタンダード',
    price: 480,
    color: Color(0xFF4CAF50),
    isPopular: true,
    features: [
      _Feature('メッセージ最大40人／月', '最大40人の気になる相手と会話を始めることができます。'),
      _Feature('足跡の表示', 'あなたのプロフィールを見た人がわかります。'),
      _Feature('いいねされた人を見れる', 'あなたにいいねしたお相手を確認できます。'),
    ],
  ),
  _Plan(
    id: 'premium',
    name: 'プレミアム',
    price: 980,
    color: AppColors.point,
    features: [
      _Feature('メッセージ無制限', '人数の上限なく、気になる相手と会話を始められます。'),
      _Feature('足跡の表示', 'あなたのプロフィールを見た人がわかります。'),
      _Feature('いいねされた人を見れる', 'あなたにいいねしたお相手を確認できます。'),
      _Feature('プロフィール優先表示', '「探す」の検索結果で、あなたのプロフィールが上位に表示されます。'),
    ],
  ),
];

int _indexOfPlan(String id) {
  final i = _plans.indexWhere((p) => p.id == id);
  return i >= 0 ? i : 0;
}

// 各ストアのサブスクリプション管理画面（解約・プラン変更はここで行う）
final Uri _kAppleSubscriptionsUrl = Uri.parse(
  'https://apps.apple.com/account/subscriptions',
);
final Uri _kGoogleSubscriptionsUrl = Uri.parse(
  'https://play.google.com/store/account/subscriptions',
);

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _planSub;

  int _selectedPlanIndex = 2;
  String _currentPlan = 'free';
  // 友達招待の無料体験中か（無料体験中は、ストアでの解約は不要）
  DateTime? _trialUntil;
  bool get _isTrial => _trialUntil != null;
  bool get _isPaid => _currentPlan != 'free' && !_isTrial;
  bool _isLoadingPlan = true;
  bool _initialSelectionDone = false;

  @override
  void initState() {
    super.initState();
    _listenPlan();
  }

  @override
  void dispose() {
    _planSub?.cancel();
    super.dispose();
  }

  // 💡 自分のプランを監視する。購入後にサーバーが plan を書き換えると、自動で表示が変わる
  void _listenPlan() {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _isLoadingPlan = false;
      return;
    }
    _planSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
          (snap) {
            final data = snap.data() ?? const <String, dynamic>{};
            final raw = data['plan'];
            String plan = raw is String && _plans.any((p) => p.id == raw)
                ? raw
                : 'free';

            // 💡 無料体験中かどうか。期限が過ぎていれば、体験前のプランとして表示する
            //    （サーバーが1時間ごとに元に戻すので、その間の表示をそろえる）
            DateTime? trialUntil;
            if (data['planSource'] == 'trial') {
              final expires = data['planExpiresAt'];
              final until = expires is Timestamp ? expires.toDate() : null;
              if (until != null && until.isAfter(DateTime.now())) {
                trialUntil = until;
              } else {
                final before = data['planBeforeTrial'];
                plan = before is String && _plans.any((p) => p.id == before)
                    ? before
                    : 'free';
              }
            }

            if (!mounted) return;
            setState(() {
              _currentPlan = plan;
              _trialUntil = trialUntil;
              _isLoadingPlan = false;
              // 最初の1回だけ、今のプランを選択状態にする
              if (!_initialSelectionDone) {
                _selectedPlanIndex = plan == 'free' ? 2 : _indexOfPlan(plan);
                _initialSelectionDone = true;
              }
            });
          },
          onError: (Object e) {
            debugPrint('プラン取得エラー: $e');
            if (mounted) setState(() => _isLoadingPlan = false);
          },
        );
  }

  // ストアのサブスクリプション管理画面を開く（解約・プラン変更）
  Future<void> _openStoreSubscriptions() async {
    final Uri url = Platform.isIOS
        ? _kAppleSubscriptionsUrl
        : _kGoogleSubscriptionsUrl;
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception('launchUrl returned false');
    } catch (e) {
      debugPrint('サブスクリプション管理画面の起動エラー: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isIOS
                ? '「設定」アプリ →「（あなたの名前）」→「サブスクリプション」から管理できます'
                : 'Google Play ストア →「お支払いと定期購入」→「定期購入」から管理できます',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onPlanButtonPressed(_Plan selected) {
    // 有料プランからフリーに戻す・別の有料プランに変える場合は、ストア側で行う
    // （無料体験中の人は、ストアでの手続きは不要）
    if (_isPaid) {
      _showStoreManageDialog(selected);
      return;
    }
    if (!_kPurchaseAvailable) {
      _showComingSoonDialog();
      return;
    }
    // TODO: 本物の課金を組み込んだら、ここで購入処理を呼ぶ
  }

  void _showComingSoonDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'ただいま準備中です',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          kDebugMode
              ? '有料プランの購入機能は準備中です。\n\n'
                    '【開発者向け】テストするときは、Firebase コンソールの users → 自分のID → plan を '
                    'light / standard / premium に書き換えてください。'
              : '有料プランの購入機能は、ただいま準備中です。\n公開まで今しばらくお待ちください。',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              '閉じる',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showStoreManageDialog(_Plan selected) {
    final String message = selected.id == 'free'
        ? 'フリープランに戻すには、${Platform.isIOS ? 'App Store' : 'Google Play'} のサブスクリプション管理画面で解約してください。\n解約後も、契約期間の終了までは今のプランをご利用いただけます。'
        : 'プランの変更は、${Platform.isIOS ? 'App Store' : 'Google Play'} のサブスクリプション管理画面から行えます。';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'サブスクリプションの管理',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _openStoreSubscriptions();
            },
            child: const Text(
              '管理画面を開く',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _planNameOf(String id) => _plans[_indexOfPlan(id)].name;

  @override
  Widget build(BuildContext context) {
    final _Plan selected = _plans[_selectedPlanIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'メンバーシッププラン',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoadingPlan
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'プランを選択',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        for (var i = 0; i < _plans.length; i++)
                          Expanded(child: _buildPlanCard(i)),
                      ],
                    ),

                    const SizedBox(height: 32),

                    Text(
                      '${selected.name}プランの機能',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final f in selected.features)
                      _buildFeatureItem(
                        Icons.check_circle,
                        f.title,
                        f.desc,
                        selected.color,
                      ),

                    const SizedBox(height: 24),
                    _buildStatusBox(),
                    const SizedBox(height: 24),
                    _buildActionButton(selected),

                    // 有料プランの人には、解約・変更の入り口を常に出しておく
                    if (_isPaid) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _openStoreSubscriptions,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('サブスクリプションを管理・解約する'),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // 💡 Appleガイドライン3.1.2・特商法対応：自動更新・解約方法を画面上に明記する
                    if (selected.id != 'free') _buildRenewalNotice(selected),

                    const SizedBox(height: 16),
                    // 💡 解約の手順は、プランに関係なく常に表示しておく
                    _buildCancelGuide(),

                    const SizedBox(height: 40),
                    _buildFooter(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPlanCard(int index) {
    final plan = _plans[index];
    final bool isSelected = _selectedPlanIndex == index;
    final bool isCurrent = plan.id == _currentPlan;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: GestureDetector(
        onTap: () => setState(() => _selectedPlanIndex = index),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
              width: double.infinity,
              height: 90,
              decoration: BoxDecoration(
                color: isSelected
                    ? plan.color.withValues(alpha: 0.04)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? plan.color : Colors.grey[300]!,
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: plan.color.withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      plan.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? plan.color : Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '¥${plan.price}',
                          style: const TextStyle(
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                        const Text(
                          '/月',
                          style: TextStyle(fontSize: 9, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (plan.isPopular || isCurrent)
              Positioned(
                top: -2,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isCurrent ? Colors.black87 : plan.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isCurrent ? '利用中' : '人気',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '現在のステータス:',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          Flexible(
            child: Text(
              _isTrial
                  ? '${_planNameOf(_currentPlan)}プラン無料体験中\n（${_trialUntil!.month}月${_trialUntil!.day}日まで）'
                  : _currentPlan == 'free'
                  ? 'フリー会員'
                  : '${_planNameOf(_currentPlan)}プラン契約中',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(_Plan selected) {
    final bool isCurrent = selected.id == _currentPlan;

    final String label;
    if (isCurrent) {
      label = _isTrial ? '無料体験中です' : '現在のプランです';
    } else if (_isPaid) {
      label = selected.id == 'free'
          ? 'フリープランに戻す（解約）'
          : '${selected.name}プランに変更する';
    } else {
      label = '${selected.name}プランにする';
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isCurrent ? null : () => _onPlanButtonPressed(selected),
        style: ElevatedButton.styleFrom(
          backgroundColor: selected.id == 'free'
              ? Colors.grey[600]
              : selected.color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[400],
          disabledForegroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRenewalNotice(_Plan selected) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${selected.name}プランは月額¥${selected.price}（税込）の自動更新サブスクリプションです。'
              '契約期間は1ヶ月で、期間終了の24時間前までに解約しない限り、自動的に更新され、更新料が請求されます。'
              '解約は、ご利用の端末のApp StoreまたはGoogle Playのサブスクリプション管理画面からいつでも行えます。'
              'アプリの削除や退会だけでは解約されません。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 解約方法の案内（iPhone と Android の両方の手順を載せる）
  Widget _buildCancelGuide() {
    Widget steps(String title, List<String> items) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < items.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${i + 1}. ${items[i]}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Colors.grey[800],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final iphone = steps('iPhone の場合', const [
      '「設定」アプリを開く',
      'いちばん上の「自分の名前」をタップ',
      '「サブスクリプション」をタップ',
      '「frendy」を選び、「サブスクリプションをキャンセルする」をタップ',
    ]);
    final android = steps('Android の場合', const [
      '「Google Play ストア」アプリを開く',
      '右上のプロフィールアイコンをタップ',
      '「お支払いと定期購入」→「定期購入」をタップ',
      '「frendy」を選び、「定期購入を解約」をタップ',
    ]);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, size: 18, color: Colors.blueGrey),
              SizedBox(width: 8),
              Text(
                '解約の方法',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'サブスクリプションは、アプリ内からは解約できません。ご利用の端末で、次の手順で解約してください。'
            'アプリの削除や退会だけでは解約されませんのでご注意ください。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Colors.grey[800],
            ),
          ),
          // 使っている端末の手順を先に表示する
          if (Platform.isIOS) ...[iphone, android] else ...[android, iphone],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openStoreSubscriptions,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(
                Platform.isIOS ? 'App Store の管理画面を開く' : 'Google Play の管理画面を開く',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        _buildFooterLink('利用規約', const TermsOfServiceScreen()),
        _buildFooterDivider(),
        _buildFooterLink('プライバシーポリシー', const PrivacyPolicyScreen()),
        _buildFooterDivider(),
        _buildFooterLink('特商法表記', const TokushohoScreen()),
      ],
    );
  }

  Widget _buildFeatureItem(
    IconData icon,
    String title,
    String description,
    Color themeColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: themeColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterLink(String text, Widget screen) {
    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => screen)),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.grey,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildFooterDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: Text('|', style: TextStyle(fontSize: 11, color: Colors.grey)),
    );
  }
}
