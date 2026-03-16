import 'package:flutter/material.dart';
import 'package:matching_app/screens/chat_screen.dart';
import 'package:matching_app/main.dart';

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
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      appBar: AppBar(
        title: const Text('友達を探す', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
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
                  bottom: 15,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_images.length, (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        // インジケーターの色も合わせる
                        color: _currentPage == index ? AppColors.green : Colors.white70
                      ),
                    )),
                  ),
                ),
              ],
            ),

            // 2. 基本情報エリア
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: 12345678', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  Text('${widget.userName} (24)', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  // 返答率の色をAppBar色に合わせる
                  Text('返信率: 95%', style: TextStyle(color: Color(0xFFFF8A80), fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 5.0,
                runSpacing: 4.0,
                children: [
                  _buildTag('飲み友募集', AppColors.bg, AppColors.green),
                  _buildTag('恋人募集', AppColors.bg, AppColors.green),
                  _buildTag('年齢関係なし', AppColors.bg, AppColors.green),
                  _buildTag('同年代と繋がりたい', AppColors.bg, AppColors.green),
                  _buildTag('性別関係なし', AppColors.bg, AppColors.green),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 3. ボタンエリア (全ボタンをAppBar色ベースに)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      // メッセージボタン
                      Expanded(
                        flex: 4,
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: widget.userName))),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.bg,
                            padding: const EdgeInsets.symmetric(vertical: 15), 
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                            elevation: 0,
                          ),
                          child: const Text('メッセージ', style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.appbarText, 
                            )),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // ギフトボタン
                      Expanded(
                        flex: 4, 
                        child: ElevatedButton(
                          onPressed: () => _showSuperMessageDialog(context, AppColors.bg, AppColors.green),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.bg,
                            padding: const EdgeInsets.symmetric(vertical: 15), 
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), 
                            elevation: 0,
                          ),
                          child: const Text('ギフト', style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.appbarText, 
                            )),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // --- 修正後のいいねボタンエリア ---
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _isLiked = !_isLiked; // 状態を反転
                            });
                            if (_isLiked) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('いいねしました！')));
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            // いいね状態なら背景を塗りつぶし、そうでなければ透明
                            backgroundColor: _isLiked ? const Color(0xFFFF8A80) : Colors.transparent,
                            foregroundColor: _isLiked ? Colors.white : const Color(0xFFFF8A80),
                            padding: const EdgeInsets.symmetric(vertical: 15), 
                            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero), 
                            side: const BorderSide(color: Color(0xFFFF8A80), width: 1.5),
                          ),
                          // 状態に応じてアイコンを切り替え
                          child: Icon(
                            _isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined, 
                            size: 20
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 友達申請ボタン
                  SizedBox(
                    width: double.infinity,
                    child: _buildFriendRequestButton(AppColors.bg, AppColors.green),
                  ),
                ],
              ),
            ),

            _buildSectionTitle('今取り組んでいること / ハマってること'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '最近はFlutterでマッチングアプリを作るのにハマっています！USCPAの勉強も並行しているので、いかに効率よくコードを書くかを考えるのが楽しいです。将来はこのアプリをきっかけに良い出会いがあればいいなと思っています。',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ),

            _buildSectionTitle('休日の過ごし方'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'カフェに行ったりしてます',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ),

               _buildSectionTitle('自分の性格'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '穏やかだとよく言われます',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ),

            _buildSectionTitle('夢・目標'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '将来はUSCPAを取得して海外で働きたいと考えています。同じ目標を持っている方や、プログラミングが好きな方と繋がりたいです！',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ),

            _buildSectionTitle('こんな友達が欲しい！'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '趣味が違っても、気軽に話したり飲みに行ったりできる友達が欲しいです！',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ),

            _buildSectionTitle('プロフィール'),
            _buildDetailTile(Icons.location_on, '居住地', '東京都'),
            _buildDetailTile(Icons.school, '学校', '法政大学（通信）'),
            _buildDetailTile(Icons.work, '職業', '三菱重工'),
            _buildDetailTile(Icons.verified, '資格', '基本情報技術者、USCPA（勉強中）'),
            _buildDetailTile(Icons.group, '部活・サークル', 'テニス、プログラミング部'),

            _buildSectionTitle('その他'),
            _buildDetailTile(Icons.interests, '趣味', 'サウナ、海外旅行、読書'), 
            _buildDetailTile(Icons.pets, 'ペット', 'トイプードル'), // 追加
            _buildDetailTile(Icons.movie, '好きなアニメ・漫画', '葬送のフリーレン、キングダム'), // 追加
            _buildDetailTile(Icons.music_note, '好きなアーティスト', 'Official髭男dism、Vaundy'),
            _buildDetailTile(Icons.smart_display, '好きなユーチューバー', '中田敦彦のYouTube大学'),
            _buildDetailTile(Icons.videogame_asset, '好きなゲーム', 'ゼルダの伝説、原神'),
            _buildDetailTile(Icons.shopping_bag, '好きなブランド', 'UNIQLO、Apple'),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- ヘルパー関数 ---

  Widget _buildTag(String label, Color bgColor, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: Colors.white,// 背景を少し薄くして文字を見やすく
      side: BorderSide(color: color, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      visualDensity: VisualDensity.compact,
    );
  }

  void _showSuperMessageDialog(BuildContext context, Color bgColor, Color textColor) {
    showDialog(
      context: context,
      builder: (context) {
        double commission = 0.1;
        return AlertDialog(
          title: const Text('ギフトを贈る'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.userName}さんにギフトを贈ります。'),
              const SizedBox(height: 20),
              const Text('金額: 1,000円', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              Text('運営手数料 (10%): ${(1000 * commission).toInt()}円', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('相手に届く額: ${(1000 * (1 - commission)).toInt()}円', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), 
              child: Text('キャンセル', style: TextStyle(color: textColor))
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(userName: widget.userName)));
              },
              style: ElevatedButton.styleFrom(backgroundColor: bgColor),
              child: Text('送金して送信', style: TextStyle(color: textColor)),
            ),
          ],
        );
      },
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
      title: Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black)),
      dense: true,
    );
  }

  Widget _buildFriendRequestButton(Color bgColor, Color textColor) {
    int messageCount = 2; 
    int requiredCount = 3;
    bool canRequest = messageCount >= requiredCount;

    return ElevatedButton.icon(
      onPressed: canRequest ? () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('友達申請を送りました！')));
      } : null,
      icon: Icon(Icons.person_add, size: 18, color: canRequest ? textColor : Colors.grey),
      label: Text(
        canRequest ? '友達申請' : 'あと${requiredCount - messageCount}通で友達申請可能', 
        style: TextStyle(fontSize: 12, color: canRequest ? textColor : Colors.grey)
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: canRequest ? bgColor : Colors.grey[300],
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }
}