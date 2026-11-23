import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/profile/profile_setup_screen.dart';
import 'package:matching_app/screens/subscription/subscription_screen.dart';
import 'package:matching_app/screens/talk/talk_screen.dart' hide AppColors;

// ============================================================================
// プロフィール詳細
//
// 💡 いいね・足跡・ブロック・トーク開始は、すべて Cloud Functions 経由で行う。
//    相手のデータをアプリから直接書き換えないことで、なりすましや
//    「上限の数字を自分で0に戻す」といった不正を防ぐ。
// ============================================================================

const Duration _kNetworkTimeout = Duration(seconds: 20);
const String _kFunctionsRegion = 'asia-northeast1';

FirebaseFirestore get _db => FirebaseFirestore.instance;

HttpsCallable _callable(String name) => FirebaseFunctions.instanceFor(
  region: _kFunctionsRegion,
).httpsCallable(name, options: HttpsCallableOptions(timeout: _kNetworkTimeout));

String _errorMessage(Object e, String fallback) {
  if (e is FirebaseFunctionsException) {
    switch (e.code) {
      case 'failed-precondition':
      case 'not-found':
      case 'invalid-argument':
      case 'permission-denied':
      case 'resource-exhausted':
        return e.message ?? fallback;
      case 'unauthenticated':
        return 'ログインの有効期限が切れました。再度ログインしてください。';
      case 'deadline-exceeded':
      case 'unavailable':
        return '通信状況を確認して、もう一度お試しください。';
    }
  }
  if (e is TimeoutException) return '通信がタイムアウトしました。もう一度お試しください。';
  return fallback;
}

class ProfileDetailScreen extends StatefulWidget {
  final Map<String, dynamic> userData; // 相手の公開プロフィール
  final String userId; // 相手のID

  const ProfileDetailScreen({
    super.key,
    required this.userData,
    required this.userId,
  });

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late final String _myId;
  late final bool _isMyProfile;

  // --- サーバーから受け取る状態 ---
  bool _loadingState = true;
  bool _peerExists = true;
  bool _iBlockedPeer = false;
  bool _canInteract = true;
  bool _hasChatHistory = false;
  bool _nameMissing = false;
  int? _monthlyLimit; // null = 無制限
  int _monthlyUsed = 0;

  // --- 操作中フラグ（連打防止） ---
  bool _startingTalk = false;
  bool _togglingLike = false;
  bool _blockBusy = false;

  // --- いいね状態 ---
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _likeStream;
  bool? _optimisticLiked; // ボタンを押した直後の表示用

  bool get _isBlockedRelationship => !_canInteract;

  bool get _isMonthlyLimitReached =>
      _monthlyLimit != null &&
      !_hasChatHistory &&
      _monthlyUsed >= _monthlyLimit!;

  String get _peerName {
    final n = widget.userData['name'];
    return n is String && n.trim().isNotEmpty ? n : 'このユーザー';
  }

