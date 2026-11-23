import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';

// ============================================================================
// Frendyの説明
// 💡 文言はアプリの実際の仕様に合わせて自由に書き換えてください。
//    下の _steps / _features / _safety / _plans のリストを編集するだけで反映されます。
// ============================================================================

class _Item {
  const _Item(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

// 💡 アプリの実際の動きに合わせた説明
//    ・検索に表示されるのは「名前・年齢・写真・好きなこと（趣味）」がそろった人だけ
//    ・トークの閲覧・送信には年齢確認（承認済み）が必要
//    ・新しい相手とのトーク開始は、プランごとに月の上限がある（index.ts の TALK_LIMITS）
//    ・友達申請は「お互い4通以上」（index.ts の REQUIRED_MESSAGES）
//    数字を変えたときは、ここの文章も合わせて直してください。
const List<_Item> _steps = [
  _Item(
    Icons.person_outline,
    'プロフィールを作る',
    '写真・名前・年齢・好きなこと（趣味）を登録しましょう。この4つがそろうと「探す」に表示されるようになります。プロフィールが充実しているほど、相手に興味を持ってもらいやすくなります。',
  ),
  _Item(
    Icons.verified_user_outlined,
    '年齢確認をする',
    'トークでメッセージを読んだり送ったりするには、年齢確認が必要です。マイページから身分証を提出し、運営の確認が終わると使えるようになります。',
  ),
  _Item(
    Icons.search,
    '気になる人を探す',
    '「探す」タブから、気の合いそうな人を見つけましょう。「おすすめ」には、あなたと趣味が近い人が表示されます。キーワードやIDで検索することもできます。',
  ),
  _Item(
    Icons.forum_outlined,
    'トークでやり取りする',
    '相手のプロフィールから「トークする」を押して、まずは気軽にお話ししてみましょう。',
  ),
  _Item(
    Icons.person_add_alt_1_outlined,
    '友達申請をする',
    'お互いに4通以上メッセージをやり取りすると、友達申請ができるようになります。相手が承認すれば友達になれます。',
  ),
];

const List<_Item> _features = [
  _Item(
    Icons.thumb_up_alt_outlined,
    'いいね',
    '気になる相手に「いいね」を送れます。いいねをくれた相手は「友達」タブで確認できます。',
  ),
  _Item(Icons.visibility_outlined, '足跡', 'あなたのプロフィールを見てくれた人が「足跡」として残ります。'),
  _Item(Icons.group_outlined, '友達一覧', '友達になった相手は「友達」タブにまとめて表示されます。'),
  _Item(
    Icons.visibility_off_outlined,
    'トークの非表示',
    'トーク一覧から、トークを非表示にできます。相手から新しいメッセージが届くと、また表示されます。',
  ),
];

const List<_Item> _safety = [
  _Item(
    Icons.verified_user_outlined,
    '年齢確認・本人確認',
    '安心して使っていただくため、年齢確認・本人確認を行っています。確認が済んだ方だけがトークを利用できます。提出いただいた身分証は運営だけが確認し、他のユーザーに公開されることはありません。',
  ),
  _Item(
    Icons.block,
    'ブロック',
    '関わりたくない相手はブロックできます。ブロックすると、お互いの「探す」や一覧に表示されなくなり、メッセージも送れなくなります。ブロックした相手は、マイページの「ブロック中のユーザー」から解除できます。',
  ),
  _Item(
    Icons.report_problem_outlined,
    '通報',
    '不適切な言動や規約違反を見つけたら、相手のプロフィールやトーク一覧から通報してください。運営で内容を確認し、対応します。',
  ),
];

const List<_Item> _plans = [
  _Item(
    Icons.card_membership_outlined,
    'フリープラン（無料）',
    '基本的な機能を無料で使えます。新しい相手とのトーク開始は月5人までです。足跡やいいねをくれた相手は、モザイク表示になります。',
  ),
  _Item(
    Icons.workspace_premium_outlined,
    'ライトプラン（月額250円）',
    '新しい相手とのトーク開始が月15人までになります。足跡をつけた相手と、いいねをくれた相手を確認できるようになります。',
  ),
  _Item(
    Icons.diamond_outlined,
    'スタンダードプラン（月額500円）',
    'ライトプランの内容に加えて、新しい相手とのトーク開始の上限がなくなります。',
  ),
  _Item(
    Icons.star_outline,
    'プレミアムプラン（月額980円）',
    'スタンダードプランの内容に加えて、「探す」の検索結果であなたのプロフィールが上位に表示されます。',
  ),
  _Item(
    Icons.info_outline,
    'プランの詳細',
    '一度トークを始めた相手とは、上限に関係なくいつでもやり取りできます。料金はすべて税込です。プランの詳細はマイページの「サブスクリプション管理」からご覧いただけます。',
  ),
];

class AboutFrendyScreen extends StatelessWidget {
  const AboutFrendyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Frendyの説明',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildHero(),
            const SizedBox(height: 28),
            const _SectionTitle('はじめ方'),
            const SizedBox(height: 12),
            for (var i = 0; i < _steps.length; i++)
              _StepTile(number: i + 1, item: _steps[i]),
            const SizedBox(height: 28),
            const _SectionTitle('主な機能'),
            const SizedBox(height: 12),
            for (final item in _features) _ItemCard(item: item),
            const SizedBox(height: 28),
            const _SectionTitle('安心・安全のために'),
            const SizedBox(height: 12),
            for (final item in _safety) _ItemCard(item: item),
            const SizedBox(height: 28),
            const _SectionTitle('プランについて'),
            const SizedBox(height: 12),
            for (final item in _plans) _ItemCard(item: item),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'ご不明な点は、マイページの「ヘルプ・お問い合わせ」からご連絡ください。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.point.withValues(alpha: 0.85), AppColors.point],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.diversity_3, color: Colors.white, size: 40),
          SizedBox(height: 12),
          Text(
            'Frendyとは',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Frendyは、気の合う新しい友達と出会えるアプリです。'
            'メッセージで少しずつ仲良くなって、友達になりましょう。',
            style: TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 部品
// ----------------------------------------------------------------------------
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.point,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.number, required this.item});
  final int number;
  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.point,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});
  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.point.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: AppColors.point, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
