import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/constants/app_tags.dart';
import 'package:matching_app/screens/profile/profile_detail_screen.dart';

// ============================================================================
// さがす（ユーザー検索）
//
// 💡 5万人規模を想定した作り
//  以前は users コレクションを「全員分」リアルタイムで読み込んでいたため、
//  画面を開くたびに全ユーザー数ぶんの読み取り料金がかかり、
//  誰かがプロフィールを変えるたびに全員の画面に通知が飛んでいた。
//  → 最近ログインした順に30人ずつ読み込む方式に変更。
//
//  ・性別・タグ（1つ目）はサーバー側で絞り込む（インデックスが必要）
//  ・年齢・キーワード・2つ目以降のタグは、読み込んだ分の中で絞り込む
//  ・ID検索（プロフィールに表示される英数字のID）はサーバー側で前方一致検索
//  ・ブロック関係（自分がブロック・相手からブロック）は一覧から除外
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const int _kPageSize = 30; // 1回の読み込み件数
const int _kMinResultsPerLoad = 12; // 1回の「続きを読む」で最低これだけ表示したい
const int _kMaxScanPerLoad = 150; // 絞り込みで外れが多くても、1回で読むのはここまで
const int _kRecommendPool = 150; // おすすめを計算する対象（最近ログインした人から）
const int _kMaxRelations = 1000; // ブロック一覧を読む上限
const Duration _kLastLoginUpdateInterval = Duration(hours: 6);

final RegExp _kIdPattern = RegExp(r'^[A-Za-z0-9]{6,28}$');
// 前方一致検索の上限に使う文字（目に見えない特殊文字なので、コードで作る）
final String _kIdUpperBound = String.fromCharCode(0xf8ff);

FirebaseFirestore get _db => FirebaseFirestore.instance;

// キーワード同士を区切る文字（読点・カンマ）
final RegExp _kWordSeparator = RegExp(r'[、,，]+');
// キーワードの前後に付いた記号を取り除く
const String _kEdgeSymbol = r'[。．/・\s　!！?？()（）「」『』【】:：;；\-－~〜…]+';
final RegExp _kEdgeSymbolRe = RegExp('^$_kEdgeSymbol|$_kEdgeSymbol\$');

const List<String> _kIgnoreWords = [
  'なし',
  '未設定',
  '特になし',
  '未入力',
  '設定なし',
  'ありません',
  '特になしです',
];
const List<String> _kHobbyFields = ['hobby', 'recentInterest'];

// ----------------------------------------------------------------------------
// 安全にデータを取り出すヘルパー（型が違ってもクラッシュしない）
// ----------------------------------------------------------------------------
String _str(Map<String, dynamic> d, String key, [String fallback = '']) {
  final v = d[key];
  if (v is String && v.trim().isNotEmpty) return v.trim();
  if (v is num) return v.toString();
  return fallback;
}

int _ageOf(Map<String, dynamic> d) {
  final v = d['age'];
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

List<String> _stringList(dynamic v) =>
    v is List ? v.whereType<String>().toList() : const [];

String? _firstImageUrl(Map<String, dynamic> d) {
  final urls = d['imageUrls'];
  if (urls is! List || urls.isEmpty) return null;
  final first = urls.first;
  return first is String && first.startsWith('https://') ? first : null;
}

List<String> _splitToKeywords(String text) {
  return text
      .split(_kWordSeparator)
      .map((s) => _normalize(s.replaceAll(_kEdgeSymbolRe, '').trim()))
      .where((s) => s.length >= 2 && !_kIgnoreWords.contains(s))
      .toList();
}

// 💡 表記ゆれをそろえる
//    ・英字は小文字に（Pokemon → pokemon）
//    ・全角英数字は半角に（ＡＢＣ１２３ → abc123）
//    ・カタカナはひらがなに（ポケモン → ぽけもん）
//    これで「ぽけもん」でも「ポケモン」でも同じように見つかる
String _normalize(String text) {
  final buf = StringBuffer();
  for (final code in text.runes) {
    if (code >= 0xFF01 && code <= 0xFF5E) {
      buf.writeCharCode(code - 0xFEE0); // 全角英数字・記号 → 半角
    } else if (code >= 0x30A1 && code <= 0x30F6) {
      buf.writeCharCode(code - 0x60); // カタカナ → ひらがな
    } else {
      buf.writeCharCode(code);
    }
  }
  return buf.toString().toLowerCase();
}

// 検索欄の文字を、スペース（半角・全角）で区切って単語のリストにする
// 例：「愛知　ぽけもん」→ ['愛知', 'ぽけもん']
final RegExp _kSpaces = RegExp(r'[\s　]+');
const int _kMaxSearchWords = 5; // 単語は5個まで（多すぎる入力で重くならないように）

List<String> _searchWords(String text) {
  return _normalize(text)
      .split(_kSpaces)
      .map((w) => w.replaceAll(_kEdgeSymbolRe, '').trim())
      .where((w) => w.isNotEmpty)
      .toSet()
      .take(_kMaxSearchWords)
      .toList();
}

class _Candidate {
  const _Candidate(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
}

// ============================================================================
// 画面
// ============================================================================
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ScrollController _gridController = ScrollController();
  final ScrollController _listController = ScrollController();
  Timer? _debounce;

  late final String _myId;
  bool _isTwoColumn = true;

  // 検索条件
  String _searchKeyword = '';
  int _minAge = 18;
  int _maxAge = 50;
  String _selectedGender = 'すべて';
  final List<String> _selectedTags = [];
  String _selectedTab = 'recommend'; // 'all'（ユーザー）/ 'recommend'（おすすめ）
  bool _isManualSelection = false;

  // 自分の情報
  bool _initializing = true;
  bool _initFailed = false;
  final Set<String> _excludedIds = {}; // 自分・ブロック関係のユーザー
  List<String> _myHobbyWords = [];

  // 検索結果
  final List<_Candidate> _results = [];
  final Set<String> _resultIds = {};
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  // 💡 読み込みの段階
  //   0：最終ログインが新しい順（lastLoginTime がある人）
  //   1：それ以外の人（lastLoginTime がまだない人）を ID 順に
  int _phase = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadFailed = false;
  int _requestId = 0; // 条件を変えたとき、古い読み込み結果を捨てるための番号

  @override
  void initState() {
    super.initState();
    _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _gridController.addListener(() => _onScroll(_gridController));
    _listController.addListener(() => _onScroll(_listController));
    if (_myId.isNotEmpty) _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gridController.dispose();
    _listController.dispose();
    super.dispose();
  }

  // ==========================================================================
  // 最初の準備：自分のプロフィールとブロック関係を1回だけ読む
  // ==========================================================================
  Future<void> _init() async {
    setState(() {
      _initializing = true;
      _initFailed = false;
    });

    try {
      final myRef = _db.collection('users').doc(_myId);
      final results = await Future.wait([
        myRef.get(),
        myRef.collection('blocks').limit(_kMaxRelations).get(),
        myRef.collection('blockedBy').limit(_kMaxRelations).get(),
      ]).timeout(_kNetworkTimeout);

      final mySnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final myBlocks = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final myBlockedBy = results[2] as QuerySnapshot<Map<String, dynamic>>;
      final myData = mySnap.data() ?? {};

      _excludedIds
        ..clear()
        ..add(_myId)
        ..addAll(myBlocks.docs.map((d) => d.id))
        ..addAll(myBlockedBy.docs.map((d) => d.id))
        // ⚠️ 移行用：古い方式（配列）のブロックも除外する
        ..addAll(_stringList(myData['blocks']))
        ..addAll(_stringList(myData['blockedBy']));

      final words = <String>[];
      for (final field in _kHobbyFields) {
        final v = myData[field];
        if (v is String) {
          words.addAll(_splitToKeywords(v));
        } else if (v is List) {
          for (final item in v.whereType<String>()) {
            words.addAll(_splitToKeywords(item));
          }
        }
      }
      _myHobbyWords = words.toSet().toList();

      _touchLastLogin(myData['lastLoginTime']);

      if (!mounted) return;
      setState(() => _initializing = false);
      _reload();
    } catch (e) {
      debugPrint('検索の準備エラー: $e');
      if (mounted) {
        setState(() {
          _initializing = false;
          _initFailed = true;
        });
      }
    }
  }

  // 💡 「最近ログインした順」に並べるため、自分の最終ログイン時刻を更新する。
  //    書き込みを減らすため、前回から6時間以上たっているときだけ。
  void _touchLastLogin(dynamic last) {
    final now = DateTime.now();
    if (last is Timestamp &&
        now.difference(last.toDate()) < _kLastLoginUpdateInterval) {
      return;
    }
    _db
        .collection('users')
        .doc(_myId)
        .update({'lastLoginTime': FieldValue.serverTimestamp()})
        .catchError((Object e) => debugPrint('最終ログイン時刻の更新エラー: $e'));
  }

  // ==========================================================================
  // 読み込み
  // ==========================================================================

  // 性別と1つ目のタグはサーバー側で絞り込む
  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = _db.collection('users');
    if (_selectedGender != 'すべて') {
      q = q.where('gender', isEqualTo: _selectedGender);
    }
    if (_selectedTags.isNotEmpty) {
      q = q.where('tags', arrayContains: _selectedTags.first);
    }
    // 💡 段階0は最終ログイン順。lastLoginTime がない人は、この並べ方では
    //    Firestore の仕様で結果に入らないため、段階1で ID 順に読み込んで拾う
    return _phase == 0 ? q.orderBy('lastLoginTime', descending: true) : q;
  }

  // 表示しない理由（表示してよいなら null）
  // プロフィール未完成・ブロック関係・停止中は除外する
  String? _hiddenReason(String id, Map<String, dynamic> d) {
    if (id == _myId) return '自分';
    if (_excludedIds.contains(id)) return 'ブロック関係';
    if (d['isBanned'] == true) return '利用停止中';

    final name = _str(d, 'name');
    if (name.isEmpty || name == '名前未設定' || name == 'ユーザー') return '名前が未設定';
    if (_ageOf(d) <= 0) return '年齢が未設定';
    if (_firstImageUrl(d) == null) return '写真がない（または https 以外のURL）';
    if (_str(d, 'hobby').isEmpty) return '「好きなこと・趣味」が未入力';
    return null;
  }

  bool _isDisplayable(String id, Map<String, dynamic> d) {
    final reason = _hiddenReason(id, d);
    // 💡 開発中だけ、表示されない理由をログに出す（原因を調べやすくするため）
    if (kDebugMode && reason != null && reason != '自分') {
      debugPrint(
        '検索で非表示: ${id.substring(0, id.length.clamp(0, 8))} 理由: $reason',
      );
    }
    return reason == null;
  }

  // 検索の対象にする項目
  static const List<String> _kSearchFields = [
    'name',
    'location',
    'hobby',
    'recentInterest',
    'idealFriend',
    'holidayActivity',
    'tags',
  ];

  // 検索条件（キーワード・年齢・性別・タグ）に合うか
  bool _matchesFilters(Map<String, dynamic> d) {
    final words = _searchWords(_searchKeyword);
    if (words.isNotEmpty) {
      // 💡 対象の項目をまとめて1つの文章にし、表記ゆれをそろえておく
      final buf = StringBuffer();
      for (final field in _kSearchFields) {
        final v = d[field];
        if (v is String) buf.write(' $v');
        if (v is List) buf.write(' ${v.whereType<String>().join(' ')}');
      }
      final text = _normalize(buf.toString());

      // 💡 すべての単語が含まれている人だけを表示する（AND検索）
      //    例：「愛知　ぽけもん」→ 居住地が愛知で、趣味にポケモンがある人
      if (!words.every(text.contains)) return false;
    }

    final age = _ageOf(d);
    if (age < _minAge || age > _maxAge) return false;

    if (_selectedGender != 'すべて' && _str(d, 'gender') != _selectedGender) {
      return false;
    }

    if (_selectedTags.isNotEmpty) {
      final tags = _stringList(d['tags']);
      if (!_selectedTags.every(tags.contains)) return false;
    }
    return true;
  }

  int _planPriority(Map<String, dynamic> d) => d['plan'] == 'premium' ? 1 : 0;

  int _hobbyScore(Map<String, dynamic> d) {
    if (_myHobbyWords.isEmpty) return 0;
    final buffer = StringBuffer();
    for (final field in _kHobbyFields) {
      final v = d[field];
      if (v is String) buffer.write(' $v');
      if (v is List) buffer.write(' ${v.whereType<String>().join(' ')}');
    }
    // 💡 おすすめも、カタカナ・ひらがなの違いを気にせず比べる
    final text = _normalize(buffer.toString());
    return _myHobbyWords.where(text.contains).length;
  }

  // 条件を変えたときは、少し待ってから読み直す（入力中に何度も読まない）
  void _scheduleReload([Duration delay = const Duration(milliseconds: 450)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, _reload);
  }

  void _reload() {
    if (!mounted || _initializing || _initFailed) return;
    _requestId++;
    setState(() {
      _results.clear();
      _resultIds.clear();
      _cursor = null;
      _phase = 0;
      _hasMore = true;
      _loading = false;
      _loadFailed = false;
    });
    if (_selectedTab == 'recommend') {
      _loadRecommend();
    } else {
      _loadMore();
    }
  }

  void _onScroll(ScrollController c) {
    if (_selectedTab != 'all' || !c.hasClients) return;
    if (c.position.pixels >= c.position.maxScrollExtent - 600) _loadMore();
  }

  // 1ページ分読み込み、条件に合う人を追加する
  Future<List<_Candidate>> _fetchPage(int req) async {
    var q = _baseQuery().limit(_kPageSize);
    final cursor = _cursor;
    if (cursor != null) q = q.startAfterDocument(cursor);

    final int phase = _phase;
    final snap = await q.get().timeout(_kNetworkTimeout);
    if (req != _requestId) return const [];

    if (snap.docs.isNotEmpty) _cursor = snap.docs.last;
    if (snap.docs.length < _kPageSize) {
      if (phase == 0) {
        // 最終ログイン順を読み終えたら、lastLoginTime がない人の読み込みに移る
        _phase = 1;
        _cursor = null;
      } else {
        _hasMore = false;
      }
    }

    final result = [
      for (final doc in snap.docs)
        // 段階1では、段階0で読んだ人（lastLoginTime がある人）は飛ばす
        if (!(phase == 1 && doc.data()['lastLoginTime'] is Timestamp) &&
            !_resultIds.contains(doc.id) &&
            _isDisplayable(doc.id, doc.data()) &&
            _matchesFilters(doc.data()))
          _Candidate(doc.id, doc.data()),
    ];
    debugPrint(
      '検索: 段階$phase で${snap.docs.length}人を読み込み、${result.length}人が条件に一致',
    );
    return result;
  }

  // 💡 ID検索：プロフィールに表示される英数字のIDで前方一致検索（サーバー側）
  Future<List<_Candidate>> _fetchIdMatches(int req) async {
    final raw = _searchKeyword.trim();
    if (!_kIdPattern.hasMatch(raw)) return const [];
    try {
      final snap = await _db
          .collection('users')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: raw)
          .where(FieldPath.documentId, isLessThan: '$raw$_kIdUpperBound')
          .limit(5)
          .get()
          .timeout(_kNetworkTimeout);
      if (req != _requestId) return const [];
      return [
        for (final doc in snap.docs)
          if (_isDisplayable(doc.id, doc.data()))
            _Candidate(doc.id, doc.data()),
      ];
    } catch (e) {
      debugPrint('ID検索エラー: $e');
      return const [];
    }
  }

  void _addResults(List<_Candidate> items) {
    for (final c in items) {
      if (_resultIds.add(c.id)) _results.add(c);
    }
  }

  // 「ユーザー」タブ：最近ログインした順に、続きを読み込む
  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _selectedTab != 'all') return;
    final req = _requestId;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final batch = <_Candidate>[];
      if (_cursor == null) batch.addAll(await _fetchIdMatches(req));

      int scanned = 0;
      while (batch.length < _kMinResultsPerLoad &&
          scanned < _kMaxScanPerLoad &&
          _hasMore &&
          req == _requestId) {
        final page = await _fetchPage(req);
        scanned += _kPageSize;
        batch.addAll(page.where((c) => !batch.any((b) => b.id == c.id)));
      }
      if (req != _requestId) return;

      // 💡 読み込んだまとまりの中で、プレミアムプランの人を先に表示
      batch.sort(
        (a, b) => _planPriority(b.data).compareTo(_planPriority(a.data)),
      );
      _addResults(batch);
    } catch (e) {
      debugPrint('ユーザー検索エラー: $e');
      if (req == _requestId) _loadFailed = true;
    } finally {
      if (mounted && req == _requestId) setState(() => _loading = false);
    }
  }

  // 「おすすめ」タブ：最近ログインした人の中から、趣味が近い人を並べる
  Future<void> _loadRecommend() async {
    final req = _requestId;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      final pool = <_Candidate>[];
      pool.addAll(await _fetchIdMatches(req));
      int scanned = 0;
      while (scanned < _kRecommendPool && _hasMore && req == _requestId) {
        pool.addAll(await _fetchPage(req));
        scanned += _kPageSize;
      }
      if (req != _requestId) return;

      final scored =
          pool
              .map((c) => MapEntry(c, _hobbyScore(c.data)))
              .where((e) => e.value > 0)
              .toList()
            ..sort((a, b) {
              final plan = _planPriority(
                b.key.data,
              ).compareTo(_planPriority(a.key.data));
              return plan != 0 ? plan : b.value.compareTo(a.value);
            });

      // 💡 おすすめが0人で、自分でタブを選んだのでなければ「ユーザー」タブに切り替える
      if (scored.isEmpty && !_isManualSelection) {
        _selectedTab = 'all';
        _loading = false;
        _reload();
        return;
      }

      _hasMore = false;
      _addResults(scored.map((e) => e.key).toList());
    } catch (e) {
      debugPrint('おすすめ取得エラー: $e');
      if (req == _requestId) _loadFailed = true;
    } finally {
      if (mounted && req == _requestId) setState(() => _loading = false);
    }
  }

  // ==========================================================================
  // 画面
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    if (_myId.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Text(
            'ログイン情報の確認中です。しばらくしてから再度お試しください。',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              _buildTabButton('ユーザー', 'all'),
              const SizedBox(width: 12),
              _buildTabButton('おすすめ', 'recommend'),
              const Spacer(),
              const Text(
                'Frendy',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: Icon(_isTwoColumn ? Icons.view_agenda : Icons.grid_view),
                onPressed: () => setState(() => _isTwoColumn = !_isTwoColumn),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_initializing) return const Center(child: CircularProgressIndicator());
    if (_initFailed) {
      return _buildRetry('読み込みに失敗しました', _init);
    }
    if (_results.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_loadFailed) return _buildRetry('読み込みに失敗しました', _reload);
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 160),
            Center(
              child: Text(
                '見つかりませんでした',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            ),
          ],
        ),
      );
    }

    final int footer = (_loading || _loadFailed || _hasMore) ? 1 : 0;

    final Widget list = _isTwoColumn
        ? GridView.builder(
            controller: _gridController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.65,
            ),
            itemCount: _results.length + footer,
            itemBuilder: (context, index) {
              if (index >= _results.length) return _buildFooter();
              final c = _results[index];
              return _buildModernUserCard(context, userId: c.id, data: c.data);
            },
          )
        : ListView.builder(
            controller: _listController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _results.length + footer,
            itemBuilder: (context, index) {
              if (index >= _results.length) return _buildFooter();
              final c = _results[index];
              return _buildOneColumnCard(context, userId: c.id, data: c.data);
            },
          );

    return RefreshIndicator(onRefresh: () async => _reload(), child: list);
  }

  Widget _buildFooter() {
    if (_loadFailed) {
      return Center(
        child: TextButton(
          onPressed: () {
            setState(() => _loadFailed = false);
            _loadMore();
          },
          child: const Text('再読み込み'),
        ),
      );
    }
    if (_hasMore && !_loading && _selectedTab == 'all') {
      // 画面が埋まらず、スクロールできないときのために自動で続きを読む
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildRetry(String message, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('再読み込み')),
        ],
      ),
    );
  }

  void _openProfile(String userId, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileDetailScreen(userData: data, userId: userId),
      ),
    );
  }

  // 1カラム（リスト形式）用のカード
  Widget _buildOneColumnCard(
    BuildContext context, {
    required String userId,
    required Map<String, dynamic> data,
  }) {
    final String name = _str(data, 'name', '名前なし');
    final int ageNum = _ageOf(data);
    final String age = ageNum > 0 ? '$ageNum' : '--';
    final String gender = _str(data, 'gender', '未設定');
    final String hobby = _str(data, 'hobby', '未設定');
    final String recentInterest = _str(data, 'recentInterest', '未設定');
    final String target = _str(data, 'idealFriend', '未設定');
    final String? imageUrl = _firstImageUrl(data);

    final IconData genderIcon = gender == '男性'
        ? Icons.male
        : (gender == '女性' ? Icons.female : Icons.transgender);
    final Color genderColor = gender == '男性'
        ? Colors.blue
        : (gender == '女性' ? Colors.pink : Colors.purple);

    final int cacheWidth =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () => _openProfile(userId, data),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 280,
              width: double.infinity,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: cacheWidth,
                      placeholder: (_, __) => Container(color: Colors.grey[50]),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[100],
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: const Icon(
                        Icons.person,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$age歳',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                      if (gender != '未設定') ...[
                        const SizedBox(width: 4),
                        Icon(genderIcon, color: genderColor, size: 20),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle('好きなこと（趣味）'),
                  _buildBodyText(hobby),
                  const SizedBox(height: 16),
                  _buildSectionTitle('最近特にハマってること'),
                  _buildBodyText(recentInterest),
                  const SizedBox(height: 16),
                  _buildSectionTitle('どんな友達を作りたい？'),
                  _buildBodyText(target),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBodyText(String text) {
    return Text(
      text,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.5),
    );
  }

  // 2カラム（グリッド形式）用のカード
  Widget _buildModernUserCard(
    BuildContext context, {
    required String userId,
    required Map<String, dynamic> data,
  }) {
    final String name = _str(data, 'name', '名前なし');
    final int ageNum = _ageOf(data);
    final String age = ageNum > 0 ? '$ageNum' : '--';
    final String location = _str(data, 'location', '未設定');
    final String recentInterest = _str(
      data,
      'recentInterest',
      '最近特にハマってることはまだありません。',
    );
    final String gender = _str(data, 'gender');
    final String? imageUrl = _firstImageUrl(data);

    final int cacheWidth =
        (MediaQuery.sizeOf(context).width /
                2 *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    return InkWell(
      onTap: () => _openProfile(userId, data),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          memCacheWidth: cacheWidth,
                          placeholder: (_, __) =>
                              Container(color: Colors.grey[50]),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[100],
                            child: const Icon(
                              Icons.broken_image,
                              size: 24,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey[100],
                          child: const Center(
                            child: Icon(
                              Icons.person,
                              size: 40,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$age歳',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (gender.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _buildGenderBadge(gender),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: AppColors.point,
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            location,
                            style: const TextStyle(fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        recentInterest,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderBadge(String gender) {
    final Color color = gender == '男性'
        ? Colors.blue
        : (gender == '女性' ? Colors.pink : Colors.purple);
    final IconData icon = gender == '男性'
        ? Icons.male
        : (gender == '女性' ? Icons.female : Icons.transgender);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 12),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.point,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, String tabValue) {
    final bool isSelected = _selectedTab == tabValue;
    return GestureDetector(
      onTap: () {
        if (_selectedTab == tabValue) return;
        setState(() {
          _isManualSelection = true;
          _selectedTab = tabValue;
        });
        _reload();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black87 : Colors.black38,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            height: 2,
            width: 24,
            color: isSelected ? AppColors.point : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              maxLength: 50,
              onChanged: (value) {
                _searchKeyword = value;
                _scheduleReload(const Duration(milliseconds: 500));
              },
              decoration: InputDecoration(
                hintText: 'キーワードで検索',
                counterText: '',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.grey,
                  size: 22,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.tune, color: Colors.blueGrey),
              onPressed: () => _showFilterSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              height: MediaQuery.sizeOf(sheetContext).height * 0.85,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '検索フィルター',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // --- タグ ---
                    const Text(
                      'タグで絞り込む',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      children: AppTags.allTags.map((tag) {
                        final isSelected = _selectedTags.contains(tag);
                        return FilterChip(
                          label: Text(tag),
                          selected: isSelected,
                          selectedColor: AppColors.point.withValues(alpha: 0.3),
                          onSelected: (val) {
                            setSheetState(() {
                              if (val) {
                                if (!_selectedTags.contains(tag))
                                  _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                            _scheduleReload();
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),

                    // --- 性別 ---
                    const Text(
                      '性別',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['すべて', '男性', '女性', 'その他']
                          .map(
                            (g) => ChoiceChip(
                              label: Text(g),
                              selected: _selectedGender == g,
                              selectedColor: AppColors.point.withValues(
                                alpha: 0.2,
                              ),
                              onSelected: (_) {
                                setSheetState(() => _selectedGender = g);
                                _scheduleReload();
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 24),

                    // --- 年齢範囲 ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '年齢範囲',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$_minAge歳 〜 $_maxAge歳',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.point,
                          ),
                        ),
                      ],
                    ),
                    RangeSlider(
                      values: RangeValues(
                        _minAge.toDouble(),
                        _maxAge.toDouble(),
                      ),
                      min: 18,
                      max: 80,
                      divisions: 62,
                      activeColor: AppColors.point,
                      onChanged: (RangeValues values) {
                        setSheetState(() {
                          _minAge = values.start.round();
                          _maxAge = values.end.round();
                        });
                        _scheduleReload(const Duration(milliseconds: 600));
                      },
                    ),
                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                        ),
                        child: const Text(
                          '適用する',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
