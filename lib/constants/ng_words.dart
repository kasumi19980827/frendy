// ============================================================================
// 友達作り専用のための「禁止の言葉」チェック
//
// 置き場所：lib/constants/ng_words.dart
//
// ・アプリ側では、送信や保存の「前」にチェックして、やさしく注意を出す
// ・本当のガードは firestore.rules（すり抜け対策は Cloud Functions）で行っている
//   → 3か所（このファイル・firestore.rules・index.ts）の言葉の一覧は合わせること
// ============================================================================

/// メッセージで止める言葉（普段の会話で使う言葉は入れない）
const List<String> kNgMessageWords = [
  '恋人募集',
  '恋人探し',
  '彼氏募集',
  '彼女募集',
  '彼氏探し',
  '彼女探し',
  '交際希望',
  '交際相手募集',
  '結婚相手募集',
  '出会い目的',
  '出会い系',
  'セフレ',
  'ワンナイト',
  'パパ活',
  'ママ活',
  '援助交際',
  '援交',
  '大人の関係',
  '体の関係',
  '身体の関係',
  'ホ別',
];

/// プロフィールで止める言葉（メッセージより厳しめ）
const List<String> kNgProfileWords = [
  ...kNgMessageWords,
  '恋人候補',
  '彼氏候補',
  '彼女候補',
  '恋人ほしい',
  '恋人欲しい',
  '彼氏ほしい',
  '彼氏欲しい',
  '彼女ほしい',
  '彼女欲しい',
  '真剣交際',
  '婚活',
  '恋活',
];

/// 判定用に文字をそろえる：全角英数→半角、カタカナ→ひらがな、空白・記号を除去
String _normalize(String text) {
  final buf = StringBuffer();
  for (final rune in text.runes) {
    var c = rune;
    // 全角英数・記号 → 半角
    if (c >= 0xFF01 && c <= 0xFF5E) c -= 0xFEE0;
    // カタカナ → ひらがな
    if (c >= 0x30A1 && c <= 0x30F6) c -= 0x60;
    final ch = String.fromCharCode(c);
    if (_ignoreChars.contains(ch)) continue;
    buf.write(ch.toLowerCase());
  }
  return buf.toString();
}

const String _ignoreChars = ' 　\n\t・･.,、。!?~〜ー-_*/|"\'`()「」『』【】[]';

final List<String> _msgNormalized = kNgMessageWords
    .map(_normalize)
    .toList(growable: false);
final List<String> _profileNormalized = kNgProfileWords
    .map(_normalize)
    .toList(growable: false);

String? _find(String text, List<String> normalized, List<String> originals) {
  final n = _normalize(text);
  for (var i = 0; i < normalized.length; i++) {
    if (n.contains(normalized[i])) return originals[i];
  }
  return null;
}

/// メッセージに禁止の言葉があれば、その言葉を返す（なければ null）
String? findNgInMessage(String text) =>
    _find(text, _msgNormalized, kNgMessageWords);

/// プロフィールの文章に禁止の言葉があれば、その言葉を返す（なければ null）
String? findNgInProfile(String text) =>
    _find(text, _profileNormalized, kNgProfileWords);

/// 注意メッセージ（画面で共通して使う）
const String kNgNotice =
    'frendyは友達作りのためのアプリです。\n'
    '恋人募集・交際希望・出会い目的などの内容は送信・登録できません。';
