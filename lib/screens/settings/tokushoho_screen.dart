import 'package:flutter/material.dart';

// ============================================================================
// 特定商取引法に基づく表記
//
// 💡 日本国内でサブスクリプション等の有料サービスを提供する場合、
//    この表示は法律（特定商取引法11条）で義務付けられている。
//
// 💡 氏名・住所・電話番号は「請求があれば遅滞なく開示する」形にしている。
//    この形にする場合は、請求が来たらすぐに回答できるようにしておくこと。
//    〔住所〕は実際の住所に書き換える（住所は表示しても、開示請求の形でもよい）。
//
// 💡 料金を変えたときは、ここ・メンバーシッププラン画面・Frendyの説明・
//    ヘルプのよくある質問・各ストアの商品設定をすべてそろえること。
//
// ⚠️ この内容はたたき台です。リリース前に専門家に一度確認してもらってください。
// ============================================================================

// お問い合わせ用メールアドレス（ヘルプ画面と同じものにする）
const String _kSupportEmail = 'frendy.support@gmail.com';

class _TokushohoItem {
  const _TokushohoItem(this.label, this.value);
  final String label;
  final String value;
}

const List<_TokushohoItem> _items = [
  _TokushohoItem('販売事業者', 'frendy運営事務局\n※ 事業者の氏名は、請求があれば遅滞なく開示します。'),
  _TokushohoItem('運営統括責任者', '請求があれば遅滞なく開示します。'),
  _TokushohoItem('所在地', '愛知県蒲郡市'),
  _TokushohoItem(
    '電話番号',
    '請求があれば遅滞なく開示します。\nお問い合わせは、下記のメールアドレスまたはアプリ内「ヘルプ・お問い合わせ」よりお願いいたします。',
  ),
  _TokushohoItem('メールアドレス', _kSupportEmail),
  _TokushohoItem(
    '販売価格（すべて税込）',
    'ライトプラン：月額250円\n'
        'スタンダードプラン：月額480円\n'
        'プレミアムプラン：月額980円\n'
        '※ 各ストアの表示価格が優先されます。',
  ),
  _TokushohoItem('販売価格以外の必要料金', 'インターネット接続にかかる通信料はお客様のご負担となります。'),
  _TokushohoItem(
    'お支払い方法',
    'App StoreまたはGoogle Playを通じたお支払い（クレジットカード、キャリア決済等、各ストアが対応する方法）',
  ),
  _TokushohoItem('お支払い時期', 'サブスクリプション契約時、および契約が自動更新されるたびに、ご利用の決済方法へ課金されます。'),
  _TokushohoItem(
    '契約期間・自動更新',
    '契約期間は1か月です。契約期間の終了の24時間前までに解約しない限り、同じ内容で自動的に更新されます。',
  ),
  _TokushohoItem('サービス提供時期', 'お支払い手続き完了後、直ちにご利用いただけます。'),
  _TokushohoItem(
    '解約について',
    'サブスクリプションの解約は、ご利用の端末のApp StoreまたはGoogle Playのサブスクリプション管理画面からいつでも行うことができます。'
        '解約した場合も、契約期間の終了までは有料プランをご利用いただけます。\n'
        'アプリの削除や退会だけでは解約されませんのでご注意ください。',
  ),
  _TokushohoItem(
    '返品・返金について',
    '本サービスはデジタルコンテンツのため、提供開始後の返品・返金には応じられません。'
        'ただし、法令に定めがある場合はこの限りではありません。'
        'App Store／Google Playでのご購入の返金の可否は、Apple社またはGoogle社の定めるところによります。',
  ),
  _TokushohoItem('動作環境', 'iOS／Androidの対応バージョンについては、各アプリストアの掲載ページをご確認ください。'),
];

class TokushohoScreen extends StatelessWidget {
  const TokushohoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '特定商取引法に基づく表記',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const Divider(height: 32),
          itemBuilder: (context, index) {
            final item = _items[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                // 💡 長押しでコピーできるようにする（メールアドレスなどを写しやすくする）
                SelectableText(
                  item.value,
                  style: const TextStyle(fontSize: 14, height: 1.6),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
