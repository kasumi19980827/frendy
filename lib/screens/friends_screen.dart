import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  // 現在選択されているメニュー項目
  String _selectedMenu = '友達一覧';
  // 足跡の課金状態（本来はユーザーデータから取得）
  bool _isPremiumUser = false; 

  @override
  Widget build(BuildContext context) {
    final Color themeColor = Theme.of(context).colorScheme.inversePrimary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('frendy', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Row(
        children: [
          // --- 左側：メニューエリア ---
          Container(
            width: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(right: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                _buildMenuItem('友達一覧', Icons.group, themeColor),
                _buildMenuItem('いいね\nした', Icons.thumb_up_alt_outlined, themeColor),
                _buildMenuItem('いいね\nされた', Icons.thumb_up_alt, themeColor),
                _buildMenuItem('足跡', Icons.visibility, themeColor),
              ],
            ),
          ),
          // --- 右側：コンテンツエリア ---
          Expanded(
            child: _buildContent(themeColor),
          ),
        ],
      ),
    );
  }

  // メニュー項目の作成
  Widget _buildMenuItem(String title, IconData icon, Color themeColor) {
    bool isSelected = _selectedMenu == title;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedMenu = title;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        color: isSelected ? Colors.white : Colors.transparent,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? themeColor : Colors.grey),
            const SizedBox(height: 5),
            Text(title, style: TextStyle(fontSize: 12, color: isSelected ? themeColor : Colors.black87)),
          ],
        ),
      ),
    );
  }

  // 右側の表示内容を切り替える
  Widget _buildContent(Color themeColor) {
    if (_selectedMenu == '足跡' && !_isPremiumUser) {
      return _buildPremiumLockPage(themeColor);
    }
    return Center(
      child: Text('「$_selectedMenu」の内容がここに表示されます'),
    );
  }

  // 足跡の有料ロック画面
  Widget _buildPremiumLockPage(Color themeColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 80, color: Color(0xFFFF8A80)),
          const SizedBox(height: 20),
          const Text('足跡機能はプレミアム限定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('月額500円で誰があなたのプロフィールを見たか確認できます。', textAlign: TextAlign.center),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              // 課金処理のシミュレーション
            },
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFFF8A80)),
            child: const Text('月額500円で登録', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}