import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:matching_app/screens/profile_preview_screen.dart';
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
  final _qualificationController = TextEditingController();
  final _clubController = TextEditingController();
  final _hobbyController = TextEditingController();
  final _petController = TextEditingController();
  final _animeController = TextEditingController();
  final _artistController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _gameController = TextEditingController();
  final _brandController = TextEditingController();
  final _bioController = TextEditingController();
  final _interestsController = TextEditingController();
  final _targetFriendController = TextEditingController();

  // --- 画像・タグ関連 ---
  final List<dynamic> _displayImages = List.filled(10, null);
  final ImagePicker _picker = ImagePicker();

  List<String> _selectedTags = [];
  final List<String> _allTags = [
    '飲み仲間募集',
    'ゲーム仲間募集',
    '推し活仲間募集',
    'ライブ仲間募集',
    '趣味仲間募集',
    'ご飯屋行きたい',
    'カフェ行きたい',
    '恋人募集',
    '通話したい',
    '同年代と繋がりたい',
  ];

  bool _isLoading = false;
  String _selectedGender = '男性';

  Map<String, String> _myValues = {};

  final Map<String, List<String>> _valueSheetQuestions = {
    '趣味にかけるお金の割合': ['給料の全て', '上限を決めている', 'お小遣いの範囲で'],
    'イベントへの遠征': ['全国どこでも行く', '地方まで', '地元の現場のみ', '在宅メイン'],
    '趣味・推し活のグッズ購入': ['コンプリートしたい', '厳選して買う', '基本買わない'],
    '自分へのご褒美の頻度': ['毎月買う', '期間限定に弱い', '大きなイベント後だけ', '滅多に買わない'],
    '旅行・遠征の宿選び': ['寝れればOK（格安）', '立地重視（ビジホ）', '宿自体を楽しむ（ホテル・旅館）'],
    '理想の連絡頻度': ['毎日たくさん', '一日数回', '用事があるときだけ', '通話派'],
    '初対面で会う時のハードル': ['まずはカフェで', '最初から一日お出かけ', 'まずは通話から'],
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
        _qualificationController.text = data['qualification'] ?? '';
        _clubController.text = data['club'] ?? '';
        _hobbyController.text = data['hobby'] ?? '';
        _petController.text = data['pet'] ?? '';
        _animeController.text = data['anime'] ?? '';
        _artistController.text = data['artist'] ?? '';
        _youtubeController.text = data['youtube'] ?? '';
        _gameController.text = data['game'] ?? '';
        _brandController.text = data['brand'] ?? '';
        _bioController.text = data['bio'] ?? '';
        _interestsController.text = data['interests'] ?? '';
        _targetFriendController.text = data['targetFriend'] ?? '';
        if (data['tags'] != null)
          _selectedTags = List<String>.from(data['tags']);

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

  // --- バリデーション（必須項目のチェック） ---
  bool _validateInputs() {
    if (_nameController.text.trim().isEmpty) return _showError('名前を入力してください');
    if (_ageController.text.trim().isEmpty) return _showError('年齢を入力してください');
    if (_locationController.text.trim().isEmpty)
      return _showError('居住地を入力してください');

    if (_hobbyController.text.trim().isEmpty) return _showError('趣味を入力してください');
    if (_petController.text.trim().isEmpty) return _showError('ペットを入力してください');
    if (_animeController.text.trim().isEmpty)
      return _showError('好きなアニメ・漫画を入力してください');
    if (_artistController.text.trim().isEmpty)
      return _showError('好きなアーティストを入力してください');
    if (_youtubeController.text.trim().isEmpty)
      return _showError('好きなYouTuberを入力してください');
    if (_gameController.text.trim().isEmpty)
      return _showError('好きなゲームを入力してください');
    if (_brandController.text.trim().isEmpty)
      return _showError('好きなブランドを入力してください');

    if (_bioController.text.trim().isEmpty) return _showError('自己紹介を入力してください');
    if (_interestsController.text.trim().isEmpty)
      return _showError('最近ハマってることを入力してください');
    if (_targetFriendController.text.trim().isEmpty)
      return _showError('どんな友達が欲しいか入力してください');

    if (_displayImages.every((img) => img == null))
      return _showError('写真を1枚以上設定してください');
    if (int.tryParse(_ageController.text.trim()) == null)
      return _showError('年齢は数字で入力してください');

    return true;
  }

  bool _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
    return false;
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
        'qualification': _qualificationController.text.trim(),
        'club': _clubController.text.trim(),
        'hobby': _hobbyController.text.trim(),
        'pet': _petController.text.trim(),
        'anime': _animeController.text.trim(),
        'artist': _artistController.text.trim(),
        'youtube': _youtubeController.text.trim(),
        'game': _gameController.text.trim(),
        'brand': _brandController.text.trim(),
        'bio': _bioController.text.trim(),
        'interests': _interestsController.text.trim(),
        'targetFriend': _targetFriendController.text.trim(),
        'tags': _selectedTags,
        'imageUrls': finalUrls,
        'updatedAt': Timestamp.now(),
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
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('エラー: $e')));
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
                  'qualification': _qualificationController.text,
                  'club': _clubController.text,
                  'hobby': _hobbyController.text,
                  'pet': _petController.text,
                  'anime': _animeController.text,
                  'artist': _artistController.text,
                  'youtube': _youtubeController.text,
                  'game': _gameController.text,
                  'brand': _brandController.text,
                  'bio': _bioController.text,
                  'interests': _interestsController.text,
                  'targetFriend': _targetFriendController.text,
                  'tags': _selectedTags,
                  'imageUrls': _displayImages,
                  'gender': _selectedGender,
                  'values': _myValues,
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
                  _buildGenderRadioSection(), // 統一感を持たせた性別選択
                  _buildTextField(_nameController, '名前 *', Icons.person),
                  _buildTextField(
                    _ageController,
                    '年齢 *',
                    Icons.calendar_today,
                    isNumber: true,
                  ),
                  _buildLocationControllerField(),

                  _buildSectionTitle('趣味・嗜好（必須）'),
                  _buildTextField(_hobbyController, '趣味 *', Icons.interests),
                  _buildTextField(_petController, 'ペット *', Icons.pets),
                  _buildTextField(_animeController, '好きなアニメ・漫画 *', Icons.movie),
                  _buildTextField(
                    _artistController,
                    '好きなアーティスト *',
                    Icons.music_note,
                  ),
                  _buildTextField(
                    _youtubeController,
                    '好きなYouTuber *',
                    Icons.smart_display,
                  ),
                  _buildTextField(
                    _gameController,
                    '好きなゲーム *',
                    Icons.videogame_asset,
                  ),
                  _buildTextField(
                    _brandController,
                    '好きなブランド *',
                    Icons.shopping_bag,
                  ),

                  _buildSectionTitle('自己紹介 *'),
                  _buildMultiLineField(_bioController, '自由に書きましょう！'),
                  _buildSectionTitle('最近ハマってること *'),
                  _buildMultiLineField(_interestsController, '例：サウナ、カフェ巡りなど'),
                  _buildSectionTitle('こんな友達が欲しい *'),
                  _buildMultiLineField(
                    _targetFriendController,
                    '例：一緒にライブに行ける人など',
                  ),

                  // ⭕ モーダルではなく通常表示の価値観シート
                  _buildSectionTitle('価値観シート（任意）'),
                  _buildInlineValueSheet(),

                  _buildSectionTitle('基本情報（任意）'),
                  _buildTextField(_schoolController, '学校', Icons.school),
                  _buildTextField(_workController, '職業', Icons.work),
                  _buildTextField(
                    _qualificationController,
                    '資格',
                    Icons.verified,
                  ),
                  _buildTextField(_clubController, '部活・サークル', Icons.group),

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
      children: _allTags.map((tag) {
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
          fontSize: 18,
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

  // ⭕ 他の入力欄と縦幅・デザインを完全に統一した性別選択UI
  Widget _buildGenderRadioSection() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InputDecorator(
        // 他のTextFieldと縦幅の見た目を揃えるために contentPadding を調整
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
                  fontSize: 13, // 枠内にきれいに収まるよう文字サイズをわずかに調整
                ),
                // チップ自体の余白を詰めて縦幅をTextFieldに合わせる
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

  // ⭕ インライン形式（画面内そのまま表示）の価値観シートUI
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
    _qualificationController.dispose();
    _clubController.dispose();
    _hobbyController.dispose();
    _petController.dispose();
    _animeController.dispose();
    _artistController.dispose();
    _youtubeController.dispose();
    _gameController.dispose();
    _brandController.dispose();
    _bioController.dispose();
    _interestsController.dispose();
    _targetFriendController.dispose();
    super.dispose();
  }
}
