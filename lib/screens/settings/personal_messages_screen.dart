import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:matching_app/constants/app_colors.dart';

// ============================================================================
// 運営からのメッセージ（自分あての個別メッセージ）
//
// 保存場所：users/{自分}/admin_inbox/{メッセージID}
//   title     : 件名（文字列）
//   body      : 本文（文字列）
//   createdAt : 送った日時（タイムスタンプ）
//   read      : 読んだか（true / false）
//
// 💡 セキュリティ（firestore.rules）
//  ・読めるのは本人だけ。書けるのは運営（isAdmin）だけ
//  ・本人ができる変更は「read を true にする（既読にする）」だけ
//
// 💡 5万人規模：自分あてのメッセージだけを、新しい順に20件ずつ読み込む
//
// ※ 全員あての「運営からのお知らせ」は、これまでどおりホーム画面に表示される
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const int _kPageSize = 20;
const int _kMaxMessages = 200;

CollectionReference<Map<String, dynamic>>? _inboxRef() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('admin_inbox');
}

// 💡 未読の件数を数える（アプリ設定のメニューに表示する用。最大20件まで数える）
Stream<int> personalMessagesUnreadCount() {
  final ref = _inboxRef();
  if (ref == null) return Stream.value(0);
  return ref
      .where('read', isEqualTo: false)
      .limit(20)
      .snapshots()
      .map((snap) => snap.size)
      .handleError((Object e) => debugPrint('未読数の取得エラー: $e'));
}

class _PersonalMessage {
  _PersonalMessage({
    required this.ref,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final String title;
  final String body;
  final DateTime? createdAt;
  bool read;

  factory _PersonalMessage.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    final rawTitle = d['title'];
    final rawBody = d['body'];
    final rawDate = d['createdAt'];
    return _PersonalMessage(
      ref: doc.reference,
      title: rawTitle is String && rawTitle.trim().isNotEmpty
          ? rawTitle.trim()
          : '運営からのメッセージ',
      body: rawBody is String ? rawBody : '',
      createdAt: rawDate is Timestamp ? rawDate.toDate() : null,
      read: d['read'] == true,
    );
  }
}

class PersonalMessagesScreen extends StatefulWidget {
  const PersonalMessagesScreen({super.key});

  @override
  State<PersonalMessagesScreen> createState() => _PersonalMessagesScreenState();
}

class _PersonalMessagesScreenState extends State<PersonalMessagesScreen> {
  final ScrollController _scrollController = ScrollController();
  final DateFormat _dateFormat = DateFormat('yyyy/MM/dd HH:mm');

  final List<_PersonalMessage> _messages = [];
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
    final ref = _inboxRef();
    if (ref == null ||
        _loading ||
        !_hasMore ||
        _messages.length >= _kMaxMessages) {
      if (ref == null && mounted) setState(() => _firstLoadDone = true);
      return;
    }
    final req = _requestId;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });

    try {
      Query<Map<String, dynamic>> q = ref
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
        _messages.addAll(snap.docs.map(_PersonalMessage.fromDoc));
      });
    } catch (e) {
      debugPrint('運営からのメッセージ取得エラー: $e');
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

  // 開いたメッセージを既読にする（本人ができるのは read を true にすることだけ）
  Future<void> _markAsRead(_PersonalMessage m) async {
    if (m.read) return;
    setState(() => m.read = true);
    try {
      await m.ref.update({'read': true}).timeout(_kNetworkTimeout);
    } catch (e) {
      debugPrint('既読エラー: $e');
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
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 160),
            Icon(
              _loadFailed ? Icons.wifi_off : Icons.mark_email_read_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              _loadFailed
                  ? '読み込みに失敗しました。\n下に引っぱって再読み込みしてください'
                  : '運営からのメッセージはありません',
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
              color: m.read
                  ? Colors.white
                  : AppColors.point.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(color: Colors.grey[200]!, width: 1),
              ),
            ),
            child: ListTile(
              leading: Icon(
                m.read ? Icons.drafts_outlined : Icons.mail,
                color: m.read ? Colors.grey : AppColors.point,
              ),
              title: Text(
                m.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: m.read ? FontWeight.normal : FontWeight.bold,
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
              trailing: m.read
                  ? const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                      size: 20,
                    )
                  : Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
              onTap: () {
                _markAsRead(m);
                _showMessageDetail(m.title, m.body, dateStr);
              },
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
          // 💡 本文はただの文字として表示する（リンクとして開かない）。長押しでコピーできる
          child: SelectableText(
            body.isNotEmpty ? body : '本文はありません',
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

// ----------------------------------------------------------------------------
// 未読があるときに、アイコンの右上に赤い数字のバッジをつける部品
// 使い方：PersonalMessagesBadge(child: Icon(Icons.person))
// 💡 下のタブのアイコンなど、どこでも包むだけで使える。
//    中で未読数を監視する（自分の受信箱の未読を最大20件数えるだけ）
// ----------------------------------------------------------------------------
class PersonalMessagesBadge extends StatefulWidget {
  const PersonalMessagesBadge({super.key, required this.child});

  final Widget child;

  @override
  State<PersonalMessagesBadge> createState() => _PersonalMessagesBadgeState();
}

class _PersonalMessagesBadgeState extends State<PersonalMessagesBadge> {
  // 💡 Stream は一度だけ作る（再描画のたびに作り直さない）
  late final Stream<int> _unreadStream = personalMessagesUnreadCount();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Badge(
          isLabelVisible: count > 0,
          backgroundColor: Colors.red,
          label: Text(count >= 20 ? '20+' : '$count'),
          child: widget.child,
        );
      },
    );
  }
}
