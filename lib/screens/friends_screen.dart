import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart';
import 'package:matching_app/screens/profile_detail_screen.dart'; 

class Friend {
  final String name;
  final String imageUrl;
  final IconData defaultIcon;

  Friend({
    required this.name,
    this.imageUrl = '',
    this.defaultIcon = Icons.person,
  });
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  // 初期選択を「友達一覧」に設定
  String _selectedMenu = '友達一覧';

  // --- 各メニューごとのデータリスト ---
  final List<Friend> _friendsList = [
    Friend(name: 'アヤカ'), Friend(name: 'タクヤ'), Friend(name: 'マナミ'),
    Friend(name: 'ケンタ'), Friend(name: 'リナ'), Friend(name: 'ショウタ'),
    Friend(name: 'ユウキ'), Friend(name: 'ヒナ'),
  ];

  final List<Friend> _likedList = [
    Friend(name: 'サオリ'), Friend(name: 'ダイスケ'), Friend(name: 'ミズキ'),
  ];

  final List<Friend> _likedByList = [
    Friend(name: 'ハルカ'), Friend(name: 'ソウタ'), Friend(name: 'ナナミ'), Friend(name: 'レン'),
  ];

  // ✅ 足跡（プロフィールを見た人）のリストを追加
  final List<Friend> _visitorList = [
    Friend(name: 'カレン'),
    Friend(name: 'トモヤ'),
    Friend(name: 'リオ'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('frendy', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Row(
        children: [
          // 左側のサイドメニュー
          Container(
            width: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(right: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                _buildMenuItem('友達一覧', Icons.group),
                _buildMenuItem('いいね\nした', Icons.thumb_up_alt_outlined),
                _buildMenuItem('いいね\nされた', Icons.thumb_up_alt),
                _buildMenuItem('足跡', Icons.visibility),
              ],
            ),
          ),
          // 右側のメインコンテンツ
          Expanded(
            child: Container(
              color: Colors.white,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(String title, IconData icon, {Color color = AppColors.point}) {
    bool isSelected = _selectedMenu == title;
    return InkWell(
      onTap: () => setState(() => _selectedMenu = title),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        color: isSelected ? Colors.white : Colors.transparent,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ コンテンツ切り替えロジック
  Widget _buildContent() {
    switch (_selectedMenu) {
      case '友達一覧':
        return _buildUserList(_friendsList);
      case 'いいね\nした':
        return _buildUserList(_likedList);
      case 'いいね\nされた':
        return _buildUserList(_likedByList);
      case '足跡':
        // ✅ プレミアムロックを外して、リストを表示するように変更
        return _buildUserList(_visitorList);
      default:
        return const Center(child: Text('選択してください'));
    }
  }

  // リスト表示用ウィジェット（共通）
  Widget _buildUserList(List<Friend> list) {
    if (list.isEmpty) {
      return const Center(child: Text('まだデータがありません', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) => _buildFriendListItem(list[index]),
    );
  }

  Widget _buildFriendListItem(Friend friend) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileDetailScreen(userName: friend.name),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey[100]!))),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEEEEEE)),
              child: friend.imageUrl.isEmpty
                  ? Icon(friend.defaultIcon, color: Colors.grey[400])
                  : ClipOval(child: Image.network(friend.imageUrl, fit: BoxFit.cover)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(friend.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}