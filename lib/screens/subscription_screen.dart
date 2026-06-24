import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // 💡 デフォルト選択を「スタンダード」（インデックス: 1）に変更
  int _selectedPlanIndex = 1;

  @override
  Widget build(BuildContext context) {
    const String currentPlan = 'free';

    // 💡 プラン名を修正＆人気プランをスタンダードに設定
    final List<Map<String, dynamic>> plans = [
      {
        'id': 'light',
        'name': 'ライト',
        'price': '250',
        'features': [
          {'title': 'メッセージ最大8人まで', 'desc': '最大8人の気になる相手と会話を始めることができます。'},
        ],
        'color': const Color(0xFFFF9800), // オレンジ
      },
      {
        'id': 'standard',
        'name': 'スタンダード',
        'price': '480',
        'features': [
          {'title': 'メッセージ無制限', 'desc': '気になる相手といつでも会話できます。'},
          {'title': '足跡の表示', 'desc': 'あなたのプロフィールを見た人がわかります。'},
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
          {'title': 'プロフィール優先表示', 'desc': '相手の検索結果で上位に表示されます。'},
          {'title': 'いいね数の表示', 'desc': 'お相手がもらった累計いいね数がわかります。'},
        ],
        'color': AppColors.point,
      },
      {
        'id': 'max',
        'name': 'マックス',
        'price': '1,480',
        'features': [
          {'title': 'スタンダード・プレミアムの全機能', 'desc': 'メッセージ無制限、足跡、いいね数表示など'},
          {'title': '特定のユーザーに優先表示', 'desc': 'あなたが気になる属性のユーザーへ集中的にアプローチ。'},
          {'title': '特別オファー機能', 'desc': '通常とは違う特別なアピールでマッチ率を劇的に高めます。'},
        ],
        'color': const Color(0xFF673AB7), // パープル
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
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('復元', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
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
                      padding: const EdgeInsets.symmetric(horizontal: 3.0),
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
                                          color: planColor.withOpacity(0.1),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
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
                                      textBaseline: TextBaseline.alphabetic,
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
                                      borderRadius: BorderRadius.circular(6),
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

              ...(plans[_selectedPlanIndex]['features'] as List).map((feat) {
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
                      style: TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    Text(
                      currentPlan == 'free' ? 'フリー会員' : '有料プラン契約中',
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
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: plans[_selectedPlanIndex]['color'],
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: Text(
                    '${plans[_selectedPlanIndex]['name']}プランに登録する',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
