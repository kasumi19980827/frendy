import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
  String get myId => currentUser?.uid ?? "";

  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  double? _uploadProgress; // 0.0〜1.0。アップロード中以外はnull

  String _verificationStatus = 'unsubmitted';
  String _rejectionReason = '';

  // 💡 身分証画像を格納するStorageバケット。
  //    本来は複数画面で使い回すため constants/app_config.dart 等に
  //    一元化するのが望ましいが、既存構成に合わせてここに定義する
  static const String _storageBucket =
      'gs://frendy-app-project.firebasestorage.app';

  // 💡 アップロード前に弾く上限ファイルサイズ（8MB）
  //    サーバー・ストレージコストの肥大化と、低速回線での失敗を防ぐ
  static const int _maxFileSizeBytes = 8 * 1024 * 1024;

  // 💡 アップロード自体のタイムアウト。不安定な回線で無限に固まるのを防ぐ
  static const Duration _uploadTimeout = Duration(seconds: 60);

  // 💡 失敗直後の連続再送信を防ぐクールダウン（秒）
  //    障害発生時に大量ユーザーが同時リトライする「リトライの雪崩」を緩和する
  static const int _resubmitCooldownSeconds = 10;

  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _loadVerificationStatus();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVerificationStatus() async {
    if (myId.isEmpty) {
      _showSnackBar("【警告】ログイン状態が確認できません。", Colors.redAccent);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myId)
          .get();

      // 💡 非同期処理の完了時点で画面が破棄されていないかを必ず確認する
      if (!mounted) return;

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _verificationStatus = data['ageVerified'] ?? 'unsubmitted';
          _rejectionReason = data['verificationRejectionReason'] ?? '';
        });
      }
    } catch (e) {
      // 💡 内部エラーの詳細はログにのみ残し、ユーザーには汎用メッセージのみ表示する
      debugPrint("ステータス取得エラー: $e");
      if (mounted) {
        _showSnackBar("ステータスの取得に失敗しました。時間をおいて再度お試しください。", Colors.redAccent);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 50,
        // 💡 解像度の上限を設定し、高解像度端末でもファイルサイズが
        //    際限なく大きくならないようにする（帯域・ストレージ対策）
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (pickedFile == null) return;

      final File file = File(pickedFile.path);

      // 💡 アップロード前にファイルサイズを検証する
      final int fileSize = await file.length();
      if (fileSize > _maxFileSizeBytes) {
        if (mounted) {
          _showSnackBar(
            "ファイルサイズが大きすぎます（上限8MB）。別の写真をお試しください。",
            Colors.redAccent,
          );
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        _imageFile = file;
      });
      debugPrint("画像取得に成功: ${pickedFile.path}（${fileSize ~/ 1024}KB）");
    } catch (e) {
      debugPrint("画像取得エラー: $e");
      if (mounted) {
        _showSnackBar("画像の取得に失敗しました。もう一度お試しください。", Colors.redAccent);
      }
    }
  }

  Future<void> _submitVerification() async {
    // 💡 多重送信・連打防止。ローディング中・クールダウン中は何もしない
    if (_isLoading || _cooldownSeconds > 0) return;

    if (_imageFile == null) {
      _showSnackBar("確認書類の写真を選択してください。", Colors.redAccent);
      return;
    }

    final user = currentUser;
    if (user == null || myId.isEmpty) {
      _showErrorDialog(title: "認証エラー", message: "ログイン情報が取得できません。再ログインしてください。");
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadProgress = 0;
    });

    String? downloadUrl;

    // ==========================================
    // STEP 1: Storage アップロード
    // ==========================================
    try {
      final String fileName =
          '${myId}_verification_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final FirebaseStorage storageInstance = FirebaseStorage.instanceFor(
        bucket: _storageBucket,
      );

      final Reference storageRef = storageInstance.ref().child(
        'user_verifications/$myId/$fileName',
      );
      debugPrint("Storageアップロード開始。パス: user_verifications/$myId/$fileName");

      final Uint8List fileBytes = await _imageFile!.readAsBytes();

      final UploadTask uploadTask = storageRef.putData(
        fileBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // 💡 進捗をUIに反映し、ユーザーに「固まっていない」ことを伝える
      final StreamSubscription<TaskSnapshot> progressSub = uploadTask
          .snapshotEvents
          .listen((snapshot) {
            if (!mounted || snapshot.totalBytes == 0) return;
            setState(() {
              _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
            });
          });

      final TaskSnapshot snapshot = await uploadTask.timeout(
        _uploadTimeout,
        onTimeout: () {
          uploadTask.cancel();
          throw TimeoutException('アップロードがタイムアウトしました');
        },
      );
      await progressSub.cancel();

      downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint("Storageアップロード成功！");
    } on TimeoutException {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorDialog(
          title: "アップロードに失敗しました",
          message: "通信状況が不安定なようです。電波の良い場所で、もう一度お試しください。",
        );
        _startCooldown();
      }
      return;
    } catch (e) {
      // 💡 内部エラー詳細（バケット名・パス等）はユーザーへ見せずログにのみ残す。
      //    Storageのアクセス権限はサーバー側のセキュリティルールで
      //    厳格に管理するものであり、エンドユーザーへ設定変更を案内してはならない
      //    （身分証画像を公開設定にしてしまうと重大な情報漏洩につながる）
      debugPrint("Storageアップロードエラー: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorDialog(
          title: "アップロードに失敗しました",
          message: "画像のアップロードに失敗しました。通信環境をご確認のうえ、もう一度お試しください。",
        );
        _startCooldown();
      }
      return;
    }

    // ==========================================
    // STEP 2: Firestore への書き込み
    // ==========================================
    try {
      debugPrint("Firestoreの更新を開始します。UID: $myId");

      await FirebaseFirestore.instance.collection('users').doc(myId).set({
        'ageVerified': 'pending',
        'verificationImageUrl': downloadUrl,
        'verificationSubmittedAt': Timestamp.now(),
        'verificationRejectionReason': '',
      }, SetOptions(merge: true));

      debugPrint("Firestoreの更新に成功しました。");

      if (!mounted) return;
      setState(() {
        _verificationStatus = 'pending';
        _imageFile = null;
      });

      _showSnackBar("身分証を提出しました。確認完了までしばらくお待ちください。", Colors.green);
    } catch (e) {
      debugPrint("Firestore更新エラー: $e");
      if (mounted) {
        _showErrorDialog(
          title: "送信に失敗しました",
          message: "画像の送信中にエラーが発生しました。もう一度お試しください。",
        );
        _startCooldown();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadProgress = null;
        });
      }
    }
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
              "OK",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color bgColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '年齢確認・本人確認',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? _buildLoadingView()
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 16.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),

                  if (_verificationStatus == 'unsubmitted' ||
                      _verificationStatus == 'rejected') ...[
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
                      'frendyは、安心・安全な友達作りのコミュニティを維持するため、18歳未満の方の利用を制限しています。メッセージ送信や広場の利用には、身分証による年齢確認が必須となります。',
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
                      Text(
                        '再送信まで ${_cooldownSeconds}秒お待ちください',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ] else if (_verificationStatus == 'pending') ...[
                    _buildPendingInfo(),
                  ] else if (_verificationStatus == 'verified') ...[
                    _buildVerifiedInfo(),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // --- アップロード中の進捗表示 ---
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: AppColors.point,
              value: _uploadProgress != null && _uploadProgress! > 0
                  ? _uploadProgress
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _uploadProgress != null
                ? 'アップロード中... ${((_uploadProgress ?? 0) * 100).toStringAsFixed(0)}%'
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
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 8),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
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
            '・運転免許証 / 健康保険証\n・マイナンバーカード (表面のみ)\n・パスポート / 在留カード',
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
                builder: (context) => SafeArea(
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
                          Navigator.pop(context);
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
                          Navigator.pop(context);
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
                      child: Image.file(_imageFile!, fit: BoxFit.cover),
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
          _cooldownSeconds > 0
              ? '再送信まで ${_cooldownSeconds}秒'
              : '身分証を提出して年齢確認する',
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
            'ただいま順番に提出された身分証の確認を行っております。\n通常、数分〜24時間以内に完了いたします。確認が完了すると、自動的に「承認済み」ステータスとなり、すべての機能がご利用可能になります。そのまましばらくお待ちください。',
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
            'ご協力ありがとうございました！\n年齢確認が正常に完了しています。安心・安全なコミュニティ作りへのご協力に感謝いたします。\n\nfrendyのすべての機能（広場でのチャット、マッチした友達とのメッセージやり取り）を心ゆくまでお楽しみください！',
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
