import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ============================================================================
// 運営からのメッセージ（お知らせ一覧）
//
// 💡 5万人規模を想定した作り
//  ・以前は最大100件を「リアルタイム監視」していたため、開くたびに最大100件分の
//    読み取り料金がかかっていた（5万人が1回ずつ開くと最大500万件）。
//  ・お知らせはめったに変わらないので、リアルタイム監視をやめて、
//    新しい順に20件ずつ読み込む方式に変更（下に引っぱると最新に更新）。
//
// 💡 セキュリティ
//  ・お知らせを書けるのは運営だけ（セキュリティルールの admin_messages で isAdmin のみ）
//  ・本文はただの文字として表示する（リンクやHTMLとして解釈しない）
//  ・型が違うデータが入っていてもクラッシュしない
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const int _kPageSize = 20;
const int _kMaxMessages = 200; // さかのぼって読み込む上限

class _AdminMessage {
  const _AdminMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  factory _AdminMessage.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final rawTitle = d['title'];
    final rawBody = d['body'];
    final rawDate = d['createdAt'];
    return _AdminMessage(
      id: doc.id,
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : 'お知らせ',
      body: rawBody is String ? rawBody : '',
      createdAt: rawDate is Timestamp ? rawDate.toDate() : null,
    );
  }
}

class AdminMessagesScreen extends StatefulWidget {
  const AdminMessagesScreen({super.key});

  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen> {
  final ScrollController _scrollController = ScrollController();
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd HH:mm');

  final List<_AdminMessage> _messages = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadFailed = false;
  bool _firstLoadDone = false;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) _loadMore();
  }

  // 下に引っぱったとき：最初から読み直す
  Future<void> _refresh() async {
    _requestId++;
    setState(() {
      _messages.clear();
      _cursor = null;
      _hasMore = true;
      _loading = false;
      _loadFailed = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _messages.length >= _kMaxMessages) return;
    final req = _requestId;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('admin_messages')
          .orderBy('createdAt', descending: true)
          .limit(_kPageSize);
      final cursor = _cursor;
      if (cursor != null) q = q.startAfterDocument(cursor);

      final snap = await q.get().timeout(_kNetworkTimeout);
      if (req != _requestId || !mounted) return;

      setState(() {
        if (snap.docs.isNotEmpty) _cursor = snap.docs.last;
        _hasMore =
            snap.docs.length >= _kPageSize &&
            _messages.length + snap.docs.length < _kMaxMessages;
        _messages.addAll(snap.docs.map(_AdminMessage.fromDoc));
      });
    } catch (e) {
      debugPrint('お知らせ取得エラー: $e');
      if (req == _requestId && mounted) setState(() => _loadFailed = true);
    } finally {
      if (req == _requestId && mounted) {
        setState(() {
          _loading = false;
          _firstLoadDone = true;
        });
      }
    }
  }

  String _formatDate(DateTime? date) =>
      date == null ? '' : _dateFormat.format(date);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '運営からのメッセージ',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey[200], height: 1.0),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (!_firstLoadDone && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      // 💡 ダミーのお知らせは表示しない（実在しない公式情報になるため。Apple審査対策）
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Icon(
              _loadFailed ? Icons.wifi_off : Icons.mail_outline,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              _loadFailed
                  ? '読み込みに失敗しました。\n下に引っぱって再読み込みしてください'
                  : '現在、お知らせはありません',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final bool showFooter = _loading || _loadFailed || _hasMore;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: _messages.length + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _messages.length) return _buildFooter();

          final m = _messages[index];
          final dateStr = _formatDate(m.createdAt);

          return Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: ListTile(
              title: Text(
                m.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  dateStr,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.grey,
                size: 20,
              ),
              onTap: () => _showMessageDetail(m.title, m.body, dateStr),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    if (_loadFailed) {
      return Center(
        child: TextButton(onPressed: _loadMore, child: const Text('再読み込み')),
      );
    }
    if (!_loading && _hasMore) {
      // 画面が埋まらずスクロールできないときのために、自動で続きを読む
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    }
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  // 詳細ポップアップ
  void _showMessageDetail(String title, String body, String date) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              date,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          // 💡 長押しで文章をコピーできるようにする（お問い合わせ番号などを写しやすくする）
          child: SelectableText(
            body,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
            ),
          ),
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
}
