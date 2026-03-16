import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('プロフィール設定'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // --- ユーザー基本情報セクション ---
            const CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage('https://via.placeholder.com/150'), // ダミー画像
            ),
            const SizedBox(height: 10),
            const Text(
              'ユーザー名',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Divider(),

            // --- 設定メニューリスト ---
            _buildSettingsItem(
              icon: Icons.edit,
              label: 'プロフィール編集',
              onTap: () {
                // 編集画面への遷移処理をここに書く
              },
            ),
            _buildSettingsItem(
              icon: Icons.photo_library,
              label: '写真の管理',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.verified_user,
              label: '年齢確認・本人確認',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.settings,
              label: 'アプリ設定',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.help_outline,
              label: 'ヘルプ・お問い合わせ',
              onTap: () {},
            ),
            
            const Divider(),
            
            // --- ログアウトなどの重要な操作 ---
            _buildSettingsItem(
              icon: Icons.logout,
              label: 'ログアウト',
              labelColor: Colors.redAccent,
              onTap: () {
                // ログアウト確認ダイアログなどを出す
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 設定項目の共通パーツ
  Widget _buildSettingsItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color labelColor = Colors.black87,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(
        label,
        style: TextStyle(color: labelColor, fontSize: 16),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}