import 'package:flutter/material.dart';
import 'package:matching_app/screens/settings/blocked_users_screen.dart';
import 'package:matching_app/screens/settings/personal_messages_screen.dart';

// ============================================================================
// アプリ設定
//
// 💡 この画面は他の画面へ移動するメニュー。
//    「運営からのメッセージ」には、自分あての未読メッセージの件数だけを表示する
//    （自分の受信箱の未読を最大20件まで数えるだけなので、負担は小さい）
// ============================================================================

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  // 💡 Stream は一度だけ作る（再描画のたびに作り直さない）
  late final Stream<int> _unreadStream = personalMessagesUnreadCount();

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
      // 💡 Column ではなく ListView にする（文字を大きくしている人や小さい画面でもはみ出さない）
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            _buildSettingsItem(
              icon: Icons.block,
              label: 'ブロック中のユーザー',
              onTap: () => _open(const BlockedUsersScreen()),
            ),
            StreamBuilder<int>(
              stream: _unreadStream,
              builder: (context, snapshot) {
                return _buildSettingsItem(
                  icon: Icons.mail_outline,
                  label: '運営からのメッセージ',
                  unreadCount: snapshot.data ?? 0,
                  onTap: () => _open(const PersonalMessagesScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int unreadCount = 0,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                unreadCount >= 20 ? '20+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
      onTap: onTap,
    );
  }
}
