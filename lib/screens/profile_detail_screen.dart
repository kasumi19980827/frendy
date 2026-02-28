import 'package:flutter/material.dart';
import 'package:matching_app/screens/chat_screen.dart';

class ProfileDetailScreen extends StatefulWidget { // 状態管理のためStatefulWidgetに変更
  final String userName;
  const ProfileDetailScreen({super.key, required this.userName});

  @override
  State<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  // PageViewをプログラムで操作するためのコントローラー
  final PageController _pageController = PageController();
  int _currentPage = 0; // 現在表示中の画像のインデックス
  bool _isFavorited = false; // お気に入り登録されているかどうか

  // 仮の画像データ（最大10枚想定。今回は色のついた四角で代用）
  final List<Color> _images = [
    Colors.grey[300]!, Colors.blue[100]!, Colors.green[100]!,
    Colors.yellow[100]!, Colors.orange[100]!, Colors.purple[100]!,
    Colors.cyan[100]!, Colors.lime[100]!, Colors.teal[100]!, Colors.pink[100]!,
  ];

  @override
  void dispose() {
    _pageController.dispose(); // メモリリーク防止のため必ず記述
    super.dispose();
  }

  // 次の画像へ移動する関数
  void _nextPage() {
    if (_currentPage < _images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300), // アニメーション時間
        curve: Curves.easeInOut, // アニメーションの動き方
      );
    }
  }

  // 前の画像へ移動する関数
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
        title: Text('${widget.userName}さんのプロフ'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 画像エリア（Stackを使って画像の上にボタンを重ねる）
            Stack(
              alignment: Alignment.center, // 子要素を中央寄せ
              children: [
                // 画像（正方形・左右スクロール）
                SizedBox(
                  height: screenWidth, // 正方形にする
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _images.length,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index; // 現在のページ番号を更新
                      });
                    },
                    itemBuilder: (context, index) {
                      return Container(
                        width: screenWidth,
                        color: _images[index],
                        child: Center(
                          child: Icon(Icons.image, size: 100, color: Colors.grey[500]),
                        ),
                      );
                    },
                  ),
                ),

                // --- ここからボタンを追加 ---
                // 左の「戻る」ボタン（最初のページでは表示しない）
                if (_currentPage > 0)
                  Positioned(
                    left: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45, // 半透明の黒
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                        onPressed: _previousPage,
                      ),
                    ),
                  ),

                // 右の「次へ」ボタン（最後のページでは表示しない）
                if (_currentPage < _images.length - 1)
                  Positioned(
                    right: 10,
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
                        onPressed: _nextPage,
                      ),
                    ),
                  ),
                // --------------------------

                // 画像下のインジケーター（点々）
                Positioned(
                  bottom: 15,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_images.length, (index) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentPage == index
                              ? Colors.pinkAccent // 現在のページはピンク
                              : Colors.white70, // それ以外は半透明の白
                        ),
                      );
                    }),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${widget.userName} (24)', 
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)
                      ),
                      const SizedBox(width: 8), // 少しだけ隙間を空ける
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isFavorited = !_isFavorited; // 状態を反転
                          });
                        },
                        icon: Icon(
                          _isFavorited ? Icons.star : Icons.star_border,
                          color: _isFavorited ? Colors.yellow[700] : Colors.grey,
                          size: 30, // 名前が大きいので、星も少し大きくするとバランスが良いです
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('返答率: 95%', style: TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ),

            // 3. メッセージボタン（中央寄せ・90度）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // 通常メッセージボタン
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(userName: widget.userName),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pinkAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      ),
                      child: const Text('メッセージ', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8), // ボタン間の隙間
                  // スーパーメッセージボタン
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _showSuperMessageDialog(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[800],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        elevation: 4,
                      ),
                      child: const Text('スーパーメッセージ', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            // 4. 最近ハマっていること（200文字以内）
            _buildSectionTitle('最近ハマっていること'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '最近はFlutterでマッチングアプリを作るのにハマっています！Go言語のバックエンド構築も勉強中で、商社DXに貢献できるエンジニアを目指しています。',
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 5. 詳細プロフィール
            _buildSectionTitle('詳細プロフィール'),
            _buildDetailTile(Icons.school, '学校', '法政大学（通信）'),
            _buildDetailTile(Icons.work, '職業', '三菱重工'),
            _buildDetailTile(Icons.verified, '資格', '基本情報技術者、USCPA（勉強中）'),
            _buildDetailTile(Icons.group, '部活・サークル', 'テニス、プログラミング部'),
            _buildSectionTitle('その他'),
            _buildDetailTile(Icons.music_note, '好きなアーティスト', 'Official髭男dism、Vaundy'),
            _buildDetailTile(Icons.smart_display, '好きなユーチューバー', '中田敦彦のYouTube大学'),
            _buildDetailTile(Icons.videogame_asset, '好きなゲーム', 'ゼルダの伝説、原神'),
            _buildDetailTile(Icons.shopping_bag, '好きなブランド', 'UNIQLO、Apple'),

            _buildSectionTitle('自由コメント欄'),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '最近はFlutterでマッチングアプリを作るのにハマっています！Go言語のバックエンド構築も勉強中で、商社DXに貢献できるエンジニアを目指しています。',
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            const SizedBox(height: 80),

          ],
        ),
      ),
    );
  }

    //スーパーメッセージ送金表示
    void _showSuperMessageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        int sendAmount = 1000; // デフォルト金額
        double commission = 0.3; // 30%

        return AlertDialog(
          title: const Text('スーパーメッセージ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${widget.userName}さんにギフトを贈ります。'),
              const SizedBox(height: 20),
              const Text('金額: 1,000円', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Divider(),
              Text('運営手数料 (30%): ${(1000 * commission).toInt()}円', 
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text('相手に届く額: ${(1000 * (1 - commission)).toInt()}円', 
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // ダイアログを閉じる
                // チャット画面へ遷移
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatScreen(userName: widget.userName),
                  ),
                );
              },
              child: const Text('送金して送信'),
            ),
          ],
        );
      },
    );
  }

  // 共通パーツ（タイトル）
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  // 共通パーツ（詳細）
  Widget _buildDetailTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey),
      title: Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      subtitle: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black)),
      dense: true,
    );
  }
}