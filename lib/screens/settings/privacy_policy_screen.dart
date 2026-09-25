import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // 💡 施行日・最終改定日。内容を更新した際は、ここも忘れずに更新してください
  static const String _effectiveDate = '2026年1月1日';
  static const String _lastUpdated = '2026年1月1日';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'プライバシーポリシー',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'frendy プライバシーポリシー',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '施行日：$_effectiveDate　最終改定日：$_lastUpdated',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const _Body(
              text:
                  '〔運営者名〕（以下「当方」といいます）は、当方が提供するマッチングアプリケーション「frendy」（以下「本サービス」といいます）における、利用者の個人情報の取扱いについて、以下のとおりプライバシーポリシー（以下「本ポリシー」といいます）を定めます。本サービスをご利用いただくにあたっては、本ポリシーに同意いただいたものとみなします。',
            ),

            _Section(
              title: '第1条（収集する情報）',
              body:
                  '当方は、本サービスの提供にあたり、以下の情報を取得します。\n\n'
                  '1. 利用者からご提供いただく情報\n'
                  '・氏名またはニックネーム\n'
                  '・メールアドレス、パスワード（暗号化して保存されます）\n'
                  '・生年月日または年齢、性別\n'
                  '・居住地（都道府県・市区町村等の入力内容）\n'
                  '・プロフィール写真\n'
                  '・趣味、興味関心、自己紹介文、価値観に関する回答その他プロフィールに入力される情報\n'
                  '・本人確認書類の画像（運転免許証、健康保険証、マイナンバーカード、パスポート、在留カード等）\n'
                  '・他の利用者とのメッセージ、通報内容、運営へのご意見・お問い合わせ内容\n\n'
                  '2. 本サービスの利用に伴い自動的に取得する情報\n'
                  '・端末情報（OSの種類、端末識別子等）\n'
                  '・ログイン日時、最終利用日時等の利用履歴\n'
                  '・いいね、足跡、友達関係、ブロック関係等、利用者間の関係性を示す情報\n\n'
                  '3. 決済に関する情報\n'
                  'サブスクリプション等の有料機能をご利用いただく場合、決済処理はApple社またはGoogle社が提供する決済プラットフォームを通じて行われ、クレジットカード番号等の決済情報そのものは当方では保持しません。',
            ),

            _Section(
              title: '第2条（利用目的）',
              body:
                  '当方は、取得した情報を以下の目的で利用します。\n\n'
                  '1. 本サービスの提供、維持、保護および改善のため\n'
                  '2. 利用者の本人確認および年齢確認のため（本サービスは18歳未満の方はご利用いただけません）\n'
                  '3. 利用者間のマッチング・おすすめ表示等、本サービスの主要機能を実現するため\n'
                  '4. 不正利用、規約違反、なりすまし等の防止および対応のため\n'
                  '5. 利用者からのお問い合わせへの対応のため\n'
                  '6. 有料プランの提供および課金管理のため\n'
                  '7. 重要なお知らせ等、本サービスに関する通知を行うため\n'
                  '8. 統計データの作成（個人を特定できない形に加工したものに限ります）のため\n'
                  '9. 前各号のほか、本サービスの適切な運営に必要な業務のため',
            ),

            _Section(
              title: '第3条（第三者提供）',
              body:
                  '当方は、次に掲げる場合を除き、あらかじめ利用者の同意を得ることなく、第三者に個人情報を提供することはありません。\n\n'
                  '1. 法令に基づく場合\n'
                  '2. 人の生命、身体または財産の保護のために必要がある場合であって、本人の同意を得ることが困難であるとき\n'
                  '3. 国の機関もしくは地方公共団体またはその委託を受けた者が法令の定める事務を遂行することに対して協力する必要がある場合であって、本人の同意を得ることにより当該事務の遂行に支障を及ぼすおそれがあるとき\n'
                  '4. 合併その他の事由による事業の承継に伴って個人情報が提供される場合であって、承継前の利用目的の範囲内でのみ利用されるとき\n\n'
                  'なお、他の利用者に対して表示されるプロフィール情報（ニックネーム・年齢・写真・趣味等、利用者自身が入力し公開設定とした情報）は、本サービスの機能上、他の利用者から閲覧可能となります。本人確認書類の画像は、審査担当者以外には公開されません。',
            ),

            _Section(
              title: '第4条（外部サービスの利用）',
              body:
                  '本サービスは、以下の外部サービスを利用しており、これらのサービス提供事業者にも情報が送信される場合があります。各事業者のプライバシーポリシーもあわせてご確認ください。\n\n'
                  '・Google LLC（Firebase Authentication、Cloud Firestore、Firebase Cloud Storage等）\n'
                  '・Apple Inc.（Sign in with Apple、App Store決済等）\n'
                  '・Google LLC（Google Sign-In、Google Play決済等）\n\n'
                  '当方は、これらの外部サービス提供事業者に対し、業務委託契約等を通じて適切な安全管理措置を求めています。',
            ),

            _Section(
              title: '第5条（安全管理措置）',
              body:
                  '当方は、取得した個人情報の漏えい、滅失またはき損の防止その他の安全管理のために、以下を含む必要かつ適切な措置を講じます。\n\n'
                  '・通信の暗号化（SSL/TLS）\n'
                  '・アクセス制御（本人確認書類等の機微情報は、権限を持つ担当者以外アクセスできない設定とします）\n'
                  '・不正アクセス対策\n'
                  '・退会時における個人情報の速やかな削除（詳細は第8条をご覧ください）',
            ),

            _Section(
              title: '第6条（未成年者の利用について）',
              body:
                  '本サービスは18歳以上の方のみご利用いただけます。当方は、本人確認書類の提出による年齢確認を実施し、18歳未満であることが判明した場合、当該利用者のアカウントを停止または削除する場合があります。',
            ),

            _Section(
              title: '第7条（保有期間とデータの削除）',
              body:
                  '当方は、利用目的の達成に必要な範囲で個人情報を保有します。利用者が退会手続きを行った場合、当方は以下を速やかに削除します。\n\n'
                  '・プロフィール情報、プロフィール写真\n'
                  '・本人確認のために提出された身分証明書の画像\n'
                  '・他の利用者の情報に残る、当該利用者との関係性を示す情報（友達関係、いいね、ブロック等）\n\n'
                  'ただし、法令上の保存義務がある情報、不正利用防止のために合理的に必要な範囲の通報記録等については、この限りではありません。',
            ),

            _Section(
              title: '第8条（利用者の権利）',
              body:
                  '利用者は、当方が保有する自己の個人情報について、法令の定めに基づき、開示、訂正、利用停止、消去等を請求することができます。ご希望の場合は、本ポリシー末尾のお問い合わせ窓口までご連絡ください。本人確認の上、法令に従い対応いたします。',
            ),

            _Section(
              title: '第9条（Cookie等の利用）',
              body:
                  '本サービスは、利用状況の分析やサービス改善のため、Cookieに類する技術（端末識別子等）を利用する場合があります。これらは個人を特定する情報と直接結び付けて利用することはありません。',
            ),

            _Section(
              title: '第10条（プライバシーポリシーの変更）',
              body:
                  '当方は、必要に応じて本ポリシーの内容を変更することがあります。重要な変更を行う場合は、本サービス内での通知その他の適切な方法によりお知らせします。変更後のポリシーは、本サービス上に表示した時点から効力を生じるものとします。',
            ),

            _Section(
              title: '第11条（お問い合わせ窓口）',
              body:
                  '本ポリシーに関するお問い合わせは、以下の窓口までご連絡ください。\n\n'
                  '〔運営者名〕\n'
                  '所在地：〔住所〕\n'
                  'お問い合わせ：アプリ内「ヘルプ・お問い合わせ」より受け付けております',
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            const Text(
              '以上',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.point,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.7,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String text;
  const _Body({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          height: 1.7,
          color: Colors.black87,
        ),
      ),
    );
  }
}
