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
  // --- お知らせのデータリスト ---
  final List<Map<String, String>> _notices = const [
    {'date': '2026/03/10', 'title': '新機能「ギフト機能」が追加されました！'},
    {'date': '2026/03/05', 'title': 'サーバーメンテナンスのお知らせ'},
    {'date': '2026/03/01', 'title': '春のプレゼントキャンペーン実施中！'},
    {'date': '2026/02/20', 'title': '重要：プライバシーポリシー改定'},
    {'date': '2026/02/15', 'title': 'アプリアップデート情報 (ver 2.1)'},
    {'date': '2026/02/10', 'title': '過去のイベント：バレンタイン特集'},
    {'date': '2026/02/01', 'title': '冬のログインボーナス配布中'},
  ];

  bool _isExpanded = false; 
  bool _showForm = false;
  
  // --- フォーム管理用 ---
  final TextEditingController _opinionController = TextEditingController();
  String myName = "ユーザー"; 

  @override
  void initState() {
    super.initState();
    _fetchMyName(); // 起動時にFirebaseから名前を取得
  }

  @override
  void dispose() {
    _opinionController.dispose(); // メモリリーク防止
    super.dispose();
  }

  // --- 自分の名前を取得する関数 ---
  Future<void> _fetchMyName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() {
            myName = doc.data()?['name'] ?? "ユーザー";
          });
        }
      } catch (e) {
        debugPrint("名前取得エラー: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayNotices = _isExpanded ? _notices : _notices.take(2).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'ホーム',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        // ここを true にすると、テキストだけが中央に配置されます
        centerTitle: true, 
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.black),
            onPressed: () {
              print('ホームアイコンがタップされました');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                    Text('運営からのお知らせ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                TextButton(
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                  child: Text(
                    _isExpanded ? '閉じる' : 'もっと見る',
                    style: const TextStyle(color: AppColors.point, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: _isExpanded ? 350 : 180, 
              ),
              child: ListView.builder(
                shrinkWrap: true,
                physics: _isExpanded 
                    ? const AlwaysScrollableScrollPhysics() 
                    : const NeverScrollableScrollPhysics(),
                itemCount: displayNotices.length,
                itemBuilder: (context, index) {
                  return _buildNoticeCard(
                    displayNotices[index]['date']!, 
                    displayNotices[index]['title']!
                  );
                },
              ),
            ),
            const SizedBox(height: 5),
            
            // --- 意見送信フォームセクション ---
            const Row(
              children: [
                Icon(Icons.rate_review, color: AppColors.point),
                SizedBox(width: 8),
                Text('運営へのご意見・ご要望', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            _buildStoreReviewBanner(context), // ★ここに追加！
            const SizedBox(height:  10),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeCard(String date, String title) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: const Icon(Icons.info_outline, color: AppColors.point),
        title: Text(title, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        dense: true,
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
                Text('友達招待で1ヶ月無料体験！', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('あなたの友達も１ヶ月無料体験が楽しめます！', style: TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _showInviteDetails,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, 
              foregroundColor: AppColors.point,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('詳細', style: TextStyle(fontWeight: FontWeight.bold)),
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
                Text('Xにシェアして特典をGET！', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text('限定デザインのアバターを\nプレゼント！', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async => await _shareOnX(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white, 
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('投稿する', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareOnX() async {
    const String text = "frendyで繋がろう！";
    const String hashtag = "frendy";
    final String rawUrl = "https://x.com/intent/tweet?text=${text} %23${hashtag}";
    final Uri xUrl = Uri.parse(rawUrl);
    try {
      await launchUrl(xUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      await launchUrl(xUrl, mode: LaunchMode.platformDefault);
    }
  }

  void _showInviteDetails() {
    final user = FirebaseAuth.instance.currentUser;
    final String inviteCode = user?.uid.substring(0, 6).toUpperCase() ?? "UNKNOWN";

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // 背景を透明にして角丸を活かす
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
              // --- 上部のバー ---
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
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              
              // --- 説明文カード ---
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
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.point, fontSize: 15),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'あなたと友達のどちらも、全ての機能が使える「プレミアムプラン」を1ヶ月間無料で楽しめます。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              const Text(
                '招待コードをシェア',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 12),

              // --- 招待コード表示エリア（タップでコピー） ---
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: inviteCode));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('招待コードをコピーしました！'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: AppColors.point,
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.point.withOpacity(0.3), width: 2),
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
                          color: AppColors.point
                        ),
                      ),
                      const Icon(Icons.copy_rounded, color: AppColors.point, size: 20),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // --- 閉じるボタン ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                    foregroundColor: Colors.black54,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text('閉じる', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom), // iPhoneの下部バー対策
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
        // 強すぎないピンク系のグラデーションで、招待バナーとの統一感を出す
        gradient: LinearGradient(
          colors: [
            AppColors.pink.withOpacity(0.1), 
            AppColors.pink.withOpacity(0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        // 枠線もピンク系にすることで、画面に馴染ませる
        border: Border.all(color: AppColors.pink.withOpacity(0.2), width: 1.5),
      ),
      child: Row(
        children: [
          // アイコンもピンク系にして統一
          const Icon(Icons.favorite_rounded, color: AppColors.pink, size: 36),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'frendyの感想を教えてね！', 
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)
                ),
                Text(
                  'レビューで応援いただけると、\n開発の励みになります！', 
                  style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final InAppReview inAppReview = InAppReview.instance;
              if (await inAppReview.isAvailable()) {
                inAppReview.requestReview();
              } else {
                inAppReview.openStoreListing(appStoreId: 'YOUR_APP_ID'); 
              }
            },
            style: ElevatedButton.styleFrom(
              // ボタンもピンクにすることで、視覚的な一貫性を確保
              backgroundColor: AppColors.pink, 
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text('書く', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // --- 意見送信フォーム ---
  Widget _buildOpinionForm(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300), // 切り替わりの速さ
      child: !_showForm 
        ? // --- 【表示1】意見を書くボタン ---
          SizedBox(
            key: const ValueKey('button'),
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _showForm = true),
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('意見を書く', style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.point,
                side: const BorderSide(color: AppColors.point),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          )
        : // --- 【表示2】入力フォーム本体 ---
          Card(
            key: const ValueKey('form'),
            elevation: 0,
            color: Colors.grey[100],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  TextField(
                    controller: _opinionController,
                    maxLines: 3,
                    autofocus: true, // フォームが出た瞬間にキーボードを出す
                    decoration: const InputDecoration(
                      hintText: '「こんな機能が欲しい！」など、お気軽にお書きください。',
                      hintStyle: TextStyle(fontSize: 13),
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // キャンセルボタン
                      TextButton(
                        onPressed: () => setState(() => _showForm = false),
                        child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
                      ),
                      const Spacer(),
                      // 送信ボタン
                      ElevatedButton(
                        onPressed: () async {
                          final text = _opinionController.text.trim();
                          if (text.isEmpty) return;

                          try {
                            await FirebaseFirestore.instance.collection('opinions').add({
                              'userId': FirebaseAuth.instance.currentUser?.uid,
                              'userName': myName,
                              'text': text,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            _opinionController.clear();
                            setState(() => _showForm = false); // 送信後に閉じる
                            
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ご意見ありがとうございます！'),
                                backgroundColor: Color.fromARGB(255, 2, 2, 2),
                              ),
                            );
                          } catch (e) {
                            debugPrint("送信エラー: $e");
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.point, 
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('送信する', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }
}