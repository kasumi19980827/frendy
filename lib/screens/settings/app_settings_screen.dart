import 'package:flutter/material.dart';
import 'package:matching_app/screens/settings/admin_messages_screen.dart';
import 'package:matching_app/screens/settings/blocked_users_screen.dart';

// ============================================================================
// アプリ設定
//
// 💡 この画面は他の画面へ移動するメニューだけで、Firestore を読み書きしない。
//    そのため、ユーザー数が増えてもサーバーの負担は増えない。
//    データの読み込みやセキュリティは、移動先の各画面（ブロック中のユーザー・
//    運営からのメッセージ）とセキュリティルールで対策済み。
// ============================================================================

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'アプリ設定',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      // 💡 Column ではなく ListView にする。
      //    文字サイズを大きく設定している人や、小さい画面でも、
      //    項目が増えたときに画面からはみ出してエラーにならない
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            _buildSettingsItem(
              icon: Icons.block,
              label: 'ブロック中のユーザー',
              onTap: () => _open(context, const BlockedUsersScreen()),
            ),
            _buildSettingsItem(
              icon: Icons.campaign,
              label: '運営からのメッセージ',
              onTap: () => _open(context, const AdminMessagesScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

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
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}
