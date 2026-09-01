import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _hobbyController = TextEditingController(); // 好きなこと（趣味） (必須)
  final _recentInterestController = TextEditingController(); // 最近特にハマってること (必須)
  final _idealFriendController = TextEditingController(); // どんな友達が欲しい（必須）

  List<String> _selectedTags = [];

  // --- 画像・タグ関連 ---
  final List<dynamic> _displayImages = List.filled(10, null);
  final ImagePicker _picker = ImagePicker();

  // 💡 ユーザーが削除した既存画像のURL。保存成功後にStorageから実削除するために追跡する
  final List<String> _removedImageUrls = [];

  bool _isLoading = false;
  String _selectedGender = '男性';

  Map<String, String> _myValues = {};

  // 💡 身分証画像バケットと同じStorageバケット。将来的には共通定数ファイルへ移すことを推奨
  static const String _storageBucket =
      'gs://frendy-app-project.firebasestorage.app';

  // 💡 画像1枚あたりの上限サイズ（8MB）
  static const int _maxImageFileSizeBytes = 8 * 1024 * 1024;

  // 💡 各種ネットワーク処理のタイムアウト
  static const Duration _networkTimeout = Duration(seconds: 30);

  // 💡 年齢の許容範囲（コミュニティガイドラインに合わせて18歳以上に制限）
  static const int _minAge = 18;
  static const int _maxAge = 100;

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

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(_networkTimeout);

      // 💡 非同期処理完了時点で画面が破棄されていないか必ず確認する
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _ageController.text = data['age']?.toString() ?? '';
          _locationController.text = data['location'] ?? '';
          _hobbyController.text = data['hobby'] ?? '';
          _recentInterestController.text = data['recentInterest'] ?? '';
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
    } catch (e) {
      debugPrint('プロフィール読み込みエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('プロフィールの読み込みに失敗しました')));
      }
    }
  }

  Future<void> _pickImage(int index) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
        // 💡 解像度に上限を設け、高解像度端末でもファイルサイズが際限なく
        //    大きくならないようにする（帯域・ストレージコスト対策）
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (pickedFile == null) return;

      final File file = File(pickedFile.path);
      final int fileSize = await file.length();

      if (fileSize > _maxImageFileSizeBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ファイルサイズが大きすぎます（上限8MB）。別の写真をお試しください。'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      // 💡 既にアップロード済みの画像（String）を新しい写真に差し替える場合は、
      //    差し替え前のURLを削除対象として記録しておく
      final dynamic previous = _displayImages[index];
      if (previous is String) {
        _removedImageUrls.add(previous);
      }

      setState(() => _displayImages[index] = file);
    } catch (e) {
      debugPrint('画像取得エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('画像の取得に失敗しました。もう一度お試しください。')),
        );
      }
    }
  }

  void _removeImage(int index) {
    final dynamic item = _displayImages[index];
    // 💡 既存アップロード済み画像を削除した場合、後でStorageからも削除するために記録する
    if (item is String) {
      _removedImageUrls.add(item);
    }
    setState(() => _displayImages[index] = null);
  }

  // --- バリデーション ---
  bool _validateInputs() {
    if (_nameController.text.trim().isEmpty) return _showError('名前を入力してください');

    final String ageText = _ageController.text.trim();
    if (ageText.isEmpty) return _showError('年齢を入力してください');

    final int? age = int.tryParse(ageText);
    if (age == null) return _showError('年齢は数字で入力してください');
    if (age < _minAge) return _showError('18歳未満の方はご利用いただけません');
    if (age > _maxAge) return _showError('年齢の入力値が正しくありません');

    if (_locationController.text.trim().isEmpty) {
      return _showError('居住地を入力してください');
    }

    if (_hobbyController.text.trim().isEmpty) {
      return _showError('好きなこと（趣味）を入力してください');
    }

    if (_recentInterestController.text.trim().isEmpty) {
      return _showError('最近特にハマってることを入力してください');
    }

    // 画像は最低1枚
    if (_displayImages.every((img) => img == null)) {
      return _showError('写真を1枚以上設定してください');
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

  // --- 1枚分の画像アップロード処理 ---
  Future<String> _uploadSingleImage(
    File file,
    String uid,
    int slotIndex,
  ) async {
    final String fileName =
        '${uid}_${DateTime.now().millisecondsSinceEpoch}_$slotIndex.jpg';
    final FirebaseStorage storage = FirebaseStorage.instanceFor(
      bucket: _storageBucket,
    );
    final Reference storageRef = storage.ref().child(
      'user_images/$uid/$fileName',
    );

    final Uint8List fileBytes = await file.readAsBytes();
    final UploadTask uploadTask = storageRef.putData(
      fileBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final TaskSnapshot snapshot = await uploadTask.timeout(_networkTimeout);
    return snapshot.ref.getDownloadURL();
  }

  // 💡 孤立ファイル（参照されなくなった画像）の削除をベストエフォートで試みる。
  //    失敗してもユーザー操作をブロックしない
  Future<void> _bestEffortDeleteByUrl(String url) async {
    try {
      await FirebaseStorage.instanceFor(
        bucket: _storageBucket,
      ).refFromURL(url).delete();
    } catch (e) {
      debugPrint('孤立ファイル削除エラー（無視して続行）: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (_isLoading) return;
    if (!_validateInputs()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    // 💡 元の並び順を保ったまま、新規ファイルは並列アップロードする
    final List<String?> orderedResults = List<String?>.filled(
      _displayImages.length,
      null,
    );
    final List<Future<void>> uploadTasks = [];
    final List<String> newlyUploadedUrls = [];

    for (int i = 0; i < _displayImages.length; i++) {
      final dynamic item = _displayImages[i];
      if (item == null) continue;

      if (item is String) {
        orderedResults[i] = item;
      } else if (item is File) {
        final int slotIndex = i;
        uploadTasks.add(
          _uploadSingleImage(item, user.uid, slotIndex).then((url) {
            orderedResults[slotIndex] = url;
            newlyUploadedUrls.add(url);
          }),
        );
      }
    }

    try {
      await Future.wait(uploadTasks);
    } catch (e) {
      debugPrint('画像アップロードエラー: $e');
      // 💡 途中まで成功した分は孤立ファイルとして残さないよう削除を試みる
      for (final url in newlyUploadedUrls) {
        unawaited(_bestEffortDeleteByUrl(url));
      }
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('画像のアップロードに失敗しました。もう一度お試しください。'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final List<String> finalUrls = orderedResults.whereType<String>().toList();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'name': _nameController.text.trim(),
            'age': int.tryParse(_ageController.text.trim()) ?? 0,
            'gender': _selectedGender,
            'values': _myValues,
            'location': _locationController.text.trim(),
            'hobby': _hobbyController.text.trim(),
            'recentInterest': _recentInterestController.text.trim(),
            'tags': _selectedTags,
            'imageUrls': finalUrls,
            'updatedAt': Timestamp.now(),
            'idealFriend': _idealFriendController.text.trim(),
          }, SetOptions(merge: true))
          .timeout(_networkTimeout);

      // 💡 Firestoreへの保存が成功した後にだけ、不要になった旧画像を削除する
      //    （保存失敗時に誤って現行画像を消してしまわないようにするため）
      for (final url in _removedImageUrls) {
        unawaited(_bestEffortDeleteByUrl(url));
      }
      _removedImageUrls.clear();

      if (!mounted) return;
      setState(() {
        for (int i = 0; i < 10; i++) {
          _displayImages[i] = i < finalUrls.length ? finalUrls[i] : null;
        }
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('プロフィールを保存しました')));
      Navigator.pop(context);
    } catch (e) {
      debugPrint('プロフィール保存エラー: $e');
      // 💡 Firestore書き込みが失敗した場合、今回新規アップロードした画像は
      //    どこからも参照されない孤立ファイルになるため削除しておく
      for (final url in newlyUploadedUrls) {
        unawaited(_bestEffortDeleteByUrl(url));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('プロフィールの保存に失敗しました。もう一度お試しください。'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
                  'hobby': _hobbyController.text,
                  'recentInterest': _recentInterestController.text,
                  'tags': _selectedTags,
                  'imageUrls': _displayImages,
                  'gender': _selectedGender,
                  'values': _myValues,
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
                  _buildTextField(
                    _nameController,
                    '名前 *',
                    Icons.person,
                    maxLength: 30,
                  ),
                  _buildTextField(
                    _ageController,
                    '年齢 *',
                    Icons.calendar_today,
                    isNumber: true,
                    maxLength: 3,
                  ),
                  _buildLocationControllerField(),

                  // 💡 「趣味・好きなもの」→「好きなこと（趣味）」に変更、入力欄を複数行に拡大
                  _buildSectionTitle('好きなこと（趣味）（必須）*'),
                  _buildMultiLineField(
                    _hobbyController,
                    '好きなこと（趣味）を教えてください',
                    maxLength: 100,
                  ),
                  // 💡 「趣味について詳しく」欄を削除し、代わりに「最近特にハマってること」を追加（必須）
                  _buildSectionTitle('最近特にハマってること（必須）*'),
                  _buildMultiLineField(
                    _recentInterestController,
                    '自由に入力してください（詳しく書くと会話が弾みやすくなります！）',
                    maxLength: 500,
                  ),
                  // 💡 「どんな友達が欲しい？」を必須に変更
                  _buildSectionTitle('どんな友達が欲しい？（必須）*'),
                  _buildMultiLineField(
                    _idealFriendController,
                    '例：一緒にカフェ巡りできる人、趣味のゲームを語れる人など',
                    maxLength: 300,
                  ),
                  const SizedBox(height: 40),

                  // 💡 ライフスタイル・価値観シート（任意のままでOK！）
                  _buildSectionTitle('ライフスタイル・価値観シート（任意）'),
                  _buildInlineValueSheet(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
    );
  }

  // --- UIパーツ ---

  Widget _buildLocationControllerField() {
    return _buildTextField(
      _locationController,
      '居住地 *',
      Icons.location_on,
      maxLength: 50,
    );
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
    int? maxLength,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: isNumber
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        maxLength: maxLength,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.grey),
          labelText: label,
          counterText: '', // 💡 文字数カウンター表示を非表示にする
          enabledBorder: _greyBorderStyle,
          focusedBorder: _greyBorderStyle.copyWith(
            borderSide: const BorderSide(color: AppColors.point, width: 2.0),
          ),
        ),
      ),
    );
  }

  Widget _buildMultiLineField(
    TextEditingController controller,
    String hint, {
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      maxLines: 4,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '', // 💡 文字数カウンター表示を非表示にする
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
    _hobbyController.dispose();
    _recentInterestController.dispose();
    _idealFriendController.dispose();
    super.dispose();
  }
}
