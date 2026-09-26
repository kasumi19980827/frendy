import 'package:flutter/material.dart';

/// 💡 特定商取引法に基づく表記。
///    日本国内でサブスクリプション等の有料サービスを提供する場合、
///    この表示は法律（特定商取引法11条）で義務付けられている。
///    〔　〕の部分は、必ず実際の情報に差し替えてから公開すること
class TokushohoScreen extends StatelessWidget {
  const TokushohoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> items = [
      {'label': '販売事業者', 'value': '〔運営者名〕'},
      {'label': '運営統括責任者', 'value': '〔責任者氏名〕'},
      {'label': '所在地', 'value': '〔住所〕（請求があれば遅滞なく開示します）'},
      {'label': 'お問い合わせ先', 'value': 'アプリ内「ヘルプ・お問い合わせ」よりご連絡ください'},
      {
        'label': '販売価格',
        'value':
            '各プランの価格は、アプリ内の「メンバーシッププラン」画面およびApp Store／Google Playの表示価格をご確認ください（すべて税込）',
      },
      {'label': '販売価格以外の必要料金', 'value': 'インターネット接続にかかる通信料はお客様のご負担となります'},
      {
        'label': 'お支払い方法',
        'value':
            'App StoreまたはGoogle Playを通じたお支払い（クレジットカード、キャリア決済等、各ストアが対応する方法）',
      },
      {
        'label': 'お支払い時期',
        'value': 'サブスクリプション契約時、および契約が自動更新されるたびに、ご利用の決済方法へ課金されます',
      },
      {'label': 'サービス提供時期', 'value': 'お支払い手続き完了後、直ちにご利用いただけます'},
      {
        'label': '返品・キャンセルについて',
        'value':
            '本サービスはデジタルコンテンツのため、提供開始後の返品・返金には応じられません。'
            'サブスクリプションの解約は、ご利用の端末のApp StoreまたはGoogle Playのサブスクリプション管理画面からいつでも行うことができます。'
            '解約手続きを行わない限り、契約期間終了時に自動的に更新されます。',
      },
      {
        'label': '動作環境',
        'value': 'iOS／Androidの対応バージョンについては、各アプリストアの掲載ページをご確認ください',
      },
    ];

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
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 32),
        itemBuilder: (context, index) {
          final item = items[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item['label']!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item['value']!,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
          );
        },
      ),
    );
  }
}
