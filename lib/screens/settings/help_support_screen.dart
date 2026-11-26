import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';

// ============================================================================
// ヘルプ・お問い合わせ
//
// 💡 この画面は文章の表示とメールアプリの起動だけで、Firestore を読み書きしない。
//    そのため、ユーザー数が増えてもサーバーの負担は増えない。
//
// 💡 よくある質問は、アプリの実際の動きと必ずそろえること。
//    （トーク上限・プラン内容・退会時の削除範囲などを変えたら、ここも直す）
// ============================================================================

// お問い合わせ先メールアドレス
// 💡 リリース前に、独自ドメインのアドレス（例：support@frendy.jp）にすると信頼感が上がる
const String _kSupportEmail = 'frendy.support@gmail.com';

class _Faq {
  const _Faq(this.question, this.answer);
  final String question;
  final String answer;
}

class _FaqSection {
  const _FaqSection(this.category, this.items);
  final String category;
  final List<_Faq> items;
}

const List<_FaqSection> _faqSections = [
  _FaqSection('アカウント・登録について', [
    _Faq(
      'frendyはどんなアプリですか？恋人探しにも使えますか？',
      'frendyは、趣味や価値観の合う「友達」を作るためのアプリです。'
          '恋愛・交際相手や結婚相手を探すことを目的としたサービスではありません。'
          '恋人募集・交際希望・婚活などの恋愛目的の投稿や勧誘は利用規約で禁止しており、'
          '見つけた場合は投稿の削除や利用停止などの対応を行います。',
    ),
    _Faq(
      '年齢確認・本人確認はなぜ必要ですか？',
      '安心してご利用いただくため、frendyでは年齢確認・本人確認を必須としています。'
          '確認が完了するまでは、トークの閲覧・送信がご利用いただけません。'
          'マイページの「年齢確認・本人確認」から、いつでも手続きを行うことができます。',
    ),
    _Faq(
      '年齢確認の結果はいつわかりますか？',
      '通常、提出から数分〜24時間以内に運営事務局で確認いたします。'
          '確認が完了すると、トークがご利用いただけるようになります。'
          '書類の文字が読み取れない場合などは非承認となることがあります。その際は理由をご確認のうえ、再提出をお願いいたします。',
    ),
    _Faq(
      '提出した身分証は他の人に見られますか？',
      '提出いただいた身分証は、年齢確認のために運営事務局だけが確認します。'
          '他のユーザーに公開されることはありません。',
    ),
    _Faq(
      '登録したメールアドレスを変更したい',
      '現在、アプリ内からのメールアドレス変更には対応しておりません。'
          'お手数をおかけしますが、下記のお問い合わせ窓口より、登録済みのIDと変更後のメールアドレスを添えてご連絡ください。',
    ),
    _Faq(
      '退会するとデータはどうなりますか？',
      'マイページの「退会する」から手続きいただくと、プロフィール・写真・提出済みの本人確認書類・トーク履歴・友達やいいねの情報を含む、ご自身のデータが削除され、復元することはできません。'
          'トーク履歴はお相手の画面からも削除されます。'
          'なお、利用規約違反への対応のため、通報の記録は一定期間保管する場合があります。'
          '一時的に利用を控えたいだけの場合は、退会ではなくログアウトをご利用ください。',
    ),
  ]),
  _FaqSection('プロフィール・検索について', [
    _Faq(
      '「おすすめ」タブに誰も表示されません',
      '「おすすめ」タブは、あなたが登録した「好きなこと（趣味）」「最近特にハマってること」と共通点があるユーザーを表示する機能です。'
          'これらが未入力の場合や、共通点のあるユーザーが見つからない場合は「ユーザー」タブに自動的に切り替わります。'
          'プロフィール編集画面から、好きなことを「、」で区切って詳しく入力していただくと、見つかりやすくなります。',
    ),
    _Faq(
      '検索結果に自分のプロフィールが表示されない',
      '名前・年齢・プロフィール写真・「好きなこと（趣味）」のいずれかが未入力のプロフィールは、検索結果には表示されない仕様になっています。'
          'マイページの「プロフィール編集」から、未入力の項目がないかご確認ください。',
    ),
    _Faq('IDで相手を検索したい', '「探す」の検索欄に、相手のプロフィールに表示されている英数字のIDを入力すると検索できます。'),
  ]),
  _FaqSection('メッセージ・トークについて', [
    _Faq(
      '「今月のトーク開始上限です」と表示されて話しかけられません',
      'ご利用中のプランにより、新しく話しかけられる人数には月ごとの上限があります（フリープラン: 5人／月、ライトプラン: 15人／月、スタンダードプラン: 40人／月、プレミアムプラン: 上限なし）。'
          'すでにトーク履歴がある相手には、上限に関係なくいつでもメッセージを送ることができます。'
          '上限を増やしたい場合は、マイページの「サブスクリプション管理」から上位プランをご確認ください。',
    ),
    _Faq(
      '友達申請ができません',
      '友達申請は、お互いに4通以上メッセージをやり取りすると、トーク一覧に「友達申請」ボタンが表示されて送れるようになります。'
          '相手が承認すると友達になれます。',
    ),
    _Faq(
      '送ったメッセージを取り消したい',
      '現在、送信済みメッセージの削除・編集機能はご用意しておりません。'
          '送信前に内容をよくご確認いただくようお願いいたします。',
    ),
  ]),
  _FaqSection('安全・トラブルについて', [
    _Faq(
      '恋愛目的・出会い目的のユーザーがいました',
      'frendyでは恋愛・交際目的の募集、出会い目的やパパ活などの勧誘を禁止しています。'
          '相手のプロフィール画面、またはトーク画面の「︙」から「通報」を選び、'
          '理由に「恋愛・交際目的の募集」を選んで送信してください。'
          '運営事務局で内容を確認し、投稿の削除・警告・利用停止などの対応を行います。'
          '通報したことが相手に知られることはありません。',
    ),
    _Faq(
      '迷惑なユーザーをブロック・通報したい',
      '相手のプロフィール画面、またはトーク一覧の「︙」から通報およびブロックが行えます。'
          'ブロックすると、お互いの検索結果や一覧画面に表示されなくなり、メッセージのやり取りもできなくなります。'
          'ブロックしたユーザーは、マイページの「アプリ設定」内「ブロック中のユーザー」からいつでも確認・解除ができます。',
    ),
    _Faq(
      '不審なメッセージを受け取りました',
      '個人情報の要求や金銭のやり取りを持ちかけるメッセージには十分ご注意ください。'
          '該当のユーザーは速やかに通報・ブロックのうえ、下記のお問い合わせ窓口までスクリーンショットを添えてご連絡ください。'
          '運営事務局にて内容を確認し、必要に応じて利用制限などの対応を行います。',
    ),
  ]),
  _FaqSection('料金・お支払いについて', [
    _Faq(
      '各プランの違いを教えてください',
      'フリープラン（無料）: 新しい相手とのトーク開始は月5人まで。足跡・いいねをくれた相手はモザイク表示です。\n'
          '※ 新しく登録した方は、登録から1ヶ月間ライトプランを無料でお使いいただけます（自動でフリープランに戻り、料金はかかりません）。\n'
          'ライトプラン（月額250円）: トーク開始が月15人まで。足跡・いいねをくれた相手を確認できます。\n'
          'スタンダードプラン（月額480円）: ライトプランの内容に加えて、トーク開始が月40人まで。\n'
          'プレミアムプラン（月額980円）: トーク開始の上限なし。さらに、検索結果であなたのプロフィールが上位に表示されます。\n'
          '料金はすべて税込です。',
    ),
    _Faq(
      'サブスクリプションを解約したい',
      'サブスクリプションは、アプリ内からは解約できません。ご利用の端末で、次の手順で解約してください。\n\n'
          '【iPhone の場合】\n'
          '1. 「設定」アプリを開く\n'
          '2. いちばん上の「自分の名前」をタップ\n'
          '3. 「サブスクリプション」をタップ\n'
          '4. 「frendy」を選び、「サブスクリプションをキャンセルする」をタップ\n\n'
          '【Android の場合】\n'
          '1. 「Google Play ストア」アプリを開く\n'
          '2. 右上のプロフィールアイコンをタップ\n'
          '3. 「お支払いと定期購入」→「定期購入」をタップ\n'
          '4. 「frendy」を選び、「定期購入を解約」をタップ\n\n'
          '解約後も、契約期間の終了までは有料プランをご利用いただけます。'
          'アプリの削除や退会だけでは解約されませんのでご注意ください。'
          'マイページの「サブスクリプション管理」からも、各ストアの管理画面を開くことができます。',
    ),
    _Faq(
      '課金したのにプランが反映されません',
      '決済処理からアプリへの反映まで、まれに数分ほどお時間をいただく場合がございます。'
          'アプリの再起動後もプランが反映されない場合は、購入日時・購入した端末の種類（iOS / Android）を添えて、下記のお問い合わせ窓口までご連絡ください。',
    ),
  ]),
];

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  // 💡 メールアプリを起動し、宛先・件名・本文の下書きを入れておく。
  //    ユーザーIDと端末の種類を入れておくと、運営が調べるときに何度も聞き返さずに済む
  Future<void> _launchSupportEmail(BuildContext context) async {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '未ログイン';
    final String os = Platform.isIOS
        ? 'iOS'
        : (Platform.isAndroid ? 'Android' : 'その他');

    final String body =
        '''
お問い合わせ内容をこちらにご記入ください。



--------------------
※ 以下は調査のための情報です。消さずにお送りください。
ユーザーID: $uid
端末: $os
''';

    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: _kSupportEmail,
      query:
          'subject=${Uri.encodeComponent('【frendy】お問い合わせ')}'
          '&body=${Uri.encodeComponent(body)}',
    );

    try {
      final bool launched = await launchUrl(emailUri);
      if (!launched && context.mounted) _showEmailFallbackDialog(context, uid);
    } catch (e) {
      debugPrint('メールアプリ起動エラー: $e');
      if (context.mounted) _showEmailFallbackDialog(context, uid);
    }
  }

  // メールアプリが起動できない端末向けに、アドレスを直接案内する
  void _showEmailFallbackDialog(BuildContext context, String uid) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'メールアプリを起動できませんでした',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SelectableText(
          '下記のメールアドレスまで、お問い合わせ内容とユーザーIDをお送りください。\n\n'
          '$_kSupportEmail\n\n'
          'ユーザーID: $uid',
          style: const TextStyle(fontSize: 14, height: 1.5),
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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const SizedBox(height: 8),

            // --- お問い合わせボタン（最上部に配置） ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.point.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'お困りのことはありますか？',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
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
                        icon: const Icon(
                          Icons.mail_outline,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'メールでお問い合わせ',
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

            // --- よくある質問 ---
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

            for (final section in _faqSections)
              _buildFaqSection(context, section),
          ],
        ),
      ),
    );
  }

  // カテゴリ単位でFAQをまとめて表示する
  Widget _buildFaqSection(BuildContext context, _FaqSection section) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.category,
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
                children: [
                  for (var i = 0; i < section.items.length; i++) ...[
                    ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      title: Text(
                        section.items[i].question,
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
                            section.items[i].answer,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.6,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (i != section.items.length - 1)
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.grey[300],
                        indent: 16,
                        endIndent: 16,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
