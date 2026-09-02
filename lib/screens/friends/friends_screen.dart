import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/profile/profile_detail_screen.dart';
import 'package:matching_app/screens/subscription/subscription_screen.dart';

// 💡 ユーザー一括取得結果のキャッシュ用コンテナ。
//    同じID集合であれば再フェッチせず使い回すことで、
//    無関係な状態更新のたびにFirestoreへ再読み込みしに行くのを防ぐ
class _CachedUserFetch {
  final String idsSignature;
  final Future<Map<String, Map<String, dynamic>>> future;
  _CachedUserFetch(this.idsSignature, this.future);
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  String _selectedMenu = '友達一覧';
  final String myId = FirebaseAuth.instance.currentUser?.uid ?? '';

  static const Duration _networkTimeout = Duration(seconds: 20);
  static const int _whereInChunkSize = 30; // FirestoreのwhereIn上限に合わせる

  // 💡 リストごとのユーザー情報キャッシュ（友達一覧／申請一覧／いいね等を個別管理）
  final Map<String, _CachedUserFetch> _fetchCaches = {};

  // 💡 処理中の友達申請IDを保持し、二重承認・二重拒否を防ぐ
  final Set<String> _processingRequestIds = {};

  // --- Firestoreからユーザー情報をまとめて取得する（N+1問題対策） ---
  Future<Map<String, Map<String, dynamic>>> _fetchUsersByIds(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return {};

    final Map<String, Map<String, dynamic>> result = {};

    // 💡 FirestoreのwhereInは最大30件までのため、チャンクに分割してまとめて取得する。
    //    1件ずつ取得する場合に比べ、ネットワークのラウンドトリップ回数を大幅に削減できる
    for (int i = 0; i < ids.length; i += _whereInChunkSize) {
      final int end = (i + _whereInChunkSize < ids.length)
          ? i + _whereInChunkSize
          : ids.length;
      final List<String> chunk = ids.sublist(i, end);

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(_networkTimeout);

        for (final doc in snapshot.docs) {
          result[doc.id] = doc.data();
        }
      } catch (e) {
        debugPrint('ユーザー一括取得エラー: $e');
        // 💡 一部チャンクの取得に失敗しても、他の結果は表示できるよう処理を継続する
      }
    }
    return result;
  }

  // 💡 ID集合が前回と同じであれば、Futureを再生成せずキャッシュを返す
  Future<Map<String, Map<String, dynamic>>> _getUsersCached(
    String cacheKey,
    List<String> ids,
  ) {
    final String idsSignature = (List<String>.from(ids)..sort()).join(',');
    final _CachedUserFetch? existing = _fetchCaches[cacheKey];

    if (existing != null && existing.idsSignature == idsSignature) {
      return existing.future;
    }

    final Future<Map<String, Map<String, dynamic>>> future = _fetchUsersByIds(
      ids,
    );
    _fetchCaches[cacheKey] = _CachedUserFetch(idsSignature, future);
    return future;
  }

  // 💡 「本当にpending状態の申請だけ」を数えるための共通ヘルパー。
  //    ・重複送信などで同じ相手から複数のpendingリクエストが残っている場合は
  //      送信者(fromId)単位で重複排除する
  //    ・Firestoreのクエリ結果をそのまま信用せず、statusフィールドの値を
  //      クライアント側でも再確認し、意図しない型・表記のデータを弾く
  List<QueryDocumentSnapshot> _dedupedPendingRequests(
    List<QueryDocumentSnapshot> docs,
  ) {
    final Map<String, QueryDocumentSnapshot> uniqueBySender = {};

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final String status = (data['status'] ?? '').toString();
      if (status != 'pending') continue; // 💡 念のためクライアント側でも再検証

      final String? fromId = data['fromId'] as String?;
      if (fromId == null || fromId.isEmpty) continue;

      // 💡 同じ送信者からの重複した申請は最初の1件だけを残す
      uniqueBySender.putIfAbsent(fromId, () => doc);
    }

    return uniqueBySender.values.toList();
  }

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
    // 💡 myIdが空（未ログイン等）の状態でクエリを投げないようにする。
    //    空文字列でのisEqualTo検索が、想定外のデータにマッチしてしまうのを防ぐ
    if (myId.isEmpty) {
      return _buildMenuItem('友達申請', Icons.person_add);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('toId', isEqualTo: myId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        // 💡 エラー時は通知が出しっぱなしにならないよう、必ず0件扱いにする
        if (snapshot.hasError) {
          debugPrint('友達申請の取得エラー: ${snapshot.error}');
          return _buildMenuItem('友達申請', Icons.person_add);
        }

        // 💡 クエリ結果をそのまま件数として使わず、
        //    重複送信や不正な形式のデータを除いた「実際に有効な申請数」を数える
        final int requestCount = snapshot.hasData
            ? _dedupedPendingRequests(snapshot.data!.docs).length
            : 0;

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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final myData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final List<String> friendsIds = List<String>.from(
          myData['friends'] ?? [],
        );

        if (friendsIds.isEmpty) {
          return const Center(
            child: Text('まだ友達がいません', style: TextStyle(color: Colors.grey)),
          );
        }

        // 💡 1件ずつ取得するのではなく、まとめて取得してN+1問題を回避する
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _getUsersCached('friends', friendsIds),
          builder: (context, userMapSnap) {
            if (!userMapSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final Map<String, Map<String, dynamic>> userMap = userMapSnap.data!;

            return ListView.builder(
              itemCount: friendsIds.length,
              itemBuilder: (context, index) {
                final String peerId = friendsIds[index];
                final userData = userMap[peerId];

                // 💡 退会済み等でユーザー情報が取得できない場合は表示をスキップする
                if (userData == null) return const SizedBox.shrink();

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

  // --- 2. 友達申請リスト ---
  Widget _buildRequestList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('friend_requests')
          .where('toId', isEqualTo: myId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('友達申請一覧の取得エラー: ${snapshot.error}');
          return const Center(
            child: Text('エラーが発生しました', style: TextStyle(color: Colors.grey)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // 💡 通知バッジと同じロジックで重複排除・再検証し、表示件数を一致させる
        final docs = _dedupedPendingRequests(snapshot.data!.docs);
        if (docs.isEmpty) {
          return const Center(
            child: Text('届いている申請はありません', style: TextStyle(color: Colors.grey)),
          );
        }

        final List<String> fromIds = docs
            .map((d) => (d.data() as Map<String, dynamic>)['fromId'] as String)
            .toList();

        // 💡 各申請者の情報も個別取得ではなく一括取得する
        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _getUsersCached('requests', fromIds),
          builder: (context, userMapSnap) {
            if (!userMapSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final Map<String, Map<String, dynamic>> userMap = userMapSnap.data!;

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final requestData = docs[index].data() as Map<String, dynamic>;
                final String fromId = requestData['fromId'];
                final String requestId = docs[index].id;
                final userData = userMap[fromId];

                if (userData == null) return const SizedBox.shrink();

                final String name = userData['name'] ?? 'ユーザー';
                final String imageUrl =
                    (userData['imageUrls'] as List?)?.isNotEmpty == true
                    ? userData['imageUrls'][0]
                    : '';

                final bool isProcessing = _processingRequestIds.contains(
                  requestId,
                );

                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: imageUrl.isNotEmpty
                        ? NetworkImage(imageUrl)
                        : null,
                  ),
                  title: Text(name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 💡 拒否ボタン：ユーザーが自分で申請を消せる手段がなかったため追加。
                      //    これがないと、承認したくない申請がいつまでも通知に残り続けてしまう
                      IconButton(
                        icon: isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.close,
                                color: Colors.grey,
                                size: 20,
                              ),
                        onPressed: isProcessing
                            ? null
                            : () => _declineFriendRequest(name, requestId),
                        tooltip: '拒否する',
                      ),
                      SizedBox(
                        width: 64,
                        height: 30,
                        child: ElevatedButton(
                          onPressed: isProcessing
                              ? null
                              : () => _acceptFriendRequest(
                                  fromId,
                                  name,
                                  requestId,
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.bg,
                            disabledBackgroundColor: Colors.grey[300],
                            elevation: 0,
                            minimumSize: const Size(64, 30),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: isProcessing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  '承認',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
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
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final myData = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        final List<dynamic> rawIds = myData[fieldName] ?? [];
        final List<dynamic> myBlocks = myData['blocks'] ?? [];
        final List<dynamic> blockedBy = myData['blockedBy'] ?? [];

        // 💡 ブロック済み・ブロックされたユーザーは、いいね/足跡一覧からも除外する。
        //    ブロック機能の「お互いのリストに表示されなくなる」という仕様に合わせるための修正
        final List<String> userIds = rawIds
            .map((e) => e.toString())
            .where((id) => !myBlocks.contains(id) && !blockedBy.contains(id))
            .toList();

        if (userIds.isEmpty) {
          return Center(
            child: Text(
              emptyMessage,
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }

        // 💡 リアルタイムのFirestoreスナップショットから直接プランを判定
        //    → プラン変更が即座に反映され、ホットリロード不要になる
        final String livePlan = myData['plan'] ?? 'free';

        // 💡 足跡タブ：フリープランのみモザイク（ライト以降で解除）
        // 💡 いいねタブ：フリー・ライトプランはモザイク（スタンダード以降で解除）
        final bool shouldBlur =
            (isFootprints && livePlan == 'free') ||
            (isLikeList && (livePlan == 'free' || livePlan == 'light'));

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _getUsersCached(fieldName, userIds),
          builder: (context, userMapSnap) {
            if (!userMapSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final Map<String, Map<String, dynamic>> userMap = userMapSnap.data!;

            return ListView.builder(
              itemCount: userIds.length,
              itemBuilder: (context, index) {
                final String peerId = userIds[index];
                final userData = userMap[peerId];
                if (userData == null) return const SizedBox.shrink();

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
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool isSubmitting = false;

          Future<void> handleSubmit() async {
            final String reason = reportController.text.trim();
            if (reason.isEmpty || isSubmitting) return;

            setDialogState(() => isSubmitting = true);

            try {
              await FirebaseFirestore.instance
                  .collection('reports')
                  .add({
                    'reporterId': currentUserId,
                    'reportedId': peerId,
                    'reason': reason,
                    'createdAt': FieldValue.serverTimestamp(),
                  })
                  .timeout(_networkTimeout);

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('報告ありがとうございます。運営で確認いたします。'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            } catch (e) {
              debugPrint('通報送信エラー: $e');
              setDialogState(() => isSubmitting = false);
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('通報の送信に失敗しました。もう一度お試しください。'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: reportController,
                  maxLines: 4,
                  maxLength: 500,
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
                      onPressed: isSubmitting
                          ? null
                          : () => Navigator.pop(dialogContext),
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
                      onPressed: isSubmitting ? null : handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '通報する',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // 友達解除
  Future<void> _removeFriend(String peerId, String peerName) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('users').doc(myId), {
        'friends': FieldValue.arrayRemove([peerId]),
      });
      batch.update(FirebaseFirestore.instance.collection('users').doc(peerId), {
        'friends': FieldValue.arrayRemove([myId]),
      });
      await batch.commit().timeout(_networkTimeout);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$peerName さんの登録を解除しました')));
      }
    } catch (e) {
      debugPrint('友達解除エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('解除に失敗しました。もう一度お試しください。')));
      }
    }
  }

  // 友達申請の承認（トランザクションで二重承認を防止）
  Future<void> _acceptFriendRequest(
    String userId,
    String name,
    String requestId,
  ) async {
    if (_processingRequestIds.contains(requestId)) return;
    setState(() => _processingRequestIds.add(requestId));

    try {
      await FirebaseFirestore.instance
          .runTransaction((transaction) async {
            final requestRef = FirebaseFirestore.instance
                .collection('friend_requests')
                .doc(requestId);
            final requestSnap = await transaction.get(requestRef);

            // 💡 既に他の操作で処理済みの申請でないかをトランザクション内で確認する
            if (!requestSnap.exists) {
              throw Exception('この申請は既に処理されています');
            }
            final data = requestSnap.data() as Map<String, dynamic>;
            if (data['status'] != 'pending') {
              throw Exception('この申請は既に処理されています');
            }

            final myRef = FirebaseFirestore.instance
                .collection('users')
                .doc(myId);
            final peerRef = FirebaseFirestore.instance
                .collection('users')
                .doc(userId);

            transaction.update(myRef, {
              'friends': FieldValue.arrayUnion([userId]),
            });
            transaction.update(peerRef, {
              'friends': FieldValue.arrayUnion([myId]),
            });
            transaction.delete(requestRef);
          })
          .timeout(_networkTimeout);

      if (mounted) {
        setState(() => _selectedMenu = '友達一覧');
      }
    } catch (e) {
      debugPrint('友達申請承認エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('申請の承認に失敗しました。もう一度お試しください。')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(requestId));
      }
    }
  }

  // 💡 友達申請の拒否：ドキュメントを完全に削除し、通知バッジからも確実に消す。
  //    （statusを'rejected'に変えるだけだと、クエリの条件次第で
  //      カウントに残り続けるリスクがあるため、削除の方が確実）
  Future<void> _declineFriendRequest(String name, String requestId) async {
    if (_processingRequestIds.contains(requestId)) return;
    setState(() => _processingRequestIds.add(requestId));

    try {
      await FirebaseFirestore.instance
          .collection('friend_requests')
          .doc(requestId)
          .delete()
          .timeout(_networkTimeout);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name さんからの申請を削除しました')));
      }
    } catch (e) {
      debugPrint('友達申請拒否エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作に失敗しました。もう一度お試しください。')));
      }
    } finally {
      if (mounted) {
        setState(() => _processingRequestIds.remove(requestId));
      }
    }
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
    try {
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

      await batch.commit().timeout(_networkTimeout);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$peerName さんをブロックしました')));
      }
    } catch (e) {
      debugPrint('ブロックエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ブロックに失敗しました。もう一度お試しください。')),
        );
      }
    }
  }
}
