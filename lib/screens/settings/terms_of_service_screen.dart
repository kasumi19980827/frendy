import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _effectiveDate = '2026年1月1日';
  static const String _lastUpdated = '2026年1月1日';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '利用規約',
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
              'frendy 利用規約',
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
                  '本利用規約（以下「本規約」といいます）は、〔運営者名〕（以下「当方」といいます）が提供するマッチングアプリケーション「frendy」（以下「本サービス」といいます）の利用条件を定めるものです。利用者の皆さま（以下「ユーザー」といいます）には、本規約に従って本サービスをご利用いただきます。',
            ),

            _Section(
              title: '第1条（適用）',
              body:
                  '本規約は、ユーザーと当方との間の本サービスの利用に関わる一切の関係に適用されるものとします。当方が本サービス上で掲示する個別のルール・ガイドライン等は、本規約の一部を構成するものとします。',
            ),

            _Section(
              title: '第2条（利用登録）',
              body:
                  '1. 本サービスの利用を希望する者は、当方の定める方法によって利用登録を申請し、当方がこれを承認することによって、利用登録が完了するものとします。\n'
                  '2. 当方は、以下のいずれかに該当すると判断した場合、利用登録の申請を承認しないことがあり、その理由については開示義務を負わないものとします。\n'
                  '　・満18歳未満である場合、または年齢確認書類により年齢を確認できない場合\n'
                  '　・虚偽の情報を届け出た場合\n'
                  '　・本規約に違反したことがある者からの申請である場合\n'
                  '　・その他、当方が利用登録を適当でないと判断した場合',
            ),

            _Section(
              title: '第3条（アカウントの管理）',
              body:
                  '1. ユーザーは、自己の責任において、本サービスのログイン情報（メールアドレス、パスワード等）を適切に管理するものとします。\n'
                  '2. ユーザーは、いかなる場合にも、ログイン情報を第三者に譲渡または貸与し、もしくは第三者と共用することはできません。\n'
                  '3. ログイン情報が第三者によって使用されたことによって生じた損害は、当方に故意または重過失がある場合を除き、当方は一切の責任を負いません。',
            ),

            _Section(
              title: '第4条（年齢確認・本人確認）',
              body:
                  '本サービスは、安心・安全なコミュニティの維持のため、ユーザーに対し公的身分証明書の提出による年齢確認・本人確認を求めることがあります。ユーザーは、正確な情報および真正な書類を提出するものとし、虚偽の提出を行った場合、当方は当該ユーザーの利用を制限または退会させることができるものとします。',
            ),

            _Section(
              title: '第5条（禁止事項）',
              body:
                  'ユーザーは、本サービスの利用にあたり、以下の行為をしてはなりません。\n\n'
                  '1. 法令または公序良俗に違反する行為\n'
                  '2. 犯罪行為に関連する行為\n'
                  '3. 当方、他のユーザーまたは第三者の知的財産権、肖像権、プライバシー権、名誉その他の権利または利益を侵害する行為\n'
                  '4. 他のユーザーに対する誹謗中傷、脅迫、嫌がらせ、ストーカー行為\n'
                  '5. 虚偽の情報を登録する行為、なりすましによる利用行為\n'
                  '6. 実在しない、または他人の写真を自己のプロフィール写真として使用する行為\n'
                  '7. 未成年者との不適切な接触を目的とする行為\n'
                  '8. 金銭、物品等の要求または勧誘を目的とする行為（いわゆる「サクラ」「業者」行為を含む）\n'
                  '9. 他のサービスへの勧誘、営業、宗教活動、政治活動を目的とする行為\n'
                  '10. わいせつ、暴力的、差別的な内容を含む情報を投稿する行為\n'
                  '11. 本サービスのシステムに不正にアクセスし、またはその機能を妨害する行為\n'
                  '12. 複数のアカウントを不正に作成する行為\n'
                  '13. 当方が事前の書面による承諾なく、本サービスを商業目的で利用する行為\n'
                  '14. その他、当方が不適切と判断する行為',
            ),

            _Section(
              title: '第6条（本サービスの提供の停止等）',
              body:
                  '当方は、以下のいずれかの事由があると判断した場合、ユーザーに事前に通知することなく本サービスの全部または一部の提供を停止または中断することができるものとします。\n\n'
                  '1. 本サービスにかかるシステムの保守点検または更新を行う場合\n'
                  '2. 地震、落雷、火災、停電、天災等の不可抗力により本サービスの提供が困難となった場合\n'
                  '3. コンピュータまたは通信回線等が事故により停止した場合\n'
                  '4. その他、当方が本サービスの提供が困難と判断した場合\n\n'
                  '当方は、本サービスの提供の停止または中断により、ユーザーまたは第三者が被ったいかなる不利益または損害についても、一切の責任を負わないものとします。',
            ),

            _Section(
              title: '第7条（利用制限および登録抹消）',
              body:
                  '当方は、ユーザーが以下のいずれかに該当する場合、事前の通知なく、当該ユーザーに対して本サービスの全部もしくは一部の利用を制限し、またはユーザーとしての登録を抹消することができるものとします。\n\n'
                  '1. 本規約のいずれかの条項に違反した場合\n'
                  '2. 登録事項に虚偽の事実があることが判明した場合\n'
                  '3. 料金等の支払債務の不履行があった場合\n'
                  '4. 当方からの連絡に対し、一定期間返答がない場合\n'
                  '5. 本サービスについて、最終の利用から一定期間利用がない場合\n'
                  '6. その他、当方が本サービスの利用を適当でないと判断した場合\n\n'
                  '当方は、本条に基づき当方が行った行為によりユーザーに生じた損害について、一切の責任を負いません。',
            ),

            _Section(
              title: '第8条（退会）',
              body:
                  'ユーザーは、当方の定める手続きにより、本サービスから退会できるものとします。退会後は、プロフィール情報、写真、提出済みの本人確認書類等のデータが削除されます。詳細はプライバシーポリシーをご確認ください。',
            ),

            _Section(
              title: '第9条（有料サービス）',
              body:
                  '1. 本サービスの一部機能は、有料のサブスクリプションプランとして提供されます。\n'
                  '2. 料金、決済方法、契約期間、自動更新の有無等の詳細は、本サービス内の表示およびApp Store／Google Playの表示するところによります。\n'
                  '3. サブスクリプションの解約は、ユーザーがご利用の端末のOS提供事業者（Apple社またはGoogle社）が提供する設定画面から行うものとし、当方は代行しません。\n'
                  '4. 既にお支払いいただいた料金は、法令に特段の定めがある場合を除き、返金いたしかねます。',
            ),

            _Section(
              title: '第10条（コンテンツの取扱い）',
              body:
                  '1. ユーザーが本サービスに投稿した文章、写真その他の情報（以下「投稿情報」といいます）にかかる著作権等の知的財産権は、ユーザーに帰属します。\n'
                  '2. ユーザーは、当方に対し、本サービスの提供、改善、宣伝広告のために必要な範囲で、投稿情報を利用（複製、表示、送信等を含みます）することを許諾するものとします。\n'
                  '3. 当方は、投稿情報が第5条の禁止事項に該当すると判断した場合、ユーザーへの事前の通知なく、当該投稿情報を削除できるものとします。',
            ),

            _Section(
              title: '第11条（通報および対応）',
              body:
                  '当方は、ユーザーからの通報を受けた場合、内容を確認の上、必要と判断したときは、当該通報対象のユーザーに対し、利用制限、登録抹消その他当方が適切と判断する措置を講じることができるものとします。措置の内容および理由について、当方は開示義務を負わないものとします。',
            ),

            _Section(
              title: '第12条（保証の否認および免責事項）',
              body:
                  '1. 当方は、本サービスに事実上または法律上の瑕疵（安全性、信頼性、正確性、完全性、有効性、特定の目的への適合性、セキュリティ等に関する欠陥、エラーやバグ、権利侵害等を含みます）がないことを明示的にも黙示的にも保証しておりません。\n'
                  '2. 本サービスは、ユーザー間の出会い・交流の場を提供するものであり、当方は、ユーザー間で生じたトラブル（金銭トラブル、実際の面会時のトラブル等を含みます）について一切の責任を負いません。ユーザーは自己の責任において本サービスを利用するものとします。\n'
                  '3. 当方は、本サービスに起因してユーザーに生じたあらゆる損害について、当方の故意または重過失による場合を除き、一切の責任を負いません。',
            ),

            _Section(
              title: '第13条（サービス内容の変更等）',
              body:
                  '当方は、ユーザーへの事前の告知をもって、本サービスの内容を変更、追加または廃止することがあり、ユーザーはこれを承諾するものとします。',
            ),

            _Section(
              title: '第14条（利用規約の変更）',
              body:
                  '当方は、必要と判断した場合には、ユーザーに通知することなく本規約を変更することができるものとします。本規約の変更後、本サービスの利用を継続したユーザーは、変更後の規約に同意したものとみなします。',
            ),

            _Section(
              title: '第15条（個人情報の取扱い）',
              body:
                  '当方は、本サービスの利用によって取得する個人情報については、当方の定める「プライバシーポリシー」に従い適切に取り扱うものとします。',
            ),

            _Section(
              title: '第16条（権利義務の譲渡の禁止）',
              body:
                  'ユーザーは、当方の書面による事前の承諾なく、利用契約上の地位または本規約に基づく権利もしくは義務を第三者に譲渡し、または担保に供することはできません。',
            ),

            _Section(
              title: '第17条（準拠法・裁判管轄）',
              body:
                  '1. 本規約の解釈にあたっては、日本法を準拠法とします。\n'
                  '2. 本サービスに関して紛争が生じた場合には、〔管轄裁判所名〕を第一審の専属的合意管轄裁判所とします。',
            ),

            _Section(title: '附則', body: '本規約は、$_effectiveDate から施行します。'),

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