  // 💡 https の画像だけを使う（不正な値でクラッシュしないように）
  List<String> get _imageUrls {
    final raw = widget.userData['imageUrls'];
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .where((u) => u.startsWith('https://'))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _isMyProfile = _myId.isEmpty || widget.userId == _myId;

    if (_isMyProfile) {
      _loadingState = false;
      return;
    }

    _likeStream = _db
        .collection('users')
        .doc(_myId)
        .collection('likes')
        .doc(widget.userId)
        .snapshots();

    _recordFootprint();
    _loadState();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.redAccent : null,
        ),
      );
  }

  // ==========================================================================
  // サーバーとのやり取り
  // ==========================================================================

  // 💡 足跡はサーバー側で「同じ相手には10分に1回まで」に制限している
  void _recordFootprint() {
    _callable('recordFootprint').call({'peerId': widget.userId}).catchError((
      e,
    ) {
      debugPrint('足跡の記録に失敗しました: $e');
      return null;
    });
  }

  Future<void> _loadState() async {
    try {
      final res = await _callable(
        'getProfileState',
      ).call({'peerId': widget.userId});
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(() {
        _peerExists = d['peerExists'] == true;
        _iBlockedPeer = d['iBlocked'] == true;
        _canInteract = d['canInteract'] == true;
        _hasChatHistory = d['hasChatHistory'] == true;
        _nameMissing = d['nameMissing'] == true;
        final limit = d['monthlyLimit'];
        _monthlyLimit = limit is num ? limit.toInt() : null;
        final used = d['monthlyUsed'];
        _monthlyUsed = used is num ? used.toInt() : 0;
        _loadingState = false;
      });
    } catch (e) {
      debugPrint('プロフィール状態の取得エラー: $e');
      if (!mounted) return;
      // 取得できなかった場合は、ボタンを押したときにサーバーで判定させる
      setState(() => _loadingState = false);
    }
  }

  // --- トーク開始 ---
  Future<void> _startTalk() async {
    if (_startingTalk) return;
    setState(() => _startingTalk = true);

    try {
      final res = await _callable('startTalk').call({'peerId': widget.userId});
      final d = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(() {
        if (d['consumed'] == true) _monthlyUsed += 1;
        _hasChatHistory = true;
      });
      _navigateToTalkScreen();
    } on FirebaseFunctionsException catch (e) {
      debugPrint('トーク開始エラー: ${e.code} ${e.message}');
      if (!mounted) return;
      if (e.code == 'resource-exhausted') {
        final details = e.details;
        final limit = details is Map && details['limit'] is num
            ? (details['limit'] as num).toInt()
            : (_monthlyLimit ?? 0);
        setState(() => _monthlyUsed = limit);
        _showLimitReachedDialog(limit);
      } else {
        _toast(_errorMessage(e, 'トークを開始できませんでした。'), isError: true);
        if (e.code == 'failed-precondition') _loadState(); // 状態が変わった可能性
      }
    } catch (e) {
      debugPrint('トーク開始エラー: $e');
      _toast(_errorMessage(e, 'トークを開始できませんでした。'), isError: true);
    } finally {
      if (mounted) setState(() => _startingTalk = false);
    }
  }

  void _navigateToTalkScreen() {
    final images = _imageUrls;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TalkScreen(
          userName: _peerName,
          peerId: widget.userId,
          peerImageUrl: images.isNotEmpty ? images.first : '',
        ),
      ),
    );
  }

  // --- いいね ---
  Future<void> _toggleLike(bool currentlyLiked) async {
    if (_togglingLike || _isBlockedRelationship) return;
    final bool next = !currentlyLiked;

    setState(() {
      _togglingLike = true;
      _optimisticLiked = next; // 押した瞬間に見た目を切り替える
    });

    try {
      await _callable(
        next ? 'likeUser' : 'unlikeUser',
      ).call({'peerId': widget.userId});
    } catch (e) {
      debugPrint('いいね処理エラー: $e');
      if (mounted) setState(() => _optimisticLiked = null); // 元に戻す
      _toast(_errorMessage(e, 'いいねの処理に失敗しました。'), isError: true);
    } finally {
      if (mounted) setState(() => _togglingLike = false);
    }
  }

  // --- ブロック／解除 ---
  Future<void> _toggleBlock({required bool unblock}) async {
    if (_blockBusy) return;
    setState(() => _blockBusy = true);

    try {
      await _callable(
        unblock ? 'unblockUser' : 'blockUser',
      ).call({'peerId': widget.userId});
      if (!mounted) return;
      setState(() {
        _iBlockedPeer = !unblock;
        if (!unblock) {
          _canInteract = false;
          _optimisticLiked = false; // ブロックでいいねも消える
        }
      });
      _toast(unblock ? 'ブロックを解除しました' : 'ブロックしました');
      if (unblock) _loadState(); // 相手側のブロック状況も含めて取り直す
    } catch (e) {
      debugPrint('ブロック処理エラー: $e');
      _toast(_errorMessage(e, '操作に失敗しました。もう一度お試しください。'), isError: true);
    } finally {
      if (mounted) setState(() => _blockBusy = false);
    }
  }

  // ==========================================================================
  // ダイアログ・シート
  // ==========================================================================
  void _showLimitReachedDialog(int limit) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '今月のトーク開始上限に達しました',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          '現在のプランでは、新しく話しかけられるのは月に$limit人までです。今月はすでに上限に達しています。\n\n'
          '『ライトプラン』や『スタンダードプラン』に登録すると、月あたりの上限が増えたり、上限なしで会話できるようになります。',
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              '閉じる',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.point,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
              // 💡 プラン変更後に戻ってきたら、上限を取り直す
              if (mounted) _loadState();
            },
            child: const Text(
              'プラン一覧を見る',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileIncompleteDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'プロフィールを設定してください',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          'トークを始めるには、まずプロフィールを設定する必要があります。プロフィール編集画面から設定してください。',
          style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              '閉じる',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.point,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
              );
              if (mounted) _loadState();
            },
            child: const Text(
              'プロフィールを編集する',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportDialog() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _ReportDialog(
        reporterId: _myId,
        peerId: widget.userId,
        peerName: _peerName,
      ),
    );
    if (sent == true) _toast('報告ありがとうございます。運営で確認いたします。');
  }

  void _showBlockConfirmation() {
    final bool unblock = _iBlockedPeer;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          unblock ? '$_peerName さんのブロックを解除しますか？' : '$_peerName さんをブロック',
        ),
        content: Text(
          unblock
              ? 'ブロックを解除すると、再びお互いのリストに表示されるようになります。'
              : 'ブロックすると、お互いのリストに表示されなくなり、メッセージのやり取りもできなくなります。よろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _toggleBlock(unblock: unblock);
            },
            child: Text(
              unblock ? '解除する' : 'ブロックする',
              style: TextStyle(
                color: unblock ? null : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreActionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.report_problem_outlined,
                  color: Colors.orange,
                ),
                title: const Text('通報する'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showReportDialog();
                },
              ),
              ListTile(
                leading: Icon(
                  _iBlockedPeer ? Icons.person_add_alt : Icons.block,
                  color: Colors.black87,
                ),
                title: Text(_iBlockedPeer ? 'ブロックを解除する' : 'ブロックする'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showBlockConfirmation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // 画面
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final int cacheSize =
        (screenWidth * MediaQuery.of(context).devicePixelRatio).round();

    final data = widget.userData;
    final imageUrls = _imageUrls;
    final Map<String, dynamic> valuesData = data['values'] is Map
        ? Map<String, dynamic>.from(data['values'] as Map)
        : {};

    final List<Widget> basicInfoTiles = [
      if (_hasValue(data['gender']))
        _buildDetailTile(Icons.wc, '性別', data['gender']),
      if (_hasValue(data['location']))
        _buildDetailTile(Icons.location_on, '居住地', data['location']),
      if (_hasValue(data['school']))
        _buildDetailTile(Icons.school, '学校', data['school']),
      if (_hasValue(data['work']))
        _buildDetailTile(Icons.work, '職業', data['work']),
    ];

    final tags = data['tags'] is List ? (data['tags'] as List) : const [];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          data['name'] is String ? data['name'] as String : '',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          if (!_isMyProfile)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _blockBusy ? null : _showMoreActionsSheet,
              tooltip: 'その他の操作',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 画像
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: screenWidth,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: imageUrls.isEmpty ? 1 : imageUrls.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) {
                      if (imageUrls.isEmpty) {
                        return Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.person,
                            size: 100,
                            color: Colors.grey,
                          ),
                        );
                      }
                      return CachedNetworkImage(
                        imageUrl: imageUrls[index],
                        fit: BoxFit.cover,
                        memCacheWidth: cacheSize,
                        memCacheHeight: cacheSize,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[100],
                          child: const Center(
                            child: SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.point,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[200],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                size: 50,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                '画像を読み込めませんでした',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (imageUrls.length > 1)
                  Positioned(
                    bottom: 35,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        imageUrls.length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index
                                ? AppColors.point
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // 2. 詳細
            Container(
              transform: Matrix4.translationValues(0, -20, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isMyProfile &&
                      !_loadingState &&
                      (!_peerExists || _isBlockedRelationship))
                    _buildNotice(
                      !_peerExists
                          ? 'このユーザーは退会しました'
                          : (_iBlockedPeer
                                ? 'このユーザーをブロックしています'
                                : 'このユーザーとはやり取りできません'),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.userId),
                            );
                            _toast(
                              'ID: ${_shortId(widget.userId)}... をコピーしました',
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'ID: ${_shortId(widget.userId)}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                data['name'] is String
                                    ? data['name'] as String
                                    : '',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_hasValue(data['age'])) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${data['age']})',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                            if (!_isMyProfile) _buildLikeButton(),
                            if (_hasValue(data['gender'])) ...[
                              const SizedBox(width: 8),
                              _GenderBadge(gender: data['gender'].toString()),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 6.0,
                        children: tags
                            .map((t) => _buildTag(t.toString(), AppColors.tag))
                            .toList(),
                      ),
                    ),
                  if (_hasValue(data['hobby'])) ...[
                    _buildSectionTitle('好きなこと・趣味'),
                    _buildContent(data['hobby']),
                  ],
                  if (_hasValue(data['recentInterest'])) ...[
                    _buildSectionTitle('最近特にハマってること'),
                    _buildContent(data['recentInterest']),
                  ],
                  if (_hasValue(data['idealFriend'])) ...[
                    _buildSectionTitle('どんな友達を作りたい？'),
                    _buildContent(data['idealFriend']),
                  ],
                  if (_hasValue(data['holidayActivity'])) ...[
                    _buildSectionTitle('休日の過ごし方'),
                    _buildContent(data['holidayActivity']),
                  ],
                  if (_hasValue(data['ngThings'])) ...[
                    _buildSectionTitle('NGなこと・苦手なこと'),
                    _buildContent(data['ngThings']),
                  ],
                  if (basicInfoTiles.isNotEmpty) ...[
                    _buildSectionTitle('基本情報'),
                    _buildInfoContainer(basicInfoTiles),
                  ],
                  if (valuesData.isNotEmpty) ...[
                    _buildSectionTitle('ライフスタイル・価値観シート'),
                    _buildInfoContainer(
                      valuesData.entries
                          .map(
                            (e) => _buildDetailTile(
                              Icons.check_circle_outline,
                              e.key,
                              e.value,
                              isValueSheet: true,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _isMyProfile ? null : _buildTalkBar(),
    );
  }

  Widget _buildNotice(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.block, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }

  // 💡 いいねボタン：自分の「いいねした」サブコレクションに相手がいるかで表示する
  Widget _buildLikeButton() {
    if (_likeStream == null || _isBlockedRelationship || !_peerExists) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _likeStream,
      builder: (context, snap) {
        final bool isLiked = _optimisticLiked ?? (snap.data?.exists ?? false);
        return Padding(
          padding: const EdgeInsets.only(left: 10),
          child: GestureDetector(
            onTap: _togglingLike ? null : () => _toggleLike(isLiked),
            child: Icon(
              isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              color: const Color(0xFFFF8A80),
              size: 24,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTalkBar() {
    final bool disabled = !_peerExists || _isBlockedRelationship;

    final String label = !_peerExists
        ? '利用できません'
        : _isBlockedRelationship
        ? '利用できません'
        : _nameMissing
        ? 'プロフィール未設定です'
        : _isMonthlyLimitReached
        ? '今月のトーク開始上限です'
        : 'トークする';

    final VoidCallback? onPressed = disabled || _startingTalk
        ? null
        : _nameMissing
        ? _showProfileIncompleteDialog
        : _isMonthlyLimitReached
        ? () => _showLimitReachedDialog(_monthlyLimit ?? 0)
        : _startTalk;

    final bool grey = disabled || _nameMissing || _isMonthlyLimitReached;

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 25, 15, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: _loadingState
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton.icon(
                    icon: _startingTalk
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                    label: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: grey
                          ? Colors.grey[400]
                          : AppColors.point,
                      disabledBackgroundColor: Colors.grey[400],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // --- ヘルパー ---
  bool _hasValue(dynamic value) {
    if (value == null) return false;
    final s = value.toString().trim();
    return s.isNotEmpty && s != '未設定' && s != '未入力';
  }

  String _shortId(String id) => id.length >= 8 ? id.substring(0, 8) : id;

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildContent(dynamic text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text.toString(),
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildInfoContainer(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        decoration: BoxDecoration(
          color: AppColors.gley,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildDetailTile(
    IconData icon,
    String label,
    dynamic value, {
    bool isValueSheet = false,
  }) {
    return ListTile(
      visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
      minVerticalPadding: 0,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: Colors.blueGrey, size: 20),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: AppColors.txt),
      ),
      subtitle: Text(
        value.toString(),
        style: TextStyle(
          fontSize: 15,
          fontWeight: isValueSheet ? FontWeight.bold : FontWeight.w500,
          color: isValueSheet ? AppColors.point : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 13, color: color)),
      backgroundColor: Colors.white,
      side: BorderSide(color: color, width: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

// ----------------------------------------------------------------------------
// 性別バッジ
// ----------------------------------------------------------------------------
class _GenderBadge extends StatelessWidget {
  const _GenderBadge({required this.gender});
  final String gender;

  @override
  Widget build(BuildContext context) {
    final Color base = gender == '男性'
        ? Colors.blue
        : (gender == '女性' ? Colors.pink : Colors.grey);
    final IconData icon = gender == '男性'
        ? Icons.male
        : (gender == '女性' ? Icons.female : Icons.transgender);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: base, size: 16),
    );
  }
}

// ----------------------------------------------------------------------------
// 通報ダイアログ（二重送信防止・同じ相手への連投防止つき）
// ----------------------------------------------------------------------------
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({
    required this.reporterId,
    required this.peerId,
    required this.peerName,
  });

  final String reporterId;
  final String peerId;
  final String peerName;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _controller.text.trim();
    if (reason.isEmpty || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _db
          .collection('reports')
          .doc('${widget.reporterId}_${widget.peerId}')
          .set({
            'reporterId': widget.reporterId,
            'reportedId': widget.peerId,
            'reason': reason,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(_kNetworkTimeout);
      if (mounted) Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      debugPrint('通報送信エラー: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.code == 'permission-denied'
            ? 'このユーザーは既に通報済みです。'
            : '通報の送信に失敗しました。もう一度お試しください。';
      });
    } catch (e) {
      debugPrint('通報送信エラー: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _errorMessage(e, '通報の送信に失敗しました。もう一度お試しください。');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        '${widget.peerName} さんを通報',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '不適切な言動や規約違反がありましたか？\n理由を詳しく教えてください。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            enabled: !_submitting,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: '通報理由を入力...',
              filled: true,
              fillColor: Colors.grey[50],
              contentPadding: const EdgeInsets.all(16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey[200]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.redAccent,
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text(
                  'キャンセル',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '通報する',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
