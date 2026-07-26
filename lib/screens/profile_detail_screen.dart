import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart'; // ★追加：高機能キャッシュ画像ライブラリ
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/talk_screen.dart' hide AppColors;
import 'package:matching_app/screens/subscription_screen.dart'; // 💡 追加：メンバーシップ画面へ遷移させるため

class ProfileDetailScreen extends StatefulWidget {
  final Map<String, dynamic> userData; // Firestoreからのデータ
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
  bool _isLiked = false;

  // 💡 プラン別制限用の変数群
  String _myPlan = 'free'; // 'free', 'light', 'standard', etc.
  int _monthlyNewTalkCount = 0; // 今月すでに使った新規トーク開始枠の数
  bool _hasChatHistoryWithThisPeer = false;
  bool _isLoadingLimits = true;

  @override
  void initState() {
    super.initState();
    _addFootprint();
    _checkLikedStatus();
    _loadUserPlanAndLimits();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- ヘルパー：有効な値があるかチェックするロジック ---
  bool _hasValue(dynamic value) {
    if (value == null ||
        value.toString().trim().isEmpty ||
        value.toString() == '未設定' ||
        value.toString() == '未入力') {
      return false;
    }
    return true;
  }

  // 💡 現在の年月を "2026-07" のような文字列で返す（月次リセット判定に使用）
  String _currentPeriodString() {
    final DateTime now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // ==========================================
  // 💡 プランと月次トーク開始枠を読み込むバックエンド処理
  // ==========================================
  Future<void> _loadUserPlanAndLimits() async {
    final String? myId = FirebaseAuth.instance.currentUser?.uid;
    if (myId == null) return;

    try {
      // 1. 自分の現在のプラン情報 & 月次カウンターを取得
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myId)
          .get();
      if (myDoc.exists) {
        final myData = myDoc.data() ?? {};
        _myPlan = myData['plan'] ?? 'free';

        // 💡 保存されている集計対象月と「今月」が違えば、表示上は0人扱いにする
        //    （実際のFirestore側のリセットは、次回消費時にトランザクションで行う）
        final String storedPeriod = myData['monthlyResetPeriod'] ?? '';
        final int storedCount = myData['monthlyNewTalkCount'] ?? 0;
        _monthlyNewTalkCount = (storedPeriod == _currentPeriodString())
            ? storedCount
            : 0;
      }

      // 2. このお相手との個別トーク履歴がすでに存在するかチェック
      final String chatRoomId = ([myId, widget.userId]..sort()).join("_");
      final roomDoc = await FirebaseFirestore.instance
          .collection('chat_rooms')
          .doc(chatRoomId)
          .get();
      if (roomDoc.exists) {
        final roomData = roomDoc.data();
        final String lastMessage = roomData?['lastMessage'] ?? '';
        _hasChatHistoryWithThisPeer = lastMessage.isNotEmpty;
      }

      if (mounted) {
        setState(() {
          _isLoadingLimits = false;
        });
      }
    } catch (e) {
      debugPrint("プラン制限情報読み込みエラー: $e");
      if (mounted) {
        setState(() {
          _isLoadingLimits = false;
        });
      }
    }
  }

  // 💡 現在のプランにおける「月あたりの新規トーク開始可能数」を返す
  //    フリー: 5人/月、ライト: 15人/月、それ以外: 無制限
  int _monthlyAllowedLimit() {
    if (_myPlan == 'free') return 5;
    if (_myPlan == 'light') return 15;
    return 9999;
  }

  // 💡 月次の新規トーク開始枠を1つ消費する（トランザクションで安全に処理）
  //    月が変わっていれば自動的にカウントを1から数え直す
  Future<bool> _tryConsumeMonthlySlot(String myId, int allowedLimit) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(myId);
    final String currentPeriod = _currentPeriodString();

    return FirebaseFirestore.instance.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(docRef);
      final data = snapshot.data() ?? {};
      final String storedPeriod = data['monthlyResetPeriod'] ?? '';
      final int storedCount = data['monthlyNewTalkCount'] ?? 0;

      // 保存されている月が今月と違えば、0人からカウントし直す（＝月次リセット）
      final int currentCount = (storedPeriod == currentPeriod)
          ? storedCount
          : 0;

      if (currentCount >= allowedLimit) {
        return false; // 上限到達につき消費できない
      }

      transaction.set(docRef, {
        'monthlyNewTalkCount': currentCount + 1,
        'monthlyResetPeriod': currentPeriod,
      }, SetOptions(merge: true));

      return true;
    });
  }

  // ==========================================
  // 💡 新規トーク開始の可否チェック＆遷移（月次カウンター消費方式）
  // ==========================================
  Future<void> _handleTalkTransition() async {
    final String? myId = FirebaseAuth.instance.currentUser?.uid;
    if (myId == null) return;

    // 1. 既にメッセージ履歴が存在するトークルーム、または自分自身のプロフィールなら無制限
    if (_hasChatHistoryWithThisPeer || widget.userId == myId) {
      _navigateToTalkScreen();
      return;
    }

    final int allowedLimit = _monthlyAllowedLimit();

    // 無制限プラン（スタンダード以上）はカウンター消費なしでそのまま遷移
    if (allowedLimit >= 9999) {
      _navigateToTalkScreen();
      return;
    }

    // 2. 月次の新規トーク開始枠を1つ消費できるか試みる（トランザクションで安全に判定）
    final bool consumed = await _tryConsumeMonthlySlot(myId, allowedLimit);
    if (!mounted) return;

    if (consumed) {
      setState(() {
        _monthlyNewTalkCount += 1; // 画面上の表示もその場で更新
      });
      _navigateToTalkScreen();
    } else {
      _showLimitReachedDialog(allowedLimit);
    }
  }

  // 枠上限に達した時の誘導アラート
  void _showLimitReachedDialog(int limit) {
    String title = "今月のトーク開始上限に達しました";
    String content =
        "現在のプランでは、新しく話しかけられるのは月に$limit人までです。今月はすでに上限に達しています。\n\n『ライトプラン』や『スタンダードプラン』に登録すると、月あたりの上限が増えたり、上限なしで会話できるようになります。";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          content,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
            onPressed: () {
              Navigator.pop(context); // アラートを閉じる
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
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

  void _navigateToTalkScreen() {
    final data = widget.userData;
    final String imageUrl = (data['imageUrls'] as List? ?? []).isNotEmpty
        ? data['imageUrls'][0]
        : 'https://via.placeholder.com/150';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TalkScreen(
          userName: data['name'] ?? '不明',
          peerId: widget.userId,
          peerImageUrl: imageUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final bool isMyProfile = widget.userId == currentUserId;

    final double screenWidth = MediaQuery.of(context).size.width;
    final int cacheSize =
        (screenWidth * MediaQuery.of(context).devicePixelRatio).round();

    const Color accentPink = Color(0xFFFF8A80);
    final data = widget.userData;
    final List<dynamic> imageUrls = data['imageUrls'] ?? [];
    final Map<String, dynamic> valuesData = Map<String, dynamic>.from(
      data['values'] ?? {},
    );

    // --- セクションごとの表示判定用リスト作成 ---
    // 💡 不要な項目（資格・部活・サークルなど）を排除し、本当に必要な項目にスリム化！
    final List<Widget> basicInfoTiles = [];
    if (_hasValue(data['gender'])) {
      basicInfoTiles.add(_buildDetailTile(Icons.wc, '性別', data['gender']));
    }
    if (_hasValue(data['location'])) {
      basicInfoTiles.add(
        _buildDetailTile(Icons.location_on, '居住地', data['location']),
      );
    }
    if (_hasValue(data['school'])) {
      basicInfoTiles.add(_buildDetailTile(Icons.school, '学校', data['school']));
    }
    if (_hasValue(data['work'])) {
      basicInfoTiles.add(_buildDetailTile(Icons.work, '職業', data['work']));
    }

    // 💡 今月の新規トーク開始枠の上限に達しているかどうかを判定
    //    （フリー・ライトのように上限が設定されているプランが対象。無制限プランは常にfalse）
    final int _allowedLimit = _monthlyAllowedLimit();
    final bool isMonthlyLimitReached =
        _allowedLimit < 9999 &&
        !_hasChatHistoryWithThisPeer &&
        _monthlyNewTalkCount >= _allowedLimit;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          data['name'] ?? '',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 画像エリア（キャッシュ画像最適化）
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
                          child: Center(
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

            // 2. プロフィール詳細エリア
            Container(
              transform: Matrix4.translationValues(0, -20, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.userId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final peerData = snapshot.hasData
                      ? snapshot.data!.data() as Map<String, dynamic>
                      : data;
                  final int likeCount = peerData['likeCount'] ?? 0;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: widget.userId),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'ID: ${widget.userId.substring(0, 8)}... をコピーしました',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'ID: ${widget.userId.substring(0, 8)}',
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${data['name'] ?? ''}${_hasValue(data['age']) ? ' (${data['age']})' : ''}',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_hasValue(data['gender'])) ...[
                                  const SizedBox(width: 8),
                                  Builder(
                                    builder: (context) {
                                      final gender = data['gender'];
                                      final Color bgColor = gender == '男性'
                                          ? Colors.blue.withOpacity(0.15)
                                          : (gender == '女性'
                                                ? Colors.pink.withOpacity(0.15)
                                                : Colors.grey.withOpacity(
                                                    0.15,
                                                  ));
                                      final Color iconColor = gender == '男性'
                                          ? Colors.blue
                                          : (gender == '女性'
                                                ? Colors.pink
                                                : Colors.grey);
                                      final IconData iconData = gender == '男性'
                                          ? Icons.male
                                          : (gender == '女性'
                                                ? Icons.female
                                                : Icons.transgender);

                                      return Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: bgColor,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          iconData,
                                          color: iconColor,
                                          size: 16,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                                IconButton(
                                  onPressed: _toggleLike,
                                  icon: Icon(
                                    _isLiked
                                        ? Icons.thumb_up_alt
                                        : Icons.thumb_up_alt_outlined,
                                    color: accentPink,
                                    size: 28,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.thumb_up,
                                  color: Colors.pink,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${likeCount < 0 ? 0 : likeCount} いいね',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (data['tags'] != null &&
                          (data['tags'] as List).isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Wrap(
                            spacing: 6.0,
                            children: (data['tags'] as List)
                                .map(
                                  (tag) =>
                                      _buildTag(tag.toString(), AppColors.tag),
                                )
                                .toList(),
                          ),
                        ),
                      if (_hasValue(data['bio'])) ...[
                        _buildSectionTitle('自己紹介'),
                        _buildContent(data['bio']),
                      ],

                      // 💡 趣味・好きなもの（必須項目・統合化に合わせてテキスト形式で美しく表示）
                      if (_hasValue(data['hobby'])) ...[
                        _buildSectionTitle('趣味・好きなもの'),
                        _buildContent(data['hobby']),
                      ],

                      if (_hasValue(data['hobbyDetail'])) ...[
                        _buildSectionTitle('趣味・好きなものの詳細'),
                        _buildContent(data['hobbyDetail']),
                      ],
                      if (_hasValue(data['idealFriend'])) ...[
                        _buildSectionTitle('どんな友達が欲しい？'),
                        _buildContent(data['idealFriend']),
                      ],

                      // 基本情報 (性別、居住地、学校、職業)
                      if (basicInfoTiles.isNotEmpty) ...[
                        _buildSectionTitle('基本情報'),
                        _buildInfoContainer(basicInfoTiles),
                      ],

                      if (_hasValue(data['favoriteFood']) ||
                          _hasValue(data['dislikeFood']) ||
                          _hasValue(data['artist']) ||
                          _hasValue(data['game']) ||
                          _hasValue(data['anime'])) ...[
                        _buildSectionTitle('その他プロフィール'),
                        _buildInfoContainer([
                          if (_hasValue(data['favoriteFood']))
                            _buildDetailTile(
                              Icons.restaurant,
                              '好きな食べ物',
                              data['favoriteFood'],
                            ),
                          if (_hasValue(data['dislikeFood']))
                            _buildDetailTile(
                              Icons.no_food,
                              '苦手な食べ物',
                              data['dislikeFood'],
                            ),
                          if (_hasValue(data['artist']))
                            _buildDetailTile(
                              Icons.music_note,
                              '好きなアーティスト',
                              data['artist'],
                            ),
                          if (_hasValue(data['game']))
                            _buildDetailTile(
                              Icons.sports_esports,
                              '好きなゲーム',
                              data['game'],
                            ),
                          if (_hasValue(data['anime']))
                            _buildDetailTile(
                              Icons.movie,
                              '好きなアニメ・漫画',
                              data['anime'],
                            ),
                        ]),
                      ],

                      // 💡 ライフスタイル・価値観シート
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(15, 25, 15, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              // 💡 情報をロード中はインジケータ等を表示、完了したらプラン別制限判定付きのボタンを表示
              child: _isLoadingLimits
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.send, color: Colors.white),
                      label: Text(
                        isMonthlyLimitReached ? '今月のトーク開始上限です' : 'トークする',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      // 💡 1. 自分のプロフィールならボタン無効
                      // 💡 2. 新規相手で今月の上限に達している場合はボタンを完全に無効化（グレーアウト）
                      onPressed: isMyProfile
                          ? null
                          : (isMonthlyLimitReached
                                ? () =>
                                      _showLimitReachedDialog(
                                        _allowedLimit,
                                      ) // タップ時にプラン案内ダイアログを表示
                                : _handleTalkTransition), // 正常時
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isMonthlyLimitReached
                            ? Colors.grey[400]
                            : AppColors.point,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // --- ヘルパー関数 ---
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
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
          color: isValueSheet
              ? AppColors.point
              : Colors.black87, // 💡 価値観シート用カラー調整
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

  // --- バックエンド処理 ---

  Future<void> _addFootprint() async {
    final String? myId = FirebaseAuth.instance.currentUser?.uid;
    final String peerId = widget.userId;
    if (myId == null || myId == peerId) return;

    try {
      final peerDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(peerId);
      await peerDoc.update({
        'footprints': FieldValue.arrayUnion([myId]),
      });
    } catch (e) {
      debugPrint('足跡の記録に失敗しました: $e');
    }
  }

  Future<void> _checkLikedStatus() async {
    final String? myId = FirebaseAuth.instance.currentUser?.uid;
    if (myId == null) return;

    final myDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .get();
    final List<dynamic> myLikes = myDoc.data()?['likes'] ?? [];

    if (mounted) {
      setState(() {
        _isLiked = myLikes.contains(widget.userId);
      });
    }
  }

  Future<void> _toggleLike() async {
    final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final String peerId = widget.userId;
    final String? currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final bool isMyProfile = widget.userId == currentUserId;
    if (myId.isEmpty || isMyProfile) return;

    setState(() => _isLiked = !_isLiked);

    final batch = FirebaseFirestore.instance.batch();
    final myDoc = FirebaseFirestore.instance.collection('users').doc(myId);
    final peerDoc = FirebaseFirestore.instance.collection('users').doc(peerId);

    if (_isLiked) {
      batch.update(myDoc, {
        'likes': FieldValue.arrayUnion([peerId]),
      });
      batch.update(peerDoc, {
        'likedBy': FieldValue.arrayRemove([myId]),
        'likeCount': FieldValue.increment(-1),
      });
    } else {
      batch.update(myDoc, {
        'likes': FieldValue.arrayRemove([peerId]),
      });
      batch.update(peerDoc, {
        'likedBy': FieldValue.arrayRemove([myId]),
        'likeCount': FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }
}
