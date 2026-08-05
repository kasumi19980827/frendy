import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:matching_app/constants/app_colors.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // 💡 デフォルト選択を「スタンダード」（インデックス: 2）に変更
  int _selectedPlanIndex = 2;

  // 💡 プラン一覧のid順（Firestoreの現在プランとインデックスを対応させるため）
  final List<String> _planIds = ['free', 'light', 'standard', 'premium'];

  String _currentPlan = 'free'; // Firestoreに保存されている現在のプラン
  bool _isLoadingPlan = true;
  bool _isUpdatingPlan = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPlan();
  }

  // 💡 現在のプランをFirestoreから取得
  Future<void> _loadCurrentPlan() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoadingPlan = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
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

  // 💡 選択中のプランをFirestoreに書き込み、実際にプランを変更する
  Future<void> _updatePlan(String newPlanId, String newPlanName) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isUpdatingPlan = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'plan': newPlanId,
      });
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
    // 💡 フリープランを追加し、各プランの内容・価格を修正
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
        'color': const Color(0xFFFF9800), // オレンジ
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
        'color': const Color(0xFF4CAF50), // グリーン
        'isPopular': true, // 🔥 人気バッジをスタンダードに設定
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

                    // --- 選択中のプランの特典内容一覧 ---
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

                    // --- 現在のプラン表示 ---
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

                    const SizedBox(height: 32),

                    // --- アクションボタン ---
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

                    const SizedBox(height: 40),

                    // --- ストア審査対策：各種規約リンク ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildFooterLink('利用規約', () {}),
                        _buildFooterDivider(),
                        _buildFooterLink('プライバシーポリシー', () {}),
                        _buildFooterDivider(),
                        _buildFooterLink('特商法表記', () {}),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
    );
  }

  // 💡 planIdからプラン名を取得するヘルパー
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
