import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matching_app/constants/app_colors.dart';

// ============================================================================
// プロフィールのプレビュー（自分のプロフィールが他の人にどう見えるか）
//
// 💡 この画面は Firestore を読み書きしない（渡されたデータを表示するだけ）。
//    そのため、ユーザー数が増えてもサーバーの負担は増えない。
//    気をつけるのは「おかしなデータが来てもクラッシュしないこと」と
//    「画像でメモリを使いすぎないこと」の2点。
// ============================================================================

const int _kMaxImages = 6; // 画像は最大6枚まで表示
const int _kMaxTags = 30; // タグは最大30個まで表示
const int _kMaxTextLength = 1000; // 1つの欄に表示する最大文字数

class ProfilePreviewScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const ProfilePreviewScreen({super.key, required this.data});

  @override
  State<ProfilePreviewScreen> createState() => _ProfilePreviewScreenState();
}

class _ProfilePreviewScreenState extends State<ProfilePreviewScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // 💡 表示用データは最初に1回だけ整える（画面を動かすたびに作り直さない）
  late final List<Object> _images; // File（選択直後の画像）または https のURL
  late final List<String> _tags;
  late final List<MapEntry<String, String>> _values;
  late final String _fullId;
  late final String _shortId;

  @override
  void initState() {
    super.initState();
    _images = _parseImages(widget.data['imageUrls']);
    _tags = _parseTags(widget.data['tags']);
    _values = _parseValues(widget.data['values']);

    _fullId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _shortId = _fullId.length >= 8 ? _fullId.substring(0, 8) : _fullId;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // データを安全に取り出すヘルパー
  // 💡 型が違うデータ（数値・null・配列など）が入っていてもクラッシュしない
  // --------------------------------------------------------------------------

  /// 表示できる文字があれば返す。なければ null。
  String? _text(dynamic value) {
    if (value == null) return null;
    if (value is! String && value is! num) return null;
    final s = value.toString().trim();
    if (s.isEmpty || s == '未設定' || s == '未入力') return null;
    return s.length > _kMaxTextLength
        ? '${s.substring(0, _kMaxTextLength)}…'
        : s;
  }

  List<Object> _parseImages(dynamic raw) {
    if (raw is! List) return const [];
    final result = <Object>[];
    for (final item in raw) {
      if (item is File) {
        result.add(item);
      } else if (item is String && item.startsWith('https://')) {
        // 💡 https 以外（http や不明な形式）は表示しない
        result.add(item);
      }
      if (result.length >= _kMaxImages) break;
    }
    return result;
  }

  List<String> _parseTags(dynamic raw) {
    if (raw is! List) return const [];
    return raw.map(_text).whereType<String>().take(_kMaxTags).toList();
  }

  List<MapEntry<String, String>> _parseValues(dynamic raw) {
    if (raw is! Map) return const [];
    final result = <MapEntry<String, String>>[];
    raw.forEach((key, value) {
      final k = _text(key);
      final v = _text(value);
      if (k != null && v != null) result.add(MapEntry(k, v));
    });
    return result;
  }

  void _copyId() {
    if (_fullId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _fullId));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('ID: $_shortId... をコピーしました'),
          backgroundColor: Colors.black87,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    // 💡 画面の幅に合わせて縮小して読み込む（元の大きな画像のままだとメモリを大量に使う）
    final int cacheWidth =
        (screenWidth * MediaQuery.devicePixelRatioOf(context)).round();

    final String? name = _text(widget.data['name']);
    final String? age = _text(widget.data['age']);
    final String? gender = _text(widget.data['gender']);
    final String? location = _text(widget.data['location']);
    final String? school = _text(widget.data['school']);
    final String? work = _text(widget.data['work']);
    final String? hobby = _text(widget.data['hobby']);
    final String? recentInterest = _text(widget.data['recentInterest']);
    final String? idealFriend = _text(widget.data['idealFriend']);
    final String? holidayActivity = _text(widget.data['holidayActivity']);
    final String? ngThings = _text(widget.data['ngThings']);

    final List<Widget> basicInfoTiles = [
      if (gender != null) _buildDetailTile(Icons.wc, '性別', gender),
      if (location != null)
        _buildDetailTile(Icons.location_on, '居住地', location),
      if (school != null) _buildDetailTile(Icons.school, '学校', school),
      if (work != null) _buildDetailTile(Icons.work, '職業', work),
    ];

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
                    itemCount: _images.isEmpty ? 1 : _images.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) {
                      if (_images.isEmpty) return _placeholder(screenWidth);
                      return SizedBox(
                        width: screenWidth,
                        child: _buildImage(_images[index], cacheWidth),
                      );
                    },
                  ),
                ),
                if (_images.length > 1)
                  Positioned(
                    bottom: 35,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _images.length,
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
                        if (_fullId.isNotEmpty)
                          InkWell(
                            onTap: _copyId,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'ID: $_shortId',
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
                            Flexible(
                              child: Text(
                                '${name ?? 'ニックネーム'}${age != null ? ' ($age)' : ''}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (gender != null) _buildGenderBadge(gender),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // タグ
                  if (_tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 5.0,
                        runSpacing: 0.0,
                        children: _tags
                            .map((tag) => _buildTag(tag, AppColors.tag))
                            .toList(),
                      ),
                    ),

                  if (hobby != null) ...[
                    _buildSectionTitle('好きなこと・趣味'),
                    _buildContent(hobby),
                  ],
                  if (recentInterest != null) ...[
                    _buildSectionTitle('最近特にハマってること'),
                    _buildContent(recentInterest),
                  ],
                  if (idealFriend != null) ...[
                    _buildSectionTitle('どんな友達を作りたい？'),
                    _buildContent(idealFriend),
                  ],
                  if (holidayActivity != null) ...[
                    _buildSectionTitle('休日の過ごし方'),
                    _buildContent(holidayActivity),
                  ],
                  if (ngThings != null) ...[
                    _buildSectionTitle('NGなこと・苦手なこと'),
                    _buildContent(ngThings),
                  ],

                  // 基本情報
                  if (basicInfoTiles.isNotEmpty) ...[
                    _buildSectionTitle('基本情報'),
                    _buildInfoContainer(basicInfoTiles),
                  ],

                  // ライフスタイル・価値観シート
                  if (_values.isNotEmpty) ...[
                    _buildSectionTitle('ライフスタイル・価値観シート'),
                    _buildInfoContainer(
                      _values
                          .map(
                            (entry) => _buildDetailTile(
                              Icons.check_circle_outline,
                              entry.key,
                              entry.value,
                              isValueSheet: true,
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 画像
  // --------------------------------------------------------------------------

  Widget _placeholder(double width) {
    return Container(
      width: width,
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.person, size: 100, color: Colors.grey[400]),
      ),
    );
  }

  Widget _brokenImage() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: Icon(Icons.broken_image, size: 60, color: Colors.grey),
      ),
    );
  }

  Widget _buildImage(Object item, int cacheWidth) {
    if (item is File) {
      // 💡 選択直後のローカル画像。縮小して読み込み、読めなければ代替表示
      return Image.file(
        item,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => _brokenImage(),
      );
    }

    // 💡 CachedNetworkImage：一度読んだ画像は端末に保存され、
    //    次回からダウンロードしない（通信量と Storage の料金を節約）
    return CachedNetworkImage(
      imageUrl: item as String,
      fit: BoxFit.cover,
      memCacheWidth: cacheWidth,
      placeholder: (_, __) => Container(
        color: Colors.grey[100],
        child: const Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.point,
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _brokenImage(),
    );
  }

  // --------------------------------------------------------------------------
  // その他の部品
  // --------------------------------------------------------------------------

  Widget _buildGenderBadge(String gender) {
    final MaterialColor? base = gender == '男性'
        ? Colors.blue
        : (gender == '女性' ? Colors.pink : null);
    final Color iconColor = base ?? Colors.grey;
    final IconData iconData = gender == '男性'
        ? Icons.male
        : (gender == '女性' ? Icons.female : Icons.transgender);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: iconColor, size: 18),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildContent(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
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
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        decoration: BoxDecoration(
          color: AppColors.gley,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildDetailTile(
    IconData icon,
    String label,
    String value, {
    bool isValueSheet = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blueGrey, size: 20),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13, color: AppColors.txt),
      ),
      subtitle: Text(
        value,
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
