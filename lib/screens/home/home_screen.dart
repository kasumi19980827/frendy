import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ⚠️【重要・提出前に必ず修正】App Store Connectで発行された実際のApp IDに
  //    差し替えてください。プレースホルダーのままだと、レビュー画面が開けない
  //    端末でタップした際に機能が正しく動作しません。
  static const String _appStoreId = 'YOUR_APP_ID';

  static const Duration _networkTimeout = Duration(seconds: 15);

  bool _isExpanded = false;
  bool _showForm = false;
  bool _isSubmittingOpinion = false;

  // --- フォーム管理用 ---
  final TextEditingController _opinionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String myName = "ユーザー";

  @override
  void initState() {
    super.initState();
    _fetchMyName(); // 起動時にFirebaseから名前を取得
  }

  @override
  void dispose() {
    _opinionController.dispose(); // メモリリーク防止
    _scrollController.dispose();
    super.dispose();
  }

  // --- 自分の名前を取得する関数 ---
  Future<void> _fetchMyName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_networkTimeout);
      if (doc.exists && mounted) {
        setState(() {
          myName = doc.data()?['name'] ?? "ユーザー";
        });
      }
    } catch (e) {
      debugPrint("名前取得エラー: $e");
    }
  }

  // 💡 AppBarのホームアイコン：ページ最上部へスクロールする実機能を持たせる
  //    （何も起きない「死んだボタン」を審査で指摘されないようにするため）
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.black),
            tooltip: '最上部へ戻る',
            onPressed: _scrollToTop,
          ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- お知らせセクション ---
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

            // --- 意見送信フォームセクション ---
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
            _buildOpinionForm(context),
            const SizedBox(height: 18),

            // --- バナー類 ---
            _buildReviewBanner(context),
            const SizedBox(height: 12),
            _buildXShareBanner(context),
            const SizedBox(height: 12),
            _buildStoreReviewBanner(context),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // --- お知らせセクション（Firestoreの本番データを表示） ---
  //    💡 以前はアプリ内に固定文言をハードコードしていたが、
  //       AdminMessagesScreenと同じ 'admin_messages' コレクションを参照するよう変更。
  //       これにより「テスト用の固定コンテンツ」に見えるリスクをなくし、
  //       お知らせ更新のたびにアプリを再申請する必要もなくなる
  Widget _buildNoticesSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('admin_messages')
          .orderBy('createdAt', descending: true)
          .limit(10) // 💡 上限を設け、無制限に読み込まないようにする
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'お知らせの読み込みに失敗しました',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];
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
            physics: _isExpanded
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: displayDocs.length,
            itemBuilder: (context, index) {
              final data = displayDocs[index].data() as Map<String, dynamic>;
              final String title = data['title'] ?? 'お知らせ';
              final String body = data['body'] ?? '';
              final Timestamp? createdAt = data['createdAt'] as Timestamp?;
              final String dateStr = createdAt != null
                  ? '${createdAt.toDate().year}/${createdAt.toDate().month.toString().padLeft(2, '0')}/${createdAt.toDate().day.toString().padLeft(2, '0')}'
                  : '';
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
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
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

  // 💡 お知らせをタップした際に本文を表示する詳細ダイアログ
  //    （AdminMessagesScreenと同じ見せ方に合わせている）
  void _showNoticeDetail(String title, String body, String date) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '閉じる',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.point.withOpacity(0.8), AppColors.point],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '友達招待で1ヶ月無料体験！',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'あなたの友達も１ヶ月無料体験が楽しめます！',
                  style: TextStyle(color: Colors.white, fontSize: 12),
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

  Widget _buildXShareBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          const Icon(Icons.close, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xにシェアして特典をGET！',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '限定デザインのアバターを\nプレゼント！',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async => await _shareOnX(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              '投稿する',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOnX() async {
    // 💡 手動の文字列結合ではなく、Uri.https + queryParametersで
    //    正しくURLエンコードする（不正なURLになるのを防ぐ）
    final Uri xUrl = Uri.https('x.com', '/intent/tweet', {
      'text': 'frendyで繋がろう！',
      'hashtags': 'frendy',
    });

    try {
      final bool launched = await launchUrl(
        xUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await launchUrl(xUrl, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('X共有エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('共有画面を開けませんでした。もう一度お試しください。')),
        );
      }
    }
  }

  void _showInviteDetails() {
    final user = FirebaseAuth.instance.currentUser;
    final String inviteCode =
        user?.uid.substring(0, 6).toUpperCase() ?? "UNKNOWN";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
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
                  color: AppColors.point.withOpacity(0.05),
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
                      'あなたと友達のどちらも、全ての機能が使える「プレミアムプラン」を1ヶ月間無料で楽しめます。',
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
              const Text(
                '招待コードをシェア',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('招待コードをコピーしました！'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      backgroundColor: AppColors.point,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.point.withOpacity(0.3),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        inviteCode,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: AppColors.point,
                        ),
                      ),
                      const Icon(
                        Icons.copy_rounded,
                        color: AppColors.point,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
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
      },
    );
  }

  Widget _buildStoreReviewBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.pink.withOpacity(0.1),
            AppColors.pink.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.pink.withOpacity(0.2), width: 1.5),
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
                  'frendyの感想を教えてね！',
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
            onPressed: () => _handleStoreReviewTap(context),
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

  // 💡 例外処理を追加し、プレースホルダーのApp IDのまま誤って
  //    ストア遷移を試みて機能が壊れることのないようにガードする
  Future<void> _handleStoreReviewTap(BuildContext context) async {
    try {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        return;
      }

      if (_appStoreId == 'YOUR_APP_ID') {
        debugPrint('警告: App Store IDが未設定のままです。_appStoreIdを実際の値に差し替えてください。');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('現在準備中です。しばらくお待ちください。')));
        }
        return;
      }

      await inAppReview.openStoreListing(appStoreId: _appStoreId);
    } catch (e) {
      debugPrint('レビュー画面の表示エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レビュー画面を開けませんでした。もう一度お試しください。')),
        );
      }
    }
  }

  // --- 意見送信フォーム ---
  Widget _buildOpinionForm(BuildContext context) {
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
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _opinionController,
                      maxLines: 3,
                      maxLength: 500, // 💡 スパム・Firestoreドキュメント肥大化対策
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

  // 💡 意見送信処理を独立させ、二重送信防止・エラーフィードバックを追加
  Future<void> _submitOpinion() async {
    final String text = _opinionController.text.trim();
    if (text.isEmpty || _isSubmittingOpinion) return;

    setState(() => _isSubmittingOpinion = true);

    try {
      await FirebaseFirestore.instance
          .collection('opinions')
          .add({
            'userId': FirebaseAuth.instance.currentUser?.uid,
            'userName': myName,
            'text': text,
            'createdAt': FieldValue.serverTimestamp(),
          })
          .timeout(_networkTimeout);

      if (!mounted) return;

      _opinionController.clear();
      setState(() {
        _showForm = false;
        _isSubmittingOpinion = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ご意見ありがとうございます！'),
          backgroundColor: Color.fromARGB(255, 2, 2, 2),
        ),
      );
    } catch (e) {
      debugPrint("意見送信エラー: $e");
      if (mounted) {
        setState(() => _isSubmittingOpinion = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('送信に失敗しました。もう一度お試しください。')));
      }
    }
  }
}
