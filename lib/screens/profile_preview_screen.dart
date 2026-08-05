import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // クリップボード用
import 'package:matching_app/constants/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 自分のID取得用

class ProfilePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const ProfilePreviewScreen({super.key, required this.data});

  @override
  State<ProfilePreviewScreen> createState() => _ProfilePreviewScreenState();
}

class _ProfilePreviewScreenState extends State<ProfilePreviewScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --- ヘルパー：有効な値があるかチェックするロジック ---
  bool _hasValue(dynamic value) {
    if (value == null ||
        value.toString().trim().isEmpty ||
        value.toString() == '未設定' ||
        value.toString() == '未入力') {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const Color accentPink = Color(0xFFFF8A80);

    final List<dynamic> rawImages = widget.data['imageUrls'] ?? [];
    final List<dynamic> displayList = rawImages
        .where((img) => img != null)
        .toList();

    // 自分の本来のUIDを取得し、最初の8文字を切り出す
    final String fullId = FirebaseAuth.instance.currentUser?.uid ?? '--------';
    final String shortId = fullId.length >= 8 ? fullId.substring(0, 8) : fullId;

    // 価値観シートのデータ取得
    final Map<String, dynamic> valuesData = Map<String, dynamic>.from(
      widget.data['values'] ?? {},
    );

    // --- セクションごとの表示判定用リスト作成 ---
    // 💡 削除された不要な項目（資格・サークルなど）を排除し、本当に必要な項目にスリム化！
    final List<Widget> basicInfoTiles = [];
    if (_hasValue(widget.data['gender'])) {
      basicInfoTiles.add(
        _buildDetailTile(Icons.wc, '性別', widget.data['gender']),
      );
    }
    if (_hasValue(widget.data['location'])) {
      basicInfoTiles.add(
        _buildDetailTile(Icons.location_on, '居住地', widget.data['location']),
      );
    }
    if (_hasValue(widget.data['school'])) {
      basicInfoTiles.add(
        _buildDetailTile(Icons.school, '学校', widget.data['school']),
      );
    }
    if (_hasValue(widget.data['work'])) {
      basicInfoTiles.add(
        _buildDetailTile(Icons.work, '職業', widget.data['work']),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'プレビュー',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 画像エリア
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: screenWidth,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: displayList.isEmpty ? 1 : displayList.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) {
                      if (displayList.isEmpty) {
                        return Container(
                          width: screenWidth,
                          color: Colors.grey[200],
                          child: Center(
                            child: Icon(
                              Icons.person,
                              size: 100,
                              color: Colors.grey[400],
                            ),
                          ),
                        );
                      }

                      final item = displayList[index];
                      return Container(
                        width: screenWidth,
                        color: Colors.grey[200],
                        child: item is File
                            ? Image.file(item, fit: BoxFit.cover)
                            : Image.network(item.toString(), fit: BoxFit.cover),
                      );
                    },
                  ),
                ),
                if (displayList.length > 1)
                  Positioned(
                    bottom: 35,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        displayList.length,
                        (index) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index
                                ? AppColors.point
                                : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            Container(
              transform: Matrix4.translationValues(0, -20, 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- ID表示 & タップでコピー ---
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                              ClipboardData(text: fullId),
                            ); // コピーはフルID
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('ID: $shortId... をコピーしました'),
                                backgroundColor: Colors.black87,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'ID: $shortId',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '${widget.data['name'] ?? '名前'}${_hasValue(widget.data['age']) ? ' (${widget.data['age']})' : ''}',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_hasValue(widget.data['gender'])) ...[
                              Builder(
                                builder: (context) {
                                  final gender = widget.data['gender'];

                                  // 色とアイコンの定義
                                  final Color bgColor = gender == '男性'
                                      ? Colors.blue.withOpacity(0.15)
                                      : (gender == '女性'
                                            ? Colors.pink.withOpacity(0.15)
                                            : Colors.grey.withOpacity(0.15));

                                  final Color iconColor = gender == '男性'
                                      ? Colors.blue
                                      : (gender == '女性'
                                            ? Colors.pink
                                            : Colors.grey);

                                  final IconData iconData = gender == '男性'
                                      ? Icons.male
                                      : (gender == '女性'
                                            ? Icons.female
                                            : Icons.transgender);

                                  return Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      iconData,
                                      color: iconColor,
                                      size: 18,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // タグ
                  if (widget.data['tags'] != null &&
                      (widget.data['tags'] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 0,
                      ),
                      child: Wrap(
                        spacing: 5.0,
                        runSpacing: 0.0,
                        children: (widget.data['tags'] as List)
                            .map(
                              (tag) => _buildTag(tag.toString(), AppColors.tag),
                            )
                            .toList(),
                      ),
                    ),

                  // 自己紹介
                  if (_hasValue(widget.data['bio'])) ...[
                    _buildSectionTitle('自己紹介'),
                    _buildContent(widget.data['bio']),
                  ],

                  if (_hasValue(widget.data['hobby'])) ...[
                    _buildSectionTitle('趣味・好きなこと'),
                    _buildContent(widget.data['hobby']),
                  ],
                  if (_hasValue(widget.data['hobbyDetail'])) ...[
                    _buildSectionTitle('趣味・好きなことの詳細'),
                    _buildContent(widget.data['hobbyDetail']),
                  ],
                  if (_hasValue(widget.data['idealFriend'])) ...[
                    _buildSectionTitle('どんな友達が欲しい？'),
                    _buildContent(widget.data['idealFriend']),
                  ],

                  // 基本情報
                  if (basicInfoTiles.isNotEmpty) ...[
                    _buildSectionTitle('基本情報'),
                    _buildInfoContainer(basicInfoTiles),
                  ],

                  _buildSectionTitle('その他プロフィール'),
                  _buildInfoContainer([
                    if (_hasValue(widget.data['favoriteFood']))
                      _buildDetailTile(
                        Icons.restaurant,
                        '好きな食べ物',
                        widget.data['favoriteFood'],
                      ),
                    if (_hasValue(widget.data['dislikeFood']))
                      _buildDetailTile(
                        Icons.no_food,
                        '苦手な食べ物',
                        widget.data['dislikeFood'],
                      ),
                    if (_hasValue(widget.data['artist']))
                      _buildDetailTile(
                        Icons.music_note,
                        '好きなアーティスト',
                        widget.data['artist'],
                      ),
                    if (_hasValue(widget.data['game']))
                      _buildDetailTile(
                        Icons.sports_esports,
                        '好きなゲーム',
                        widget.data['game'],
                      ),
                    if (_hasValue(widget.data['anime']))
                      _buildDetailTile(
                        Icons.movie,
                        '好きなアニメ・漫画',
                        widget.data['anime'],
                      ),
                  ]),

                  // 💡 ライフスタイル・価値観シート
                  if (valuesData.isNotEmpty) ...[
                    _buildSectionTitle('ライフスタイル・価値観シート'),
                    _buildInfoContainer(
                      valuesData.entries.map((entry) {
                        return _buildDetailTile(
                          Icons.check_circle_outline,
                          entry.key,
                          entry.value,
                          isValueSheet: true,
                        );
                      }).toList(),
                    ),
                  ],

                  const SizedBox(height: 40), // 下部にスクロールの余裕を持たせる
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ヘルパー関数 ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildContent(dynamic text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text.toString(),
        style: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildInfoContainer(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16), // 下部余白を確保
        decoration: BoxDecoration(
          color: AppColors.gley,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(children: children),
      ),
    );
  }

  // 価値観シートのハイライトに対応できるよう引数拡張
  Widget _buildDetailTile(
    IconData icon,
    String label,
    dynamic value, {
    bool isValueSheet = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey, size: 20),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: AppColors.txt),
      ),
      subtitle: Text(
        value.toString(),
        style: TextStyle(
          fontSize: 15,
          fontWeight: isValueSheet ? FontWeight.bold : FontWeight.w500,
          color: isValueSheet ? AppColors.txt : Colors.black87,
        ),
      ),
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
    );
  }

  Widget _buildTag(String label, Color color) {
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      backgroundColor: Colors.white,
      side: BorderSide(color: color, width: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
