import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matching_app/constants/app_colors.dart';

class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({super.key});

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  User? get currentUser => FirebaseAuth.instance.currentUser;
  String get myId => currentUser?.uid ?? '';

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  double? _uploadProgress; // 0.0〜1.0。アップロード中以外はnull

  String _verificationStatus = 'unsubmitted';
  String _rejectionReason = '';

  // 💡 ステータスの読み込み状態
  bool _isStatusLoading = true;
  bool _statusLoadFailed = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;

  // 💡 身分証画像を格納するStorageバケット
  static const String _storageBucket =
      'gs://frendy-app-project.firebasestorage.app';

  // 💡 1人につき1枚だけ保存する（再提出のたびに上書きする）。
  //    提出のたびに別名で保存すると、古い身分証が溜まり続けて
  //    ストレージ代がかさむうえ、不要な個人情報を持ち続けることになるため
  static const String _verificationFileName = 'verification_image';

  // 💡 アップロード前に弾く上限ファイルサイズ（8MB）。Storageのルールでも同じ上限で弾く
  static const int _maxFileSizeBytes = 8 * 1024 * 1024;

  static const Duration _uploadTimeout = Duration(seconds: 60);
  static const Duration _networkTimeout = Duration(seconds: 20);

  // 💡 失敗直後の連続再送信を防ぐクールダウン（秒）
  static const int _resubmitCooldownSeconds = 10;

  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _listenVerificationStatus();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }

  // ==========================================
  // 審査状況をリアルタイムで受け取る
  // ==========================================
  //    運営が承認・否認したら、画面を開いたままでもすぐに表示が切り替わる
  void _listenVerificationStatus() {
    _statusSub?.cancel();

    if (myId.isEmpty) {
      _isStatusLoading = false;
      _statusLoadFailed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnackBar('ログイン状態が確認できません。再ログインしてください。', Colors.redAccent);
      });
      return;
    }

    _statusSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myId)
        .snapshots()
        .listen(
          (doc) {
            if (!mounted) return;
            final data = doc.data();
            setState(() {
              _verificationStatus =
                  (data?['ageVerified'] as String?) ?? 'unsubmitted';
              _rejectionReason =
                  (data?['verificationRejectionReason'] as String?) ?? '';
              _isStatusLoading = false;
              _statusLoadFailed = false;
            });
          },
          onError: (e) {
            debugPrint('ステータス取得エラー: $e');
            if (!mounted) return;
            setState(() {
              _isStatusLoading = false;
              _statusLoadFailed = true;
            });
          },
        );
  }

  void _retryLoadStatus() {
    setState(() {
      _isStatusLoading = true;
      _statusLoadFailed = false;
    });
    _listenVerificationStatus();
  }

  // ==========================================
  // 画像の選択
  // ==========================================
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        // 💡 身分証の文字（生年月日など）が読めなくならないよう、画質は高めに保つ
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (pickedFile == null) return;

      final File file = File(pickedFile.path);

      final int fileSize = await file.length();
      if (fileSize > _maxFileSizeBytes) {
        _showSnackBar('ファイルサイズが大きすぎます（上限8MB）。別の写真をお試しください。', Colors.redAccent);
        return;
      }

      if (!mounted) return;
      setState(() => _imageFile = file);
    } catch (e) {
      debugPrint('画像取得エラー: $e');
      _showSnackBar(
        '画像の取得に失敗しました。カメラ・写真へのアクセスが許可されているかご確認ください。',
        Colors.redAccent,
      );
    }
  }

  // 💡 ファイルの拡張子から、正しい画像の種類を判定する
  String _contentTypeFor(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  // ==========================================
  // 提出
  // ==========================================
  Future<void> _submitVerification() async {
    if (_isLoading || _cooldownSeconds > 0) return;

    final File? imageFile = _imageFile;
    if (imageFile == null) {
      _showSnackBar('確認書類の写真を選択してください。', Colors.redAccent);
      return;
    }

    final user = currentUser;
    if (user == null) {
      _showErrorDialog(title: '認証エラー', message: 'ログイン情報が取得できません。再ログインしてください。');
      return;
    }
    final String uid = user.uid;
    final String storagePath = 'user_verifications/$uid/$_verificationFileName';

    setState(() {
      _isLoading = true;
      _uploadProgress = 0;
    });

    // ==========================================
    // STEP 1: Storage にアップロード
    // ==========================================
    StreamSubscription<TaskSnapshot>? progressSub;
    try {
      final Reference storageRef = FirebaseStorage.instanceFor(
        bucket: _storageBucket,
      ).ref().child(storagePath);

      // 💡 putFileはファイルを少しずつ送るので、画像全体をメモリに読み込まずに済む
      final UploadTask uploadTask = storageRef.putFile(
        imageFile,
        SettableMetadata(contentType: _contentTypeFor(imageFile.path)),
      );

      progressSub = uploadTask.snapshotEvents.listen((snapshot) {
        if (!mounted || snapshot.totalBytes == 0) return;
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      });

      await uploadTask.timeout(
        _uploadTimeout,
        onTimeout: () {
          uploadTask.cancel();
          throw TimeoutException('アップロードがタイムアウトしました');
        },
      );

      // 💡 ダウンロードURLは取得しない・保存しない。
      //    ダウンロードURLは「知っている人なら誰でも見られる」URLなので、
      //    Firestoreに保存すると身分証が流出する原因になる
    } on TimeoutException {
      _handleSubmitFailure('通信状況が不安定なようです。電波の良い場所で、もう一度お試しください。');
      return;
    } catch (e) {
      debugPrint('Storageアップロードエラー: $e');
      _handleSubmitFailure('画像のアップロードに失敗しました。通信環境をご確認のうえ、もう一度お試しください。');
      return;
    } finally {
      await progressSub?.cancel();
    }

    // ==========================================
    // STEP 2: Firestore に提出記録を保存
    // ==========================================
    //    - verification_requests/{uid}：画像の保存場所（本人も含めて誰も読めない。運営がコンソールで確認）
    //    - users/{uid}：審査状況（「審査中」にする）
    //    2つを同時に書き込み、片方だけ保存される状態を防ぐ
    try {
      if (mounted) setState(() => _uploadProgress = null);

      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      batch.set(db.collection('verification_requests').doc(uid), {
        'imagePath': storagePath,
        'submittedAt': FieldValue.serverTimestamp(),
      });

      batch.set(db.collection('users').doc(uid), {
        'ageVerified': 'pending',
        'verificationSubmittedAt': FieldValue.serverTimestamp(),
        'verificationRejectionReason': '',
        // 💡 以前のバージョンで保存していた、誰でも見られる身分証のURLを消す
        'verificationImageUrl': FieldValue.delete(),
      }, SetOptions(merge: true));

      await batch.commit().timeout(_networkTimeout);

      if (!mounted) return;
      setState(() {
        _verificationStatus = 'pending';
        _imageFile = null;
        _isLoading = false;
      });
      _showSnackBar('身分証を提出しました。確認完了までしばらくお待ちください。', Colors.green);
    } on TimeoutException {
      _handleSubmitFailure('通信がタイムアウトしました。電波の良い場所で、もう一度お試しください。');
    } catch (e) {
      debugPrint('Firestore更新エラー: $e');
      _handleSubmitFailure('送信中にエラーが発生しました。もう一度お試しください。');
    }
  }

  void _handleSubmitFailure(String message) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _uploadProgress = null;
    });
    _showErrorDialog(title: '提出に失敗しました', message: message);
    _startCooldown();
  }

  // --- 再送信クールダウンの開始（連続リトライの抑止） ---
  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _resubmitCooldownSeconds);

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_cooldownSeconds <= 1) {
          _cooldownSeconds = 0;
          timer.cancel();
        } else {
          _cooldownSeconds -= 1;
        }
      });
    });
  }

  void _showErrorDialog({required String title, required String message}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.redAccent,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color bgColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: bgColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 💡 アップロード中に戻ると、提出が途中で止まってしまうため戻れないようにする
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            '年齢確認・本人確認',
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black87),
          automaticallyImplyLeading: !_isLoading,
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingView();

    if (_isStatusLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.point),
      );
    }

    if (_statusLoadFailed) return _buildLoadErrorView();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusCard(),
          const SizedBox(height: 24),
          if (_verificationStatus == 'pending')
            _buildPendingInfo()
          else if (_verificationStatus == 'verified')
            _buildVerifiedInfo()
          else ...[
            // 未提出・否認（rejected）・想定外の値は、提出フォームを表示する
            const Text(
              '年齢確認のお願い',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'frendyは、安心・安全な友達作りのコミュニティを維持するため、18歳未満の方の利用を制限しています。メッセージの送信には、身分証による年齢確認が必須となります。',
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            _buildGuidelineCard(),
            const SizedBox(height: 24),
            _buildImagePickerSection(),
            const SizedBox(height: 32),
            _buildSubmitButton(),
            if (_cooldownSeconds > 0) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '再送信まで $_cooldownSeconds秒お待ちください',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              '提出いただいた画像は年齢確認のみに使用し、運営の審査担当者以外が見ることはありません。退会時には完全に削除されます。',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- 読み込み失敗時 ---
  Widget _buildLoadErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              '確認状況を読み込めませんでした。\n通信環境をご確認ください。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _retryLoadStatus,
              style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
              child: const Text('再読み込み'),
            ),
          ],
        ),
      ),
    );
  }

  // --- アップロード中の進捗表示 ---
  Widget _buildLoadingView() {
    final double? progress = _uploadProgress;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: AppColors.point,
              value: progress != null && progress > 0 ? progress : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            progress != null
                ? 'アップロード中... ${(progress * 100).toStringAsFixed(0)}%'
                : '送信中...',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // --- UIパーツ群 ---

  Widget _buildStatusCard() {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (_verificationStatus) {
      case 'verified':
        statusColor = Colors.green;
        statusText = '年齢確認 承認済み';
        statusIcon = Icons.verified;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusText = '身分証 確認中';
        statusIcon = Icons.hourglass_empty_rounded;
        break;
      case 'rejected':
        statusColor = Colors.redAccent;
        statusText = '確認書類 再提出のお願い';
        statusIcon = Icons.error_outline_rounded;
        break;
      default:
        statusColor = Colors.grey;
        statusText = '年齢確認 未完了';
        statusIcon = Icons.gpp_maybe_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (_verificationStatus == 'rejected' &&
              _rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '理由: $_rejectionReason',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuidelineCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '💡 ご利用可能な確認書類（いずれか1つ）',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '・運転免許証\n'
            '・マイナンバーカード（表面のみ）\n'
            '・パスポート\n'
            '・在留カード / 特別永住者証明書',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
          SizedBox(height: 12),
          Text(
            '📸 撮影のポイント',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '・生年月日・書類の名称・発行者がはっきり読めるように撮影してください\n'
            '・光の反射や指で文字が隠れないようにしてください\n'
            '・マイナンバーカードの裏面（個人番号）は撮影しないでください',
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePickerSection() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (sheetContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.camera_alt,
                          color: Colors.black87,
                        ),
                        title: const Text('写真を撮影する'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _pickImage(ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(
                          Icons.photo_library,
                          color: Colors.black87,
                        ),
                        title: const Text('ライブラリから選択'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _pickImage(ImageSource.gallery);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[300]!, width: 1),
              ),
              child: _imageFile == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo,
                          size: 40,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '身分証の写真をアップロード',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'タップしてカメラ・写真を選択',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _imageFile!,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
            ),
          ),
          if (_imageFile != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => setState(() => _imageFile = null),
              icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
              label: const Text(
                '写真を削除',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final bool canSubmit =
        _imageFile != null && !_isLoading && _cooldownSeconds == 0;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: canSubmit ? _submitVerification : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.point,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey[200],
          disabledForegroundColor: Colors.grey[400],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(27),
          ),
          elevation: 0,
        ),
        child: Text(
          _cooldownSeconds > 0 ? '再送信まで $_cooldownSeconds秒' : '身分証を提出して年齢確認する',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildPendingInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          const Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          const Text(
            '現在、運営チームで確認中です',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '提出された身分証を順番に確認しております。\n'
            '通常、数分〜24時間以内に完了いたします。確認が完了すると、この画面も自動で「承認済み」に切り替わり、すべての機能がご利用可能になります。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 150,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.grey),
                shape: const StadiumBorder(),
              ),
              child: const Text('戻る', style: TextStyle(color: Colors.black87)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          const Icon(Icons.gpp_good_rounded, size: 64, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            '年齢確認は完了しています',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'ご協力ありがとうございました！\n'
            '安心・安全なコミュニティ作りへのご協力に感謝いたします。\n\n'
            'frendyのすべての機能をお楽しみください！',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 150,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              child: const Text('戻る'),
            ),
          ),
        ],
      ),
    );
  }
}
