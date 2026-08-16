import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/profile/profile_detail_screen.dart';
import 'package:matching_app/screens/subscription/subscription_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String _selectedMenu = '友達一覧';
  final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          _selectedMenu,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Row(
        children: [
          // 左側のサイドメニュー
          Container(
            width: 85,
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(right: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Column(
              children: [
                _buildMenuItem('友達一覧', Icons.group),
                _buildRequestMenuItem(),
                _buildMenuItem('いいねした', Icons.thumb_up_alt_outlined),
                _buildMenuItem('いいねされた', Icons.thumb_up_alt),
                _buildMenuItem('足跡', Icons.visibility),
              ],
            ),
          ),
          // 右側のコンテンツエリア
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  // メニューアイテムの生成
  Widget _buildMenuItem(String title, IconData icon) {
    bool isSelected = _selectedMenu == title;
    return InkWell(
      onTap: () => setState(() => _selectedMenu = title),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 4),
        color: isSelected ? Colors.white : Colors.transparent,
        child: Column(
          children: [
            Icon(icon, color: isSelected ? AppColors.point : AppColors.txt),
            const SizedBox(height: 5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.point : AppColors.txt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 通知バッジ付きの友達申請メニュー
  Widget _buildRequestMenuItem() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('toId', isEqualTo: myId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        int requestCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Stack(
          children: [
            _buildMenuItem('友達申請', Icons.person_add),
            if (requestCount > 0)
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    '$requestCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // コンテンツの出し分けロジック
  Widget _buildContent() {
    switch (_selectedMenu) {
      case '友達一覧':
        return _buildFriendsList();
      case '友達申請':
        return _buildRequestList();
      case 'いいねした':
        return _buildUserListFromField('likes', 'いいねしたユーザーはいません');
      case 'いいねされた':
        return _buildUserListFromField(
          'likedBy',
          'まだいいねが届いていません',
          isLikeList: true,
        );
      case '足跡':
        return _buildUserListFromField(
          'footprints',
          'まだ足跡はありません',
          isFootprints: true,
        );
      default:
        return const Center(child: Text('準備中'));
    }
  }

  // --- 1. 友達一覧 ---
  Widget _buildFriendsList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(myId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final myData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final List<dynamic> friendsIds = myData['friends'] ?? [];

        if (friendsIds.isEmpty)
          return const Center(
            child: Text('まだ友達がいません', style: TextStyle(color: Colors.grey)),
          );

        return ListView.builder(
          itemCount: friendsIds.length,
          itemBuilder: (context, index) {
            final String peerId = friendsIds[index];
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(peerId)
                  .get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) return const SizedBox();
                final userData =
                    userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final String name = userData['name'] ?? 'ユーザー';
                final String imageUrl =
                    (userData['imageUrls'] as List?)?.isNotEmpty == true
                    ? userData['imageUrls'][0]
                    : '';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: imageUrl.isNotEmpty
                        ? NetworkImage(imageUrl)
                        : null,
                    child: imageUrl.isEmpty ? const Icon(Icons.person) : null,
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                      if (userData.containsKey('gender')) ...[
                        const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            final gender = userData['gender'];
                            final Color bgColor = gender == '男性'
                                ? Colors.blue.withOpacity(0.15)
                                : (gender == '女性'
                                      ? Colors.pink.withOpacity(0.15)
                                      : Colors.grey.withOpacity(0.15));
                            final Color iconColor = gender == '男性'
                                ? Colors.blue
                                : (gender == '女性' ? Colors.pink : Colors.grey);
                            final IconData iconData = gender == '男性'
                                ? Icons.male
                                : (gender == '女性'
                                      ? Icons.female
                                      : Icons.transgender);

                            return Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: bgColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(iconData, color: iconColor, size: 12),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showActionSheet(context, peerId, name),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileDetailScreen(
                          userData: userData,
                          userId: peerId,
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // --- 2. 友達申請リスト（承認ボタンを小サイズ化） ---
  Widget _buildRequestList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('toId', isEqualTo: myId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty)
          return const Center(
            child: Text('届いている申請はありません', style: TextStyle(color: Colors.grey)),
          );

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final requestData = docs[index].data() as Map<String, dynamic>;
            final String fromId = requestData['fromId'];
            final String requestId = docs[index].id;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(fromId)
                  .get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) return const SizedBox();
                final userData =
                    userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final String name = userData['name'] ?? 'ユーザー';
                final String imageUrl =
                    (userData['imageUrls'] as List?)?.isNotEmpty == true
                    ? userData['imageUrls'][0]
                    : '';

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: imageUrl.isNotEmpty
                        ? NetworkImage(imageUrl)
                        : null,
                  ),
                  title: Text(name),
                  // 💡 承認ボタンを右寄せしつつ、サイズを綺麗に小さくコントロール
                  trailing: ElevatedButton(
                    onPressed: () =>
                        _acceptFriendRequest(fromId, name, requestId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.bg,
                      elevation: 0, // フラットにしてすっきり見せる
                      // 💡 ボタンの縦横の最小サイズを低く指定 (横64, 縦30)
                      minimumSize: const Size(64, 30),
                      // 💡 内側の余白を狭めて文字がギリギリ収まるサイズに
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          20,
                        ), // 丸みを強くしてコンパクト感を強調
                      ),
                    ),
                    child: const Text(
                      '承認',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // --- 3. 共通リスト（いいね・足跡） ---
  Widget _buildUserListFromField(
    String fieldName,
    String emptyMessage, {
    bool isFootprints = false,
    bool isLikeList = false,
  }) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(myId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final myData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final List<dynamic> userIds = myData[fieldName] ?? [];

        if (userIds.isEmpty)
          return Center(
            child: Text(
              emptyMessage,
              style: const TextStyle(color: Colors.grey),
            ),
          );

        // 💡 リアルタイムのFirestoreスナップショットから直接プランを判定
        //    → プラン変更が即座に反映され、ホットリロード不要になる
        final String livePlan = myData['plan'] ?? 'free';

        // 💡 足跡タブ：フリープランのみモザイク（ライト以降で解除）
        // 💡 いいねタブ：フリー・ライトプランはモザイク（スタンダード以降で解除）
        final bool shouldBlur =
            (isFootprints && livePlan == 'free') ||
            (isLikeList && (livePlan == 'free' || livePlan == 'light'));

        return ListView.builder(
          itemCount: userIds.length,
          itemBuilder: (context, index) {
            final String peerId = userIds[index];
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(peerId)
                  .get(),
              builder: (context, userSnap) {
                if (!userSnap.hasData) return const SizedBox();
                final userData =
                    userSnap.data!.data() as Map<String, dynamic>? ?? {};
                final String name = userData['name'] ?? 'ユーザー';
                final bool hasImage =
                    (userData['imageUrls'] as List?)?.isNotEmpty == true;

                final Widget avatar = CircleAvatar(
                  backgroundImage: hasImage
                      ? NetworkImage(userData['imageUrls'][0])
                      : null,
                  child: hasImage ? null : const Icon(Icons.person),
                );

                return ListTile(
                  leading: shouldBlur
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                          child: avatar,
                        )
                      : avatar,
                  title: shouldBlur
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              '●●●●',
                              style: TextStyle(
                                color: Colors.grey,
                                letterSpacing: 2,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.lock, size: 14, color: Colors.grey),
                          ],
                        )
                      : Text(name),
                  subtitle: shouldBlur
                      ? const Text(
                          'プラン登録で誰か確認できます',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        )
                      : null,
                  onTap: () {
                    if (shouldBlur) {
                      if (isLikeList) {
                        _showLikeUpgradeDialog(context);
                      } else {
                        _showFootprintUpgradeDialog(context);
                      }
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileDetailScreen(
                            userData: userData,
                            userId: peerId,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // 💡 足跡モザイクをタップした際、プラン登録を促すダイアログ
  void _showFootprintUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '足跡は非表示中です',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          '現在フリープランをご利用中のため、あなたのプロフィールを見た人の詳細はモザイク表示になっています。\n\n'
          '『ライトプラン』以降に登録すると、足跡をつけた相手をすべて確認できるようになります。',
          style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '閉じる',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.point,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
            },
            child: const Text(
              'プラン一覧を見る',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 💡 いいねモザイクをタップした際、スタンダード以降への登録を促すダイアログ
  void _showLikeUpgradeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'いいねは非表示中です',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          '現在のプランでは、いいねの詳細はモザイク表示になっています。\n\n'
          '『スタンダードプラン』以降に登録すると、いいねした相手・された相手をすべて確認できるようになります。',
          style: TextStyle(fontSize: 14, height: 1.5, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '閉じる',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.point,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
              );
            },
            child: const Text(
              'プラン一覧を見る',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- アクション (ボトムシート、通報、削除など) ---

  void _showActionSheet(BuildContext context, String peerId, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            Text(
              name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _tile(
              icon: Icons.report_problem_outlined,
              title: '通報する',
              subtitle: '不適切な内容を報告',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(context, peerId, name);
              },
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.block,
              title: 'ブロックする',
              subtitle: 'このユーザーを非表示',
              color: Colors.black87,
              onTap: () {
                Navigator.pop(context); // シートを閉じる
                _showBlockConfirmation(context, peerId, name); // 確認ダイアログへ
              },
            ),
            const SizedBox(height: 12),
            _tile(
              icon: Icons.person_remove_outlined,
              title: '友達解除',
              subtitle: '友達リストから削除します',
              color: Colors.redAccent,
              onTap: () {
                Navigator.pop(context);
                _removeFriend(peerId, name);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.grey[50],
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext context, String peerId, String name) {
    final TextEditingController reportController = TextEditingController();
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          '$name さんを通報',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '不適切な言動や規約違反がありましたか？\n理由を詳しく教えてください。',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: reportController,
              maxLines: 4,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: '通報理由を入力...',
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.all(16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey[200]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: Colors.redAccent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    final String reason = reportController.text.trim();
                    if (reason.isEmpty) return;

                    await FirebaseFirestore.instance.collection('reports').add({
                      'reporterId': currentUserId,
                      'reportedId': peerId,
                      'reason': reason,
                      'createdAt': FieldValue.serverTimestamp(),
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('報告ありがとうございます。運営で確認いたします。'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '通報する',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 友達解除
  Future<void> _removeFriend(String peerId, String peerName) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(FirebaseFirestore.instance.collection('users').doc(myId), {
      'friends': FieldValue.arrayRemove([peerId]),
    });
    batch.update(FirebaseFirestore.instance.collection('users').doc(peerId), {
      'friends': FieldValue.arrayRemove([myId]),
    });
    await batch.commit();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$peerName さんの登録を解除しました')));
  }

  // 友達申請の承認
  Future<void> _acceptFriendRequest(
    String userId,
    String name,
    String requestId,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(FirebaseFirestore.instance.collection('users').doc(myId), {
      'friends': FieldValue.arrayUnion([userId]),
    });
    batch.update(FirebaseFirestore.instance.collection('users').doc(userId), {
      'friends': FieldValue.arrayUnion([myId]),
    });
    batch.delete(
      FirebaseFirestore.instance.collection('friend_requests').doc(requestId),
    );
    await batch.commit();
    setState(() => _selectedMenu = '友達一覧');
  }

  // --- ブロック確認ダイアログ ---
  void _showBlockConfirmation(
    BuildContext context,
    String peerId,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name さんをブロック'),
        content: const Text(
          'ブロックすると、お互いのリストに表示されなくなり、メッセージのやり取りもできなくなります。よろしいですか？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _blockUser(peerId, name);
            },
            child: const Text(
              'ブロックする',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- ブロック実行 (Firestore更新) ---
  Future<void> _blockUser(String peerId, String peerName) async {
    final batch = FirebaseFirestore.instance.batch();

    // 1. 自分の「ブロックリスト(blocks)」に追加し、友達から削除
    batch.update(FirebaseFirestore.instance.collection('users').doc(myId), {
      'blocks': FieldValue.arrayUnion([peerId]),
      'friends': FieldValue.arrayRemove([peerId]),
    });

    // 2. 相手の「ブロックされたリスト(blockedBy)」に追加し、友達から削除
    batch.update(FirebaseFirestore.instance.collection('users').doc(peerId), {
      'blockedBy': FieldValue.arrayUnion([myId]),
      'friends': FieldValue.arrayRemove([myId]),
    });

    try {
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$peerName さんをブロックしました')));
      }
    } catch (e) {
      debugPrint('Block Error: $e');
    }
  }
}
