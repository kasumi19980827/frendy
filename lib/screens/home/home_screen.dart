import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:matching_app/constants/app_colors.dart';

const Duration _kNetworkTimeout = Duration(seconds: 15);
const String _kFunctionsRegion = 'asia-northeast1';

// 限定バッジの条件（index.ts の BADGE_RULES と必ずそろえること）
const int _kSilverBadgePeers = 5;
const int _kGoldBadgePeers = 10;
const Color _kSilverColor = Color(0xFF9E9E9E);
const Color _kGoldColor = Color(0xFFFFB300);

// 友達招待の条件（index.ts の INVITE_REDEEM_WINDOW_DAYS・INVITER_REWARD_LIMIT とそろえる）
const int _kInviteRedeemWindowDays = 7;
const int _kInviterRewardLimit = 3;

// 無料体験中のプラン（'light' または 'premium'。無料体験中でなければ null）
String? _trialPlan(Map<String, dynamic> data) {
  if (_trialDaysLeft(data) == null) return null;
  final plan = data['plan'];
  return plan is String ? plan : null;
}

// 無料体験の残り日数（無料体験中でなければ null）
int? _trialDaysLeft(Map<String, dynamic> data) {
  if (data['planSource'] != 'trial') return null;
  final expires = data['planExpiresAt'];
  if (expires is! Timestamp) return null;
  final diff = expires.toDate().difference(DateTime.now());
  if (diff.isNegative) return null;
  return (diff.inHours / 24).ceil();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ⚠️【提出前に必ず修正】App Store Connect の「App 情報」にある Apple ID（数字）に差し替える
  static const String _appStoreId = 'YOUR_APP_ID';

  bool _isExpanded = false;
  bool _showForm = false;
  bool _isSubmittingOpinion = false;

  final TextEditingController _opinionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // 💡 Stream は initState で一度だけ作る。
  //    build 内で作ると「もっと見る」やフォーム操作のたびに再購読して読み取りが増える
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _noticesStream;

  // 💡 限定バッジの進み具合を表示するため、自分のドキュメントを監視する（1件だけ）
  //    人数（messagedPeersCount）とバッジ（badge）はサーバーが書き込む
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _myStream;

  // 招待コードは一度取得したら使い回す
  Future<String>? _inviteCodeFuture;

  @override
  void initState() {
    super.initState();
    _noticesStream = FirebaseFirestore.instance
        .collection('admin_messages')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _myStream = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots();
    }
  }

  @override
  void dispose() {
    _opinionController.dispose();
    _scrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'ホーム',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- お知らせ ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.campaign, color: AppColors.point),
                    SizedBox(width: 8),
                    Text(
                      '運営からのお知らせ',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  child: Text(
                    _isExpanded ? '閉じる' : 'もっと見る',
                    style: const TextStyle(
                      color: AppColors.point,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildNoticesSection(),
            const SizedBox(height: 5),

            // --- ご意見フォーム ---
            const Row(
              children: [
                Icon(Icons.rate_review, color: AppColors.point),
                SizedBox(width: 8),
                Text(
                  '運営へのご意見・ご要望',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildOpinionForm(),
            const SizedBox(height: 18),

            // --- バナー ---
            _buildWelcomeTrialBanner(),
            _buildInviteBanner(),
            const SizedBox(height: 12),
            _buildStoreReviewBanner(),
            const SizedBox(height: 12),
            _buildBadgeBanner(),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // お知らせ
  // ==========================================================================
  Widget _buildNoticesSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _noticesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('お知らせ取得エラー: ${snapshot.error}');
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'お知らせの読み込みに失敗しました',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('お知らせはまだありません', style: TextStyle(color: Colors.grey)),
          );
        }

        final displayDocs = _isExpanded ? docs : docs.take(2).toList();

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _isExpanded ? 350 : 180),
          child: ListView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: _isExpanded
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: displayDocs.length,
            itemBuilder: (context, index) {
              final data = displayDocs[index].data();
              final title = data['title'] is String
                  ? data['title'] as String
                  : 'お知らせ';
              final body = data['body'] is String ? data['body'] as String : '';
              final createdAt = data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).toDate()
                  : null;
              final dateStr = createdAt == null
                  ? ''
                  : '${createdAt.year}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.day.toString().padLeft(2, '0')}';
              return _buildNoticeCard(dateStr, title, body);
            },
          ),
        );
      },
    );
  }

  Widget _buildNoticeCard(String date, String title, String body) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.info_outline, color: AppColors.point),
        title: Text(
          title,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          date,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        dense: true,
        onTap: () => _showNoticeDetail(title, body, date),
      ),
    );
  }

  void _showNoticeDetail(String title, String body, String date) {
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
          child: Text(
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

  // ==========================================================================
  // ご意見フォーム
  // ==========================================================================
  Widget _buildOpinionForm() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: !_showForm
          ? SizedBox(
              key: const ValueKey('button'),
              width: double.infinity,
              height: 54,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _showForm = true),
                icon: const Icon(Icons.edit, size: 18),
                label: const Text(
                  '意見を書く',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.point,
                  side: const BorderSide(color: AppColors.point),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          : Card(
              key: const ValueKey('form'),
              elevation: 0,
              color: Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _opinionController,
                      maxLines: 3,
                      maxLength: 500,
                      autofocus: true,
                      enabled: !_isSubmittingOpinion,
                      decoration: const InputDecoration(
                        hintText: '「こんな機能が欲しい！」など、お気軽にお書きください。',
                        hintStyle: TextStyle(fontSize: 13),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _isSubmittingOpinion
                              ? null
                              : () => setState(() => _showForm = false),
                          child: const Text(
                            'キャンセル',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: _isSubmittingOpinion
                              ? null
                              : _submitOpinion,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.point,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSubmittingOpinion
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '送信する',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // 💡 ご意見と「最後に送った時刻」を同時に書き込み、
  //    ルール側で「前回から60秒以上空いているか」を確認して連投（スパム）を防ぐ。
  //    名前は端末から送らず、運営側で userId から確認する（なりすまし防止）
  Future<void> _submitOpinion() async {
    final text = _opinionController.text.trim();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (text.isEmpty || _isSubmittingOpinion) return;
    if (uid == null) {
      _toast('ログインが必要です', isError: true);
      return;
    }

    setState(() => _isSubmittingOpinion = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      batch.set(db.collection('opinions').doc(), {
        'userId': uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.set(db.collection('rate_limits').doc(uid), {
        'lastOpinionAt': FieldValue.serverTimestamp(),
      });
      await batch.commit().timeout(_kNetworkTimeout);

      if (!mounted) return;
      _opinionController.clear();
      setState(() => _showForm = false);
      _toast('ご意見ありがとうございます！');
    } on FirebaseException catch (e) {
      debugPrint('意見送信エラー: $e');
      _toast(
        e.code == 'permission-denied'
            ? '続けて送信できません。1分ほど待ってからお試しください。'
            : '送信に失敗しました。もう一度お試しください。',
        isError: true,
      );
    } on TimeoutException {
      _toast('通信が不安定です。接続が回復すると送信されます。');
    } catch (e) {
      debugPrint('意見送信エラー: $e');
      _toast('送信に失敗しました。もう一度お試しください。', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmittingOpinion = false);
    }
  }

  // ==========================================================================
  // 友達招待
  // ==========================================================================
  Widget _buildInviteBanner() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _myStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        // 招待バナーには、プレミアムの無料体験中のときだけ残り日数を出す
        final days = _trialPlan(data) == 'premium'
            ? _trialDaysLeft(data)
            : null;
        return _buildInviteBannerBody(days);
      },
    );
  }

  // ==========================================================================
  // 新規登録の特典（はじめの1ヶ月はライトプランが無料）
  // 💡 ライトプランの無料体験中だけ表示する
  // ==========================================================================
  Widget _buildWelcomeTrialBanner() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _myStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        if (_trialPlan(data) != 'light') return const SizedBox.shrink();
        final days = _trialDaysLeft(data)!;
        final until = (data['planExpiresAt'] as Timestamp).toDate();

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: const Color(0xFFFF9800).withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.celebration_rounded,
                  color: Color(0xFFFF9800),
                  size: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ライトプラン無料体験中（あと$days日）',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'はじめの1ヶ月の特典です（${until.month}月${until.day}日まで）。'
                        '月15人までトークを始められて、足跡・いいねをくれた人も見られます。',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInviteBannerBody(int? trialDaysLeft) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.point.withValues(alpha: 0.8), AppColors.point],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '友達招待で2人とも1ヶ月プレミアム無料！',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trialDaysLeft != null
                      ? '🎉 プレミアム無料体験中（あと$trialDaysLeft日）'
                      : '友達が年齢確認を完了すると、あなたも友達も1ヶ月無料に！',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _showInviteDetails,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.point,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              '詳細',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // 💡 招待コードはサーバーで重複なく発行する。
  //    以前は「ユーザーIDの先頭6文字」を使っていたため、
  //    ① 5万人規模だと他人とコードが重なる可能性が高い
  //    ② ユーザーIDの一部が外部に漏れる
  //    という問題があった
  Future<String> _loadInviteCode() async {
    final res = await FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
        .httpsCallable(
          'getInviteCode',
          options: HttpsCallableOptions(timeout: _kNetworkTimeout),
        )
        .call();
    final data = Map<String, dynamic>.from(res.data as Map);
    final code = data['code'];
    if (code is! String || code.isEmpty) throw StateError('招待コードが空です');
    return code;
  }

  void _showInviteDetails() {
    _inviteCodeFuture ??= _loadInviteCode();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // 💡 招待コードの入力欄でキーボードが出ても隠れないよう、下に余白をとってスクロールできるようにする
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          child: _InviteSheet(
            codeFuture: _inviteCodeFuture!,
            onRetry: () {
              Navigator.pop(sheetContext);
              setState(() => _inviteCodeFuture = null);
              _showInviteDetails();
            },
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // ストアレビュー
  // ==========================================================================
  Widget _buildStoreReviewBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.pink.withValues(alpha: 0.1),
            AppColors.pink.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.pink.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite_rounded, color: AppColors.pink, size: 36),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Frendyの感想を教えてね！',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'レビューで応援いただけると、\n開発の励みになります！',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _handleStoreReviewTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.pink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text(
              '書く',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // 💡 ボタンから開く場合は requestReview ではなく openStoreListing を使う。
  //    requestReview は表示回数に上限（iOS は年3回）があり、
  //    押しても何も起きないことが多いため「ボタンが壊れている」ように見えてしまう
  Future<void> _handleStoreReviewTap() async {
    final bool isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    if (isIOS && _appStoreId == 'YOUR_APP_ID') {
      debugPrint('警告: _appStoreId が未設定です');
      _toast('現在準備中です。しばらくお待ちください。');
      return;
    }

    try {
      await InAppReview.instance.openStoreListing(
        appStoreId: isIOS ? _appStoreId : null,
      );
    } catch (e) {
      debugPrint('レビュー画面の表示エラー: $e');
      _toast('レビュー画面を開けませんでした。もう一度お試しください。', isError: true);
    }
  }

  // ==========================================================================
  // 限定バッジ（メッセージを送った人数でもらえる）
  // ==========================================================================
  Widget _buildBadgeBanner() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _myStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final rawCount = data['messagedPeersCount'];
        final int count = rawCount is num ? rawCount.toInt() : 0;
        final String badge = data['badge'] is String
            ? data['badge'] as String
            : '';

        final String subText;
        if (badge == 'gold' || count >= _kGoldBadgePeers) {
          subText = '金バッジ獲得済み！たくさんの出会いをありがとう🎉';
        } else if (badge == 'silver' || count >= _kSilverBadgePeers) {
          subText = '銀バッジ獲得済み！あと${_kGoldBadgePeers - count}人で金バッジ';
        } else {
          subText = 'あと${_kSilverBadgePeers - count}人で銀バッジ（今 $count人）';
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _kGoldColor.withValues(alpha: 0.15),
                _kSilverColor.withValues(alpha: 0.08),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _kGoldColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.military_tech_rounded,
                color: badge == 'silver' ? _kSilverColor : _kGoldColor,
                size: 40,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '5人にメッセージを送ると限定バッジプレゼント！',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subText,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => _showBadgeDetails(count, badge),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kGoldColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text(
                  '詳細',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBadgeDetails(int count, String badge) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _BadgeSheet(count: count, badge: badge),
    );
  }
}

// ----------------------------------------------------------------------------
// 招待コードのボトムシート
// ----------------------------------------------------------------------------
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.codeFuture, required this.onRetry});

  final Future<String> codeFuture;
  final VoidCallback onRetry;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  bool _copied = false;

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    // 💡 SnackBar はシートの裏に隠れて見えないため、シート内の表示で知らせる
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Icon(Icons.card_giftcard, color: AppColors.point, size: 48),
          const SizedBox(height: 16),
          const Text(
            '友達招待特典',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.point.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Column(
              children: [
                Text(
                  '🎁 1ヶ月プレミアム体験プレゼント',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.point,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '招待した友達が年齢確認を完了すると、あなたと友達のどちらも「プレミアムプラン」を1ヶ月間無料で楽しめます。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _copied ? 'コピーしました！' : '招待コードをタップしてコピー',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _copied ? AppColors.point : Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<String>(
            future: widget.codeFuture,
            builder: (context, snap) {
              if (snap.hasError) {
                debugPrint('招待コード取得エラー: ${snap.error}');
                return Column(
                  children: [
                    const Text(
                      '招待コードを取得できませんでした',
                      style: TextStyle(color: Colors.grey),
                    ),
                    TextButton(
                      onPressed: widget.onRetry,
                      child: const Text('再読み込み'),
                    ),
                  ],
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                );
              }

              final code = snap.data!;
              return InkWell(
                onTap: () => _copy(code),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.point.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          code,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            color: AppColors.point,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          color: AppColors.point,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '※ 友達には、登録してから$_kInviteRedeemWindowDays日以内に、このコードを入力してもらってください。\n'
            '※ あなたが受け取れる特典は、$_kInviterRewardLimit回（3ヶ月分）までです。\n'
            '※ すでにストアでプレミアムプランをご契約中の方には、特典はつきません。',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),
          const _RedeemSection(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[100],
                foregroundColor: Colors.black54,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                '閉じる',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// 招待コードを入力する欄（招待された人用）
// ----------------------------------------------------------------------------
class _RedeemSection extends StatefulWidget {
  const _RedeemSection();

  @override
  State<_RedeemSection> createState() => _RedeemSectionState();
}

class _RedeemSectionState extends State<_RedeemSection> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String _status =
      ''; // '' = 未入力 / 'pending' = 入力済み・年齢確認待ち / 'rewarded' = 受け取り済み
  String? _error;

  // 💡 入力できるのは登録から7日以内（最終的な判定はサーバーで行う）
  bool get _withinWindow {
    final created = FirebaseAuth.instance.currentUser?.metadata.creationTime;
    if (created == null) return false;
    return DateTime.now().difference(created).inDays < _kInviteRedeemWindowDays;
  }

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('invites')
          .doc(uid)
          .get()
          .timeout(_kNetworkTimeout);
      final status = doc.data()?['status'];
      if (mounted) {
        setState(() {
          _status = status is String ? status : '';
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('招待の状態取得エラー: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
          .httpsCallable(
            'redeemInviteCode',
            options: HttpsCallableOptions(timeout: _kNetworkTimeout),
          )
          .call({'code': code});
      final data = Map<String, dynamic>.from(res.data as Map);
      if (!mounted) return;
      setState(
        () => _status = data['status'] == 'rewarded' ? 'rewarded' : 'pending',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('招待コード入力エラー: ${e.code} ${e.message}');
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          'invalid-argument' ||
          'not-found' ||
          'already-exists' ||
          'failed-precondition' => e.message ?? '招待コードを確認してください',
          _ => '通信に失敗しました。もう一度お試しください',
        };
      });
    } catch (e) {
      debugPrint('招待コード入力エラー: $e');
      if (mounted) setState(() => _error = '通信に失敗しました。もう一度お試しください');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _statusBox(IconData icon, Color color, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 40);

    if (_status == 'rewarded') {
      return _statusBox(
        Icons.celebration,
        AppColors.point,
        '招待の特典を受け取りました！プレミアムプランをお楽しみください。',
      );
    }
    if (_status == 'pending') {
      return _statusBox(
        Icons.hourglass_top_rounded,
        Colors.orange,
        '招待コードは入力済みです。年齢確認が承認されると、あなたと招待してくれた友達に特典がつきます。',
      );
    }
    // 登録から7日を過ぎた人には、入力欄を出さない
    if (!_withinWindow) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '招待コードをお持ちの方',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_submitting,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: '8文字のコード',
                  counterText: '',
                  errorText: _error,
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.point,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(72, 48),
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
                      '入力',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '登録から$_kInviteRedeemWindowDays日以内に入力できます（1回のみ）',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// 限定バッジの詳細シート
// ----------------------------------------------------------------------------
class _BadgeSheet extends StatelessWidget {
  const _BadgeSheet({required this.count, required this.badge});

  final int count;
  final String badge;

  Widget _badgeRow({
    required Color color,
    required String name,
    required int peers,
    required bool earned,
  }) {
    final int remaining = (peers - count).clamp(0, peers);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: earned ? 0.8 : 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.military_tech_rounded, color: color, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$peers人にメッセージを送るともらえます',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
          Text(
            earned ? '獲得済み' : 'あと$remaining人',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: earned ? color : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasGold = badge == 'gold' || count >= _kGoldBadgePeers;
    final bool hasSilver =
        hasGold || badge == 'silver' || count >= _kSilverBadgePeers;
    final double progress = (count / _kGoldBadgePeers).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Icon(Icons.emoji_events_rounded, color: _kGoldColor, size: 48),
          const SizedBox(height: 12),
          const Text(
            '限定バッジプレゼント',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'メッセージを送った相手の人数に応じて、限定バッジがもらえます。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
          ),
          const SizedBox(height: 20),

          // 進み具合
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'メッセージを送った人数：$count人',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey[200],
              color: hasSilver ? _kGoldColor : _kSilverColor,
            ),
          ),
          const SizedBox(height: 20),

          _badgeRow(
            color: _kSilverColor,
            name: '銀バッジ',
            peers: _kSilverBadgePeers,
            earned: hasSilver,
          ),
          _badgeRow(
            color: _kGoldColor,
            name: '金バッジ',
            peers: _kGoldBadgePeers,
            earned: hasGold,
          ),

          const SizedBox(height: 4),
          Text(
            '※ 同じ相手に何通送っても、1人として数えます。\n'
            '※ メッセージの送信には年齢確認が必要です。\n'
            '※ 数え始めは、この機能の開始後に送ったメッセージからです。',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[100],
                foregroundColor: Colors.black54,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                '閉じる',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
