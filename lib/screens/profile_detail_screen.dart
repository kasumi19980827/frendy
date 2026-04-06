import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/screens/talk_screen.dart';

class ProfileDetailScreen extends StatefulWidget {
  final String userName;
  const ProfileDetailScreen({super.key, required this.userName});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLiked = false;

  final List<Color> _images = [
    Colors.grey[300]!, Colors.blue[100]!, Colors.green[100]!,
    Colors.yellow[100]!, Colors.orange[100]!, Colors.purple[100]!,
    Colors.cyan[100]!, Colors.lime[100]!, Colors.teal[100]!, Colors.pink[100]!,
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _images.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const Color accentPink = Color(0xFFFF8A80);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('frendy', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
        // backgroundColor: AppColors.blue,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 画像エリア
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: screenWidth,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _images.length,
                    onPageChanged: (index) => setState(() => _currentPage = index),
                    itemBuilder: (context, index) => Container(
                      width: screenWidth,
                      color: _images[index],
                      child: Center(child: Icon(Icons.image, size: 100, color: Colors.grey[500])),
                    ),
                  ),
                ),
                if (_currentPage > 0)
                  Positioned(
                    left: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: _previousPage),
                    ),
                  ),
                if (_currentPage < _images.length - 1)
                  Positioned(
                    right: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20), onPressed: _nextPage),
                    ),
                  ),
                Positioned(
                  bottom: 35, 
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_images.length, (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        color: _currentPage == index ? AppColors.point : Colors.white70
                      ),
                    )),
                  ),
                ),
              ],
            ),

            // プロフィール詳細コンテナ
            Container(
              transform: Matrix4.translationValues(0, -20, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 基本情報エリア
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ID: 12345678', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                        Text('${widget.userName} (24)', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                        const Text('返信率: 95%', style: TextStyle(color: accentPink, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 5.0,
                      runSpacing: 4.0,
                      children: [
                        _buildTag('飲み友募集', AppColors.tag),
                        _buildTag('恋人募集', AppColors.tag),
                        _buildTag('年齢関係なし', AppColors.tag),
                        _buildTag('同年代と繋がりたい', AppColors.tag),
                        _buildTag('性別関係なし', AppColors.tag),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 4. ボタンエリア
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 7,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.send, size: 18, color: Colors.white), 
                                label: const Text('トークする', style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white, 
                                )),
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => TalkScreen(userName: widget.userName))),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.point,
                                  padding: const EdgeInsets.symmetric(vertical: 15), 
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), 
                                  elevation: 2,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            
                            Expanded(
                              flex: 1,
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() => _isLiked = !_isLiked);
                                  if (_isLiked) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('いいねしました！')));
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: _isLiked ? accentPink : Colors.transparent,
                                  foregroundColor: _isLiked ? Colors.white : accentPink,
                                  padding: const EdgeInsets.symmetric(vertical: 15), 
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), 
                                  side: const BorderSide(color: accentPink, width: 1.5),
                                ),
                                child: Icon(
                                  _isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined, 
                                  size: 20
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: _buildFriendRequestButton(AppColors.point),
                        ),
                      ],
                    ),
                  ),

                  _buildSectionTitle('自己紹介'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'こんにちは！山田花子です！今大学生でバイトやサークル活動を行っています。',
                      style: TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),

                  _buildSectionTitle('ハマってること'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'アイドルを推すことで、週末ライブにいったりしています！',
                      style: TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),

                  _buildSectionTitle('こんな友達が欲しい'),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '同じアイドルオタクで、一緒にライブ行ったりできる友達が欲しいです！',
                      style: TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),

                  // 5. プロフィール欄 (Blue背景)
                  _buildSectionTitle('プロフィール'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgblue, 
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          _buildDetailTile(Icons.location_on, '居住地', '東京都'),
                          _buildDetailTile(Icons.school, '学校', '法政大学（通信）'),
                          _buildDetailTile(Icons.work, '職業', '三菱重工'),
                          _buildDetailTile(Icons.verified, '資格', '基本情報技術者、USCPA（勉強中）'),
                          _buildDetailTile(Icons.group, '部活・サークル', 'テニス、プログラミング部'),
                        ],
                      ),
                    ),
                  ),

                  // 6. その他プロフィール欄 (Pink背景)
                  _buildSectionTitle('その他プロフィール'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgblue, // Pinkを薄めた色
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        children: [
                          _buildDetailTile(Icons.interests, '趣味', 'サウナ、海外旅行、読書'),
                          _buildDetailTile(Icons.pets, 'ペット', 'トイプードル'),
                          _buildDetailTile(Icons.movie, '好きなアニメ・漫画', '葬送のフリーレン、キングダム'),
                          _buildDetailTile(Icons.music_note, '好きなアーティスト', 'Official髭男dism、Vaundy'),
                          _buildDetailTile(Icons.smart_display, '好きなユーチューバー', '中田敦彦のYouTube大学'),
                          _buildDetailTile(Icons.videogame_asset, '好きなゲーム', 'ゼルダの伝説、原神'),
                          _buildDetailTile(Icons.shopping_bag, '好きなブランド', 'UNIQLO、Apple'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 50),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ヘルパー関数 ---
  // (変更なしのため省略可能ですが、そのままお使いいただけます)

  Widget _buildTag(String label, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: Colors.white,
      side: BorderSide(color: color, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDetailTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey),
      title: Text(label, style: const TextStyle(fontSize: 14, color: Color.fromARGB(174, 0, 0, 0))),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black)),
      dense: true,
    );
  }

  Widget _buildFriendRequestButton(Color color) {
    int messageCount = 2; 
    int requiredCount = 3;
    bool canRequest = messageCount >= requiredCount;

    return ElevatedButton.icon(
      onPressed: canRequest ? () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('友達申請を送りました！')));
      } : null,
      icon: Icon(Icons.person_add, size: 18, color: canRequest ? color : Colors.grey),
      label: Text(
        canRequest ? '友達申請' : 'あと${requiredCount - messageCount}通で友達申請可能', 
        style: TextStyle(fontSize: 12, color: canRequest ? color : Colors.grey)
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: canRequest ? Colors.white : Colors.grey[100],
        foregroundColor: color,
        elevation: canRequest ? 1 : 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: canRequest ? BorderSide(color: color) : BorderSide.none,
        ),
      ),
    );
  }
}