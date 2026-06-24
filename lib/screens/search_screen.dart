import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/profile_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  bool _isTwoColumn = true;
  // 検索文字を管理する変数
  String _searchKeyword = "";

  // フィルター用の状態
  int _minAge = 18;
  int _maxAge = 50;
  String _selectedGender = 'すべて';
  List<String> _selectedTags = [];

  // タブ選択の状態を管理する変数（デフォルト：おすすめ）
  String _selectedTab =
      'recommend'; // 'all' (ユーザー), 'recommend' (おすすめ), 'popular' (人気)
  bool _isManualSelection = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              _buildTabButton('ユーザー', 'all'),
              const SizedBox(width: 12),
              _buildTabButton('おすすめ', 'recommend'),
              const SizedBox(width: 12),
              _buildTabButton('人気', 'popular'),
              const Spacer(),
              const Text(
                'frendy',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontSize: 16,
                ),
              ),
              IconButton(
                icon: Icon(_isTwoColumn ? Icons.view_agenda : Icons.grid_view),
                onPressed: () => setState(() => _isTwoColumn = !_isTwoColumn),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(context),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return const Center(child: Text('エラーが発生しました'));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final String myId =
                    FirebaseAuth.instance.currentUser?.uid ?? '';

                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(myId)
                      .snapshots(),
                  builder: (context, mySnapshot) {
                    if (!mySnapshot.hasData)
                      return const Center(child: CircularProgressIndicator());

                    final myData =
                        mySnapshot.data!.data() as Map<String, dynamic>? ?? {};
                    final List<dynamic> myLikedList =
                        (myData['likedUserIds'] is List)
                        ? List<dynamic>.from(myData['likedUserIds'])
                        : [];
                    final List<dynamic> myBlockedList =
                        myData['blockedUsers'] ?? [];

                    // 趣味・嗜好に関連するすべてのフィールド一覧
                    final List<String> hobbyFields = [
                      'hobby',
                      'anime',
                      'youtube',
                      'game',
                      'artist',
                      'pet',
                      'brand',
                      'interests',
                    ];

                    final List<String> ignoreWords = [
                      'なし',
                      '未設定',
                      '特になし',
                      '未入力',
                      '設定なし',
                      'ありません',
                      '特になしです',
                    ];

                    // --- 自分の全趣味・嗜好フィールドから有効な単語を抽出してリスト化 ---
                    final List<String> myCleanHobbies = [];
                    for (var field in hobbyFields) {
                      final val = myData[field];
                      if (val == null) continue;

                      if (val is List) {
                        for (var item in val) {
                          final str = item.toString().trim().toLowerCase();
                          if (str.isNotEmpty && !ignoreWords.contains(str)) {
                            myCleanHobbies.add(str);
                          }
                        }
                      } else {
                        final str = val.toString().trim().toLowerCase();
                        if (str.isNotEmpty && !ignoreWords.contains(str)) {
                          myCleanHobbies.add(str);
                        }
                      }
                    }

                    // 1. 基本的なキーワード、年齢、性別、ブロック、自分除外の【フィルタリング】
                    List<QueryDocumentSnapshot>
                    docs = snapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final String userId = doc.id;

                      final List<dynamic> myBlocks = myData['blocks'] ?? [];
                      final List<dynamic> blockedBy = myData['blockedBy'] ?? [];

                      // 💡 自分のアカウントは除外
                      if (userId == myId) return false;
                      // 💡 ブロック関連アカウントは除外
                      if (myBlocks.contains(userId)) return false;
                      if (blockedBy.contains(userId)) return false;

                      // =======================================================
                      // 🔥【重要】プロフィール未設定ユーザーを検索画面から除外するフィルター
                      // =======================================================
                      final String name = (data['name'] ?? '')
                          .toString()
                          .trim();
                      final int age =
                          int.tryParse(data['age']?.toString() ?? '0') ?? 0;
                      final String bio = (data['bio'] ?? '').toString().trim();
                      final List<dynamic> imageUrls =
                          data['imageUrls'] as List? ?? [];

                      // 1. 名前が空、または初期値のままの場合は非表示
                      if (name.isEmpty || name == '名前未設定' || name == 'ユーザー') {
                        return false;
                      }
                      // 2. 年齢が未登録、または 0 歳の場合は非表示
                      if (age <= 0) {
                        return false;
                      }
                      // 3. 写真が1枚も登録されていないユーザーは非表示
                      if (imageUrls.isEmpty) {
                        return false;
                      }
                      // 4. 自己紹介文が空のままのユーザーは非表示
                      if (bio.isEmpty) {
                        return false;
                      }
                      // =======================================================

                      final query = _searchKeyword.toLowerCase();
                      bool _contains(dynamic value) {
                        if (value == null) return false;
                        if (value is List) {
                          return value.any(
                            (item) =>
                                item.toString().toLowerCase().contains(query),
                          );
                        }
                        return value.toString().toLowerCase().contains(query);
                      }

                      final bool matchesKeyword =
                          _searchKeyword.isEmpty ||
                          (doc.id.toLowerCase().contains(query) ||
                              _contains(data['name']) ||
                              _contains(data['location']) ||
                              _contains(data['bio']) ||
                              _contains(data['interests']) ||
                              _contains(data['targetFriend']) ||
                              _contains(data['school']) ||
                              _contains(data['work']) ||
                              _contains(data['qualification']) ||
                              _contains(data['club']) ||
                              _contains(data['hobby']) ||
                              _contains(data['pet']) ||
                              _contains(data['anime']) ||
                              _contains(data['artist']) ||
                              _contains(data['youtube']) ||
                              _contains(data['game']) ||
                              _contains(data['brand']) ||
                              _contains(data['tags']));

                      final int userAge =
                          int.tryParse(data['age']?.toString() ?? '0') ?? 0;
                      final bool matchesAge =
                          (userAge == 0) ||
                          (userAge >= _minAge && userAge <= _maxAge);

                      final String userGender = data['gender'] ?? '未設定';
                      final bool matchesGender =
                          _selectedGender == 'すべて' ||
                          userGender == _selectedGender;

                      final List<dynamic> userTags =
                          data['tags'] as List? ?? [];
                      final bool matchesFilterTags =
                          _selectedTags.isEmpty ||
                          _selectedTags.every((tag) => userTags.contains(tag));

                      return matchesKeyword &&
                          matchesAge &&
                          matchesGender &&
                          matchesFilterTags;
                    }).toList();

                    // --- 相手との共通趣味・嗜好スコアを算出するヘルパー関数 ---
                    int getHobbyMatchScore(Map<String, dynamic> targetData) {
                      int score = 0;

                      // 相手の趣味・嗜好に関するテキストを一括で結合
                      StringBuffer targetBuffer = StringBuffer();
                      for (var field in hobbyFields) {
                        final val = targetData[field];
                        if (val == null) continue;
                        if (val is List) {
                          targetBuffer.write(' ${val.join(' ')}');
                        } else {
                          targetBuffer.write(' $val');
                        }
                      }
                      final targetText = targetBuffer.toString().toLowerCase();

                      // 自分の抽出した趣味単語が相手のテキストに含まれているか走査
                      for (var myHobby in myCleanHobbies) {
                        if (targetText.contains(myHobby)) {
                          score++;
                        }
                      }
                      return score;
                    }

                    // 2. 選択されたタブ（_selectedTab）に応じた【除外】および【ソート】
                    if (_selectedTab == 'recommend') {
                      // おすすめ条件（共通趣味スコアが1以上）でフィルタリング
                      final recommendDocs = docs.where((doc) {
                        final targetData = doc.data() as Map<String, dynamic>;
                        return getHobbyMatchScore(targetData) > 0;
                      }).toList();

                      // 💡 自分のプロフィール（趣味・嗜好）が未設定、または手動選択以外でおすすめが0人の場合
                      if (myCleanHobbies.isEmpty ||
                          (recommendDocs.isEmpty && !_isManualSelection)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && _selectedTab == 'recommend') {
                            setState(() {
                              _selectedTab = 'all'; // 『ユーザー』タブに自動変更
                            });
                          }
                        });
                      } else {
                        // プロフィールが設定されていて、おすすめユーザーが存在する場合
                        docs = recommendDocs;
                        docs.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          return getHobbyMatchScore(
                            bData,
                          ).compareTo(getHobbyMatchScore(aData));
                        });
                      }
                    } else if (_selectedTab == 'popular') {
                      // 【人気順】いいね数（likeCount）が多い順にソート
                      docs.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final int aLikes =
                            int.tryParse(
                              aData['likeCount']?.toString() ?? '0',
                            ) ??
                            0;
                        final int bLikes =
                            int.tryParse(
                              bData['likeCount']?.toString() ?? '0',
                            ) ??
                            0;
                        return bLikes.compareTo(aLikes);
                      });
                    } else {
                      // 【ユーザー】最終ログイン順（lastLoginTime）が新しい順にソート
                      docs.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;

                        final Timestamp? aTime =
                            aData['lastLoginTime'] as Timestamp?;
                        final Timestamp? bTime =
                            bData['lastLoginTime'] as Timestamp?;

                        if (aTime == null && bTime == null) return 0;
                        if (aTime == null) return 1;
                        if (bTime == null) return -1;

                        return bTime.compareTo(aTime);
                      });
                    }

                    if (docs.isEmpty) {
                      return const Center(
                        child: Text(
                          '見つかりませんでした',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      );
                    }

                    return _isTwoColumn
                        ? GridView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.65,
                                ),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data =
                                  docs[index].data() as Map<String, dynamic>;
                              return _buildModernUserCard(
                                context,
                                userId: docs[index].id,
                                data: data,
                                myLikedList: myLikedList,
                              );
                            },
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final data =
                                  docs[index].data() as Map<String, dynamic>;
                              return _buildOneColumnCard(
                                context,
                                userId: docs[index].id,
                                data: data,
                              );
                            },
                          );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 1カラム（リスト形式）用のカードウィジェット
  Widget _buildOneColumnCard(
    BuildContext context, {
    required String userId,
    required Map<String, dynamic> data,
  }) {
    final String name = data['name'] ?? '名前なし';
    final String age = data['age']?.toString() ?? '--';
    final String gender = data['gender'] ?? '未設定';
    final String bio = data['bio'] ?? '未設定';
    final String interests = data['interests'] ?? '未設定';
    final String target = data['targetFriend'] ?? '未設定';
    final String? imageUrl = (data['imageUrls'] as List?)?.isNotEmpty == true
        ? data['imageUrls'][0]
        : null;

    final IconData genderIcon = gender == '男性'
        ? Icons.male
        : (gender == '女性' ? Icons.female : Icons.transgender);
    final Color genderColor = gender == '男性'
        ? Colors.blue
        : (gender == '女性' ? Colors.pink : Colors.purple);

    final double screenWidth = MediaQuery.of(context).size.width;
    final int cacheWidth =
        (screenWidth * MediaQuery.of(context).devicePixelRatio).round();

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ProfileDetailScreen(userData: data, userId: userId),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 画像エリア
            SizedBox(
              height: 280,
              width: double.infinity,
              child: imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: cacheWidth,
                      placeholder: (context, url) =>
                          Container(color: Colors.grey[50]),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[100],
                        child: const Icon(
                          Icons.broken_image,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: const Icon(
                        Icons.person,
                        size: 80,
                        color: Colors.grey,
                      ),
                    ),
            ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 24,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$age歳',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                      ),
                      if (gender != '未設定' && gender.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Icon(genderIcon, color: genderColor, size: 20),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSectionTitle("自己紹介"),
                  Text(
                    bio,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("ハマっていること"),
                  Text(
                    interests,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSectionTitle("欲しい友達のタイプ"),
                  Text(
                    target,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 2カラム（グリッド形式）用のカードウィジェット
  Widget _buildModernUserCard(
    BuildContext context, {
    required String userId,
    required Map<String, dynamic> data,
    required List<dynamic> myLikedList,
  }) {
    final String name = data['name'] ?? '名前なし';
    final String age = data['age']?.toString() ?? '--';
    final String location = data['location'] ?? '未設定';
    final String interests = data['interests'] ?? '最近ハマってることはまだありません。';
    final String? imageUrl = (data['imageUrls'] as List?)?.isNotEmpty == true
        ? data['imageUrls'][0]
        : null;

    final double gridWidth = MediaQuery.of(context).size.width / 2;
    final int cacheWidth = (gridWidth * MediaQuery.of(context).devicePixelRatio)
        .round();

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                ProfileDetailScreen(userData: data, userId: userId),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        memCacheWidth: cacheWidth,
                        placeholder: (context, url) =>
                            Container(color: Colors.grey[50]),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[100],
                          child: const Icon(
                            Icons.broken_image,
                            size: 24,
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.grey[100],
                        child: const Center(
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                      ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$age歳',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (data.containsKey('gender')) ...[
                          const SizedBox(width: 4),
                          Builder(
                            builder: (context) {
                              final gender = data['gender'];
                              final Color bgColor = gender == '男性'
                                  ? Colors.blue.withOpacity(0.15)
                                  : (gender == '女性'
                                        ? Colors.pink.withOpacity(0.15)
                                        : Colors.purple.withOpacity(0.15));
                              final Color iconColor = gender == '男性'
                                  ? Colors.blue
                                  : (gender == '女性'
                                        ? Colors.pink
                                        : Colors.purple);
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
                                child: Icon(
                                  iconData,
                                  color: iconColor,
                                  size: 12,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          size: 14,
                          color: AppColors.point,
                        ),
                        const SizedBox(width: 2),
                        Text(location, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: Text(
                        interests,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.point,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, String tabValue) {
    final bool isSelected = _selectedTab == tabValue;
    return GestureDetector(
      onTap: () {
        setState(() {
          _isManualSelection = true;
          _selectedTab = tabValue;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.black87 : Colors.black38,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            height: 2,
            width: 24,
            color: isSelected ? AppColors.point : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (value) => setState(() => _searchKeyword = value),
              decoration: InputDecoration(
                hintText: 'キーワードで検索',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.grey,
                  size: 22,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.tune, color: Colors.blueGrey),
              onPressed: () => _showFilterSheet(context),
            ),
          ),
        ],
      ),
    );
  }

  // 検索フィルター用ボトムシート（後半のコードが省略されていたため、完全に動作するように補完）
  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              height: MediaQuery.of(context).size.height * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '検索フィルター',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '性別',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['すべて', '男性', '女性', 'その他']
                          .map(
                            (g) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(g),
                                selected: _selectedGender == g,
                                selectedColor: AppColors.point.withOpacity(0.2),
                                onSelected: (val) {
                                  setSheetState(() => _selectedGender = g);
                                  setState(() {});
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '年齢範囲',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '$_minAge歳 〜 $_maxAge歳',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.point,
                          ),
                        ),
                      ],
                    ),
                    RangeSlider(
                      values: RangeValues(
                        _minAge.toDouble(),
                        _maxAge.toDouble(),
                      ),
                      min: 18,
                      max: 80,
                      divisions: 62,
                      activeColor: AppColors.point,
                      inactiveColor: Colors.grey[200],
                      labels: RangeLabels('$_minAge歳', '$_maxAge歳'),
                      onChanged: (RangeValues values) {
                        setSheetState(() {
                          _minAge = values.start.round();
                          _maxAge = values.end.round();
                        });
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '適用する',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
