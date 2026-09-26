import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/settings/privacy_policy_screen.dart';
import 'package:matching_app/screens/settings/terms_of_service_screen.dart';
import 'package:matching_app/screens/settings/tokushoho_screen.dart';

// ============================================================
// 🔴🔴🔴 重要な警告（本番リリース前に必ず対応すること） 🔴🔴🔴
// ------------------------------------------------------------
// このファイルの _updatePlan() は、実際の決済（Apple In-App Purchase /
// Google Play Billing）を一切経由せず、Firestoreの 'plan' フィールドを
// 直接書き換えているだけです。
//
// つまり現状は「ボタンを押すだけで、お金を払わずに誰でもプレミアムプランに
// なれてしまう」状態であり、収益化の仕組みとして機能していません。
//
// 本番リリース前に、最低限以下の対応が必要です：
//   1. `in_app_purchase` パッケージを導入し、App Store Connect /
//      Google Play Console で実際のサブスクリプション商品を登録する
//   2. 購入完了後、Cloud Functions等のサーバー側でレシート（購入証明）を
//      検証してから、'plan' フィールドを更新する
//      （クライアントから直接 'plan' を書き換えられる今のFirestoreルールも
//        あわせて見直し、クライアントからの直接書き込みは禁止すべき）
//   3. 上記が完了するまでは、このプラン変更ボタンは「テスト用」の
//      仮実装であることを明確に認識しておくこと
// ============================================================

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  static const Duration _networkTimeout = Duration(seconds: 20);

  int _selectedPlanIndex = 2;
  final List<String> _planIds = ['free', 'light', 'standard', 'premium'];

  String _currentPlan = 'free';
  bool _isLoadingPlan = true;
  bool _isUpdatingPlan = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  Future<void> _loadCurrentPlan() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingPlan = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_networkTimeout);
      final String plan = doc.data()?['plan'] ?? 'free';
      if (mounted) {
        setState(() {
          _currentPlan = plan;
          final int idx = _planIds.indexOf(plan);
          _selectedPlanIndex = idx >= 0 ? idx : 0;
          _isLoadingPlan = false;
        });
      }
    } catch (e) {
      debugPrint('プラン取得エラー: $e');
      if (mounted) setState(() => _isLoadingPlan = false);
    }
  }

  Future<void> _updatePlan(String newPlanId, String newPlanName) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isUpdatingPlan = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'plan': newPlanId})
          .timeout(_networkTimeout);
      if (mounted) {
        setState(() {
          _currentPlan = newPlanId;
          _isUpdatingPlan = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$newPlanNameプランに変更しました'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('プラン更新エラー: $e');
      if (mounted) {
        setState(() => _isUpdatingPlan = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('プランの変更に失敗しました。もう一度お試しください。'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> plans = [
      {
        'id': 'free',
        'name': 'フリー',
        'price': '0',
        'features': [
          {'title': 'メッセージ最大5人／月', 'desc': '最大5人の気になる相手と会話を始めることができます。'},
        ],
        'color': Colors.grey,
      },
      {
        'id': 'light',
        'name': 'ライト',
        'price': '250',
        'features': [
          {'title': 'メッセージ最大15人／月', 'desc': '最大15人の気になる相手と会話を始めることができます。'},
          {'title': '足跡の表示', 'desc': 'あなたのプロフィールを見た人がわかります。'},
        ],
        'color': const Color(0xFFFF9800),
      },
      {
        'id': 'standard',
        'name': 'スタンダード',
        'price': '500',
        'features': [
          {'title': 'メッセージ無制限', 'desc': '気になる相手といつでも会話できます。'},
          {'title': '足跡の表示', 'desc': 'あなたのプロフィールを見た人がわかります。'},
          {'title': 'いいねされた人を見れる', 'desc': 'あなたにいいねしたお相手を確認できます。'},
        ],
        'color': const Color(0xFF4CAF50),
        'isPopular': true,
      },
      {
        'id': 'premium',
        'name': 'プレミアム',
        'price': '980',
        'features': [
          {'title': 'メッセージ無制限', 'desc': '気になる相手といつでも会話できます。'},
          {'title': '足跡の表示', 'desc': 'あなたのプロフィールを見た人がわかります。'},
          {'title': 'いいねされた人を見れる', 'desc': 'あなたにいいねしたお相手を確認できます。'},
          {'title': 'プロフィール優先表示', 'desc': '相手の検索結果で上位に表示されます。'},
        ],
        'color': AppColors.point,
      },
    ];

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
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 16.0,
                ),
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(plans.length, (index) {
                        final plan = plans[index];
                        final bool isSelected = _selectedPlanIndex == index;
                        final Color planColor = plan['color'] as Color;

                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3.0,
                            ),
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedPlanIndex = index;
                                });
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 10),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                      horizontal: 2,
                                    ),
                                    width: double.infinity,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? planColor.withOpacity(0.04)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? planColor
                                            : Colors.grey[300]!,
                                        width: isSelected ? 2.5 : 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: planColor.withOpacity(
                                                  0.1,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 3),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          plan['name'],
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected
                                                ? planColor
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.baseline,
                                            textBaseline:
                                                TextBaseline.alphabetic,
                                            children: [
                                              Text(
                                                '¥${plan['price']}',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const Text(
                                                '/月',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (plan['isPopular'] == true)
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
                                            color: planColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: const Text(
                                            '人気',
                                            style: TextStyle(
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
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 32),

                    Text(
                      '${plans[_selectedPlanIndex]['name']}プランの機能',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),

                    ...(plans[_selectedPlanIndex]['features'] as List).map((
                      feat,
                    ) {
                      return _buildFeatureItem(
                        Icons.check_circle,
                        feat['title'],
                        feat['desc'],
                        plans[_selectedPlanIndex]['color'],
                      );
                    }),

                    const SizedBox(height: 24),

                    Container(
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
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
                          ),
                          Text(
                            _currentPlan == 'free'
                                ? 'フリー会員'
                                : '${_planNameOf(plans, _currentPlan)}プラン契約中',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- アクションボタン（注意書きより先に、目立つ位置に配置） ---
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: Builder(
                        builder: (context) {
                          final String selectedId =
                              plans[_selectedPlanIndex]['id'] as String;
                          final String selectedName =
                              plans[_selectedPlanIndex]['name'] as String;
                          final bool isCurrent = selectedId == _currentPlan;

                          return ElevatedButton(
                            onPressed: (_isUpdatingPlan || isCurrent)
                                ? null
                                : () => _updatePlan(selectedId, selectedName),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCurrent
                                  ? Colors.grey[400]
                                  : plans[_selectedPlanIndex]['color'],
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            child: _isUpdatingPlan
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    isCurrent
                                        ? '現在のプランです'
                                        : (selectedId == 'free'
                                              ? 'フリープランを利用する'
                                              : '$selectedNameプランに変更する'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 💡 Appleガイドライン3.1.2対応：サブスクリプションの自動更新・
                    //    解約方法について、画面上に明記する（フッターのリンクだけに頼らない）
                    if (plans[_selectedPlanIndex]['id'] != 'free')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: Colors.blueGrey,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${plans[_selectedPlanIndex]['name']}プランは月額¥${plans[_selectedPlanIndex]['price']}（税込）の自動更新サブスクリプションです。'
                                '契約期間は1ヶ月で、期間終了の24時間前までに解約しない限り、自動的に更新され、更新料が請求されます。'
                                '解約は、ご利用の端末のApp StoreまたはGoogle Playのサブスクリプション管理画面からいつでも行えます。',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 40),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFooterLink('利用規約', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const TermsOfServiceScreen(),
                            ),
                          );
                        }),
                        _buildFooterDivider(),
                        _buildFooterLink('プライバシーポリシー', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const PrivacyPolicyScreen(),
                            ),
                          );
                        }),
                        _buildFooterDivider(),
                        _buildFooterLink('特商法表記', () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const TokushohoScreen(),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  String _planNameOf(List<Map<String, dynamic>> plans, String planId) {
    final match = plans.firstWhere(
      (p) => p['id'] == planId,
      orElse: () => {'name': '不明'},
    );
    return match['name'] as String;
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

  Widget _buildFooterLink(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
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
