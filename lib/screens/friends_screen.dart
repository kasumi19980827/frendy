import 'package:flutter/material.dart';
import 'package:matching_app/main.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String _selectedMenu = '友達一覧';
  bool _isPremiumUser = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('友達', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
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
                _buildMenuItem('友達一覧', Icons.group),
                _buildMenuItem('いいね', Icons.thumb_up_alt_outlined),
                _buildMenuItem('いいね\nされた', Icons.thumb_up_alt),
                _buildMenuItem('足跡', Icons.visibility),
              ],
            ),
          ),
          // --- 右側：コンテンツエリア ---
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  // ✅ パラメータ名を color に修正、AppColors.bgはデフォルト値として渡す
  Widget _buildMenuItem(String title, IconData icon, {Color color = AppColors.point}) {
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
        color: isSelected ? AppColors.white : Colors.transparent,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? color : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedMenu == '足跡' && !_isPremiumUser) {
      return _buildPremiumLockPage();
    }
    return Center(
      child: Text('「$_selectedMenu」の内容がここに表示されます'),
    );
  }

  Widget _buildPremiumLockPage() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 80, color: AppColors.pink),
          const SizedBox(height: 20),
          const Text('足跡機能はプレミアム限定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text('月額980円で誰があなたのプロフィールを見たか確認できます。',
              textAlign: TextAlign.center),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              // 課金処理
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
            child: const Text('月額980円で登録',
                style: TextStyle(color: AppColors.white)),
          ),
        ],
      ),
    );
  }
}