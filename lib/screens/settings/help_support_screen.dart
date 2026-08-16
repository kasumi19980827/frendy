import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:matching_app/constants/app_colors.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  // 💡 お問い合わせ先メールアドレス（実際の窓口アドレスに差し替えてください）
  static const String _supportEmail = 'support@frendy-app.jp';

  // 💡 よくある質問データ
  //    カテゴリごとにグルーピングし、上から順に表示
  static const List<Map<String, dynamic>> _faqSections = [
    {
      'category': 'アカウント・登録について',
      'items': [
        {
          'question': '年齢確認・本人確認はなぜ必要ですか？',
          'answer':
              '安心してご利用いただくため、frendyでは年齢確認・本人確認を必須としています。'
              '確認が完了するまでは、一部の機能（トークの開始など）がご利用いただけない場合があります。'
              'マイページの「年齢確認・本人確認」から、いつでも手続きを行うことができます。',
        },
        {
          'question': '登録したメールアドレスを変更したい',
          'answer':
              '現在、アプリ内からのメールアドレス変更には対応しておりません。'
              'お手数をおかけしますが、お問い合わせ窓口より、登録済みのIDと変更後のメールアドレスを添えてご連絡ください。',
        },
        {
          'question': '退会するとデータはどうなりますか？',
          'answer':
              'マイページの「退会する」から手続きいただくと、プロフィール・トーク履歴・写真を含むすべてのデータが完全に削除され、復元することはできません。'
              '一時的に利用を控えたいだけの場合は、退会ではなくログアウトをご利用ください。',
        },
      ],
    },
    {
      'category': 'プロフィール・検索について',
      'items': [
        {
          'question': '「おすすめ」タブに誰も表示されません',
          'answer':
              '「おすすめ」タブは、あなたが登録した趣味・好きなものと共通点があるユーザーを表示する機能です。'
              'プロフィールの趣味・好きなもの欄が未入力の場合や、共通の趣味を持つユーザーが見つからない場合は「ユーザー」タブに自動的に切り替わります。'
              'プロフィール編集画面から趣味・好きなものを詳しく入力していただくと、精度が上がります。',
        },
        {
          'question': '検索結果に自分のプロフィールが表示されない',
          'answer':
              '名前・年齢・自己紹介文・プロフィール写真がすべて入力されていないプロフィールは、検索結果や一覧画面には表示されない仕様になっています。'
              'マイページの「プロフィール編集」から、未入力の項目がないかご確認ください。',
        },
      ],
    },
    {
      'category': 'メッセージ・トークについて',
      'items': [
        {
          'question': '「今月のトーク開始上限です」と表示されて話しかけられません',
          'answer':
              'ご利用中のプランにより、新しく話しかけられる人数には月ごとの上限があります（フリープラン: 5人／月、ライトプラン: 15人／月）。'
              'すでにトーク履歴がある相手には、上限に関係なくいつでもメッセージを送ることができます。'
              '上限を増やしたい場合は、マイページの「サブスクリプション管理」から上位プランをご確認ください。',
        },
        {
          'question': '送ったメッセージを取り消したい',
          'answer':
              '現在、送信済みメッセージの削除・編集機能はご用意しておりません。'
              '送信前に内容をよくご確認いただくようお願いいたします。',
        },
      ],
    },
    {
      'category': '安全・トラブルについて',
      'items': [
        {
          'question': '迷惑なユーザーをブロック・通報したい',
          'answer':
              '相手のプロフィール画面から通報およびブロックが行えます。'
              'ブロックすると、お互いの検索結果や一覧画面に表示されなくなり、メッセージのやり取りもできなくなります。'
              'ブロックしたユーザーは、マイページの「アプリ設定」内「ブロック中のユーザー」からいつでも確認・解除ができます。',
        },
        {
          'question': '不審なメッセージを受け取りました',
          'answer':
              '個人情報の要求や金銭のやり取りを持ちかけるメッセージには十分ご注意ください。'
              '該当のユーザーは速やかに通報・ブロックのうえ、お問い合わせ窓口までスクリーンショットを添えてご連絡ください。'
              '運営事務局にて内容を確認し、必要に応じて利用制限などの対応を行います。',
        },
      ],
    },
    {
      'category': '料金・お支払いについて',
      'items': [
        {
          'question': 'サブスクリプションを解約したい',
          'answer':
              'サブスクリプションの解約は、ご利用の端末のOS設定（App StoreまたはGoogle Playのサブスクリプション管理画面）から行ってください。'
              'アプリ内の「サブスクリプション管理」からも設定画面へのご案内を確認できます。',
        },
        {
          'question': '課金したのにプランが反映されません',
          'answer':
              '決済処理からアプリへの反映まで、まれに数分ほどお時間をいただく場合がございます。'
              'アプリの再起動後もプランが反映されない場合は、購入日時・購入した端末の種類（iOS / Android）を添えて、お問い合わせ窓口までご連絡ください。',
        },
      ],
    },
  ];

  // 💡 メールアプリを起動してお問い合わせ用の宛先・件名をあらかじめ入力しておく
  Future<void> _launchSupportEmail(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: 'subject=${Uri.encodeComponent('【frendy】お問い合わせ')}',
    );

    try {
      final bool launched = await launchUrl(emailUri);
      if (!launched && context.mounted) {
        _showEmailFallbackDialog(context);
      }
    } catch (e) {
      if (context.mounted) {
        _showEmailFallbackDialog(context);
      }
    }
  }

  // メールアプリが起動できない端末向けに、アドレスを直接案内するフォールバック
  void _showEmailFallbackDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'メールアプリを起動できませんでした',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: const SelectableText(
          '下記のメールアドレスまでお問い合わせ内容をお送りください。\n\n$_supportEmail',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '閉じる',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'ヘルプ・お問い合わせ',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 8),

          // --- お問い合わせボタン（最上部に配置） ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.point.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'お困りのことはありますか？',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'よくある質問で解決しない場合は、お気軽にお問い合わせください。',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _launchSupportEmail(context),
                      icon: const Icon(Icons.mail_outline, color: Colors.white),
                      label: const Text(
                        'お問い合わせフォームへ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.point,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // --- よくある質問セクション ---
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'よくある質問',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),

          ..._faqSections.map((section) => _buildFaqSection(context, section)),
        ],
      ),
    );
  }

  // カテゴリ単位でFAQをまとめて表示するウィジェット
  Widget _buildFaqSection(BuildContext context, Map<String, dynamic> section) {
    final String category = section['category'] as String;
    final List<Map<String, String>> items = (section['items'] as List)
        .cast<Map<String, String>>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            category,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.point,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.gley,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Theme(
              // ExpansionTile展開時のデフォルト区切り線を消し、独自のDividerで制御する
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final bool isLast = index == items.length - 1;

                  return Column(
                    children: [
                      ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        title: Text(
                          item['question'] ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        iconColor: AppColors.point,
                        collapsedIconColor: Colors.grey,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              item['answer'] ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!isLast)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: Colors.grey[300],
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
