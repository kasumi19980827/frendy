import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:matching_app/constants/app_tags.dart';
import 'package:matching_app/screens/profile/profile_preview_screen.dart';
import 'dart:typed_data';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  // --- コントローラー ---
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _locationController = TextEditingController();
  final _schoolController = TextEditingController();
  final _workController = TextEditingController();
  final _bioController = TextEditingController(); // 自己紹介 (任意)
  final _hobbyController = TextEditingController(); // 趣味・好きなこと (必須に変更)
  final _hobbyDetailController = TextEditingController();
  final _favoriteFoodController = TextEditingController();
  final _dislikeFoodController = TextEditingController();
  final _artistController = TextEditingController();
  final _gameController = TextEditingController();
  final _animeController = TextEditingController();
  final _idealFriendController = TextEditingController();

  List<String> _selectedTags = [];

  // --- 画像・タグ関連 ---
  final List<dynamic> _displayImages = List.filled(10, null);
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = false;
  String _selectedGender = '男性';

  Map<String, String> _myValues = {};

  // 💡 ライフスタイルに関する質問（任意のままでOK！）
  final Map<String, List<String>> _valueSheetQuestions = {
    'お休みの日': ['土日祝休み', '平日休み', 'シフト・不定休', '夜勤メイン'],
    '会うまでの希望': ['まずはメッセージから', 'まずは通話から', '気が合えば会いたい', '気軽にすぐ会いたい'],
    'お酒について': ['よく飲む', 'ときどき飲む', 'お付き合い程度', '全く飲まない'],
    'フットワーク': ['フッ軽（誘われればすぐ行く）', '予定をあらかじめ立てたい', '基本インドア'],
    '趣味にかけるお金の割合': ['給料の全て', '上限を決めている', 'お小遣いの範囲で'],
    '旅行・遠征の宿選び': ['寝れればOK（格安）', '立地重視（ビジホ）', '宿自体を楽しむ（ホテル・旅館）'],
    '理想の連絡頻度': ['毎日たくさん', '一日数回', '用事があるときだけ', '通話派'],
  };

  final OutlineInputBorder _greyBorderStyle = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: const BorderSide(color: Colors.grey),
  );

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _nameController.text = data['name'] ?? '';
        _ageController.text = data['age']?.toString() ?? '';
        _locationController.text = data['location'] ?? '';
        _schoolController.text = data['school'] ?? '';
        _workController.text = data['work'] ?? '';
        _hobbyController.text = data['hobby'] ?? '';
        _bioController.text = data['bio'] ?? '';
        _hobbyDetailController.text = data['hobbyDetail'] ?? '';
        _favoriteFoodController.text = data['favoriteFood'] ?? '';
        _dislikeFoodController.text = data['dislikeFood'] ?? '';
        _artistController.text = data['artist'] ?? '';
        _gameController.text = data['game'] ?? '';
        _animeController.text = data['anime'] ?? '';
        _idealFriendController.text = data['idealFriend'] ?? '';

        if (data['tags'] != null) {
          _selectedTags = List<String>.from(data['tags']);
        }

        _selectedGender = data['gender'] ?? '男性';
        if (data['values'] != null) {
          _myValues = Map<String, String>.from(data['values']);
        }

        if (data['imageUrls'] != null) {
          List<dynamic> urls = data['imageUrls'];
          for (int i = 0; i < urls.length && i < 10; i++) {
            _displayImages[i] = urls[i];
          }
        }
      });
    }
  }

  Future<void> _pickImage(int index) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (pickedFile != null) {
      setState(() => _displayImages[index] = File(pickedFile.path));
    }
  }

  void _removeImage(int index) {
    setState(() => _displayImages[index] = null);
  }

  // --- バリデーション（趣味・好きなものを「必須」に戻しました！） ---
  bool _validateInputs() {
    if (_nameController.text.trim().isEmpty) return _showError('名前を入力してください');
    if (_ageController.text.trim().isEmpty) return _showError('年齢を入力してください');
    if (_locationController.text.trim().isEmpty)
      return _showError('居住地を入力してください');

    // 💡 趣味・好きなものを必須チェックに再追加！
    if (_hobbyController.text.trim().isEmpty)
      return _showError('趣味・好きなものを入力してください');

    if (_hobbyDetailController.text.trim().isEmpty)
      return _showError('趣味について詳しく教えてください');

    // 画像は最低1枚
    if (_displayImages.every((img) => img == null)) {
      return _showError('写真を1枚以上設定してください');
    }

    // 年齢数値チェック
    if (int.tryParse(_ageController.text.trim()) == null) {
      return _showError('年齢は数字で入力してください');
    }

    if (_idealFriendController.text.trim().isEmpty) {
      return _showError('どんな友達が欲しいか教えてください');
    }

    return true;
  }

  bool _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
    return false;
  }

  // 💡 簡単自己紹介テンプレート機能
  void _applyBioTemplate() {
    setState(() {
      _bioController.text =
          "はじめまして！プロフィールを見ていただきありがとうございます✨\n\n"
          "普段は ${_locationController.text.isNotEmpty ? _locationController.text : '都内'} で ${_workController.text.isNotEmpty ? _workController.text : '会社員'} をしています。\n"
          "休日はカフェを巡ったり、まったり映画を観たりして過ごすことが多いです。☕\n"
          "最近は新しくサウナや旅行にも興味を持ち始めています。♨️\n\n"
          "共通の趣味やお互いの好きなことなど、いろいろまったりたくさんお話しできたら嬉しいです！よろしくお願いします！";
    });
  }

  Future<void> _saveProfile() async {
    if (!_validateInputs()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      List<String> finalUrls = [];

      for (var item in _displayImages) {
        if (item == null) continue;

        if (item is String) {
          finalUrls.add(item);
        } else if (item is File) {
          String fileName =
              '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          Reference storageRef = FirebaseStorage.instanceFor(
            bucket: 'gs://frendy-app-project.firebasestorage.app',
          ).ref().child('user_images/${user.uid}/$fileName');

          Uint8List fileBytes = await item.readAsBytes();
          UploadTask uploadTask = storageRef.putData(
            fileBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
          TaskSnapshot snapshot = await uploadTask;
          String downloadUrl = await snapshot.ref.getDownloadURL();
          finalUrls.add(downloadUrl);
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameController.text.trim(),
        'age': int.tryParse(_ageController.text.trim()) ?? 0,
        'gender': _selectedGender,
        'values': _myValues,
        'location': _locationController.text.trim(),
        'school': _schoolController.text.trim(),
        'work': _workController.text.trim(),
        'hobby': _hobbyController.text.trim(),
        'bio': _bioController.text.trim(),
        'tags': _selectedTags,
        'imageUrls': finalUrls,
        'updatedAt': Timestamp.now(),
        'hobbyDetail': _hobbyDetailController.text.trim(),
        'favoriteFood': _favoriteFoodController.text.trim(),
        'dislikeFood': _dislikeFoodController.text.trim(),
        'artist': _artistController.text.trim(),
        'game': _gameController.text.trim(),
        'anime': _animeController.text.trim(),
        'idealFriend': _idealFriendController.text.trim(),
      }, SetOptions(merge: true));

      setState(() {
        for (int i = 0; i < 10; i++) {
          _displayImages[i] = i < finalUrls.length ? finalUrls[i] : null;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('プロフィールを保存しました')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラー: $e')));
      }
      print('$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '編集',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.appbarText,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: OutlinedButton(
              onPressed: () {
                final profileData = {
                  'name': _nameController.text,
                  'age': _ageController.text,
                  'location': _locationController.text,
                  'school': _schoolController.text,
                  'work': _workController.text,
                  'hobby': _hobbyController.text,
                  'bio': _bioController.text,
                  'tags': _selectedTags,
                  'imageUrls': _displayImages,
                  'gender': _selectedGender,
                  'values': _myValues,
                  'hobbyDetail': _hobbyDetailController.text,
                  'favoriteFood': _favoriteFoodController.text,
                  'dislikeFood': _dislikeFoodController.text,
                  'artist': _artistController.text,
                  'game': _gameController.text,
                  'anime': _animeController.text,
                  'idealFriend': _idealFriendController.text,
                };
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ProfilePreviewScreen(data: profileData),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.appbarText,
                side: const BorderSide(color: AppColors.appbarText, width: 1.0),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text(
                'プレビュー',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: const Text(
              '保存',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.appbarText,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.point),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('プロフィール写真（最大10枚）*'),
                  _buildImageSection(),

                  _buildSectionTitle('タグ（5個まで選択可）'),
                  _buildTagSection(),

                  _buildSectionTitle('基本情報（必須）'),
                  _buildGenderRadioSection(),
                  _buildTextField(_nameController, '名前 *', Icons.person),
                  _buildTextField(
                    _ageController,
                    '年齢 *',
                    Icons.calendar_today,
                    isNumber: true,
                  ),
                  _buildLocationControllerField(),

                  // 💡 趣味・好きなものを必須に変更（アスタリスク * を追加）
                  _buildSectionTitle('趣味・好きなもの（必須）*'),
                  _buildTextField(
                    _hobbyController,
                    '趣味・好きなものを教えてください',
                    Icons.interests,
                  ),
                  _buildSectionTitle('趣味・好きなものについて詳しく教えてください（必須）*'),
                  _buildMultiLineField(
                    _hobbyDetailController,
                    '自由に入力してください（詳しく書くと会話が弾みやすくなります！）',
                  ),
                  _buildSectionTitle('どんな友達が欲しい？（必須）*'),
                  _buildMultiLineField(
                    _idealFriendController,
                    '例：一緒にカフェ巡りできる人、趣味のゲームを語れる人など',
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    '※これより下の項目はすべて任意です',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // 自己紹介（任意・ワンタップ入力補助つき）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('自己紹介文（任意）'),
                      TextButton.icon(
                        onPressed: _applyBioTemplate,
                        icon: const Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: AppColors.point,
                        ),
                        label: const Text(
                          'テンプレート入力',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.point,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildMultiLineField(_bioController, '自由に書きましょう！'),

                  // 💡 ライフスタイル・価値観シート（任意のままでOK！）
                  _buildSectionTitle('ライフスタイル・価値観シート（任意）'),
                  _buildInlineValueSheet(),

                  _buildSectionTitle('その他プロフィール（任意）'),
                  _buildTextField(_schoolController, '学校', Icons.school),
                  _buildTextField(_workController, '職業', Icons.work),
                  _buildTextField(
                    _favoriteFoodController,
                    '好きな食べ物',
                    Icons.restaurant,
                  ),
                  _buildTextField(
                    _dislikeFoodController,
                    '苦手な食べ物',
                    Icons.no_food,
                  ),
                  _buildTextField(
                    _artistController,
                    '好きなアーティスト',
                    Icons.music_note,
                  ),
                  _buildTextField(
                    _gameController,
                    '好きなゲーム',
                    Icons.sports_esports,
                  ),
                  _buildTextField(_animeController, '好きなアニメ・漫画', Icons.movie),
                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }

  // --- UIパーツ ---

  Widget _buildLocationControllerField() {
    return _buildTextField(_locationController, '居住地 *', Icons.location_on);
  }

  Widget _buildImageSection() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 10,
        itemBuilder: (context, index) {
          final item = _displayImages[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _pickImage(index),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: item == null
                        ? const Icon(Icons.add_a_photo, color: Colors.grey)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: item is File
                                ? Image.file(item, fit: BoxFit.cover)
                                : Image.network(item, fit: BoxFit.cover),
                          ),
                  ),
                ),
                if (item != null)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTagSection() {
    return Wrap(
      spacing: 8,
      children: AppTags.allTags.map((tag) {
        final isSelected = _selectedTags.contains(tag);
        return FilterChip(
          label: Text(tag),
          selected: isSelected,
          onSelected: (val) {
            setState(() {
              if (val) {
                if (_selectedTags.length < 5) _selectedTags.add(tag);
              } else {
                _selectedTags.remove(tag);
              }
            });
          },
          shape: const StadiumBorder(),
          selectedColor: AppColors.point.withOpacity(0.2),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.appbarText,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey),
          labelText: label,
          enabledBorder: _greyBorderStyle,
          focusedBorder: _greyBorderStyle.copyWith(
            borderSide: const BorderSide(color: AppColors.point, width: 2.0),
          ),
        ),
      ),
    );
  }

  Widget _buildMultiLineField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      maxLines: 4,
      decoration: InputDecoration(
        hintText: hint,
        enabledBorder: _greyBorderStyle,
        focusedBorder: _greyBorderStyle.copyWith(
          borderSide: const BorderSide(color: AppColors.point, width: 2.0),
        ),
      ),
    );
  }

  Widget _buildGenderRadioSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: '性別 *',
          prefixIcon: const Icon(Icons.wc, color: Colors.grey),
          enabledBorder: _greyBorderStyle,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: ['男性', '女性', 'その他'].map((gender) {
            final isSelected = _selectedGender == gender;
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ChoiceChip(
                label: Text(gender),
                selected: isSelected,
                selectedColor: AppColors.point.withOpacity(0.15),
                labelStyle: TextStyle(
                  color: isSelected ? AppColors.point : Colors.black87,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: isSelected ? AppColors.point : Colors.grey[300]!,
                  ),
                ),
                showCheckmark: false,
                onSelected: (bool selected) {
                  if (selected) {
                    setState(() => _selectedGender = gender);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInlineValueSheet() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _valueSheetQuestions.keys.map((question) {
          final options = _valueSheetQuestions[question]!;
          final currentSelection = _myValues[question];

          return Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: AppColors.point,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      question,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: options.map((option) {
                    final isSelected = currentSelection == option;
                    return ChoiceChip(
                      label: Text(option),
                      selected: isSelected,
                      selectedColor: AppColors.point.withOpacity(0.15),
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.point : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSelected
                              ? AppColors.point
                              : Colors.grey[300]!,
                        ),
                      ),
                      showCheckmark: false,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            _myValues[question] = option;
                          } else {
                            _myValues.remove(question);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _locationController.dispose();
    _schoolController.dispose();
    _workController.dispose();
    _hobbyController.dispose();
    _bioController.dispose();
    _hobbyDetailController.dispose();
    _favoriteFoodController.dispose();
    _dislikeFoodController.dispose();
    _artistController.dispose();
    _gameController.dispose();
    _animeController.dispose();
    _idealFriendController.dispose();
    super.dispose();
  }
}
