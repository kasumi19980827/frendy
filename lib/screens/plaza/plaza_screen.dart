import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/models/chat_room.dart';
import 'package:matching_app/screens/plaza/plaza_chat_screen.dart';

class PlazaScreen extends StatefulWidget {
  const PlazaScreen({super.key});

  @override
  State<PlazaScreen> createState() => _PlazaScreenState();
}

class _PlazaScreenState extends State<PlazaScreen> {
  final String myUserId = FirebaseAuth.instance.currentUser?.uid ?? "user_me";

  static const int _maxMembersPerRoom = 10;
  static const Duration _networkTimeout = Duration(seconds: 20);

  // 💡 部屋作成の連打・スパム防止用クールダウン
  static const int _createRoomCooldownSeconds = 10;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  // 💡 入室処理中の部屋IDを保持し、同じ部屋への多重タップを防ぐ
  final Set<String> _joiningRoomIds = {};

  // ==========================================
  // 💡「幽霊メンバー」対策：ハートビート方式
  //    在室中は一定間隔でlastActiveAtを更新し続け、
  //    強制終了などで更新が途絶えたメンバーは、
  //    後述のクリーンアップ処理で自動的に除外される
  // ==========================================
  static const Duration _heartbeatInterval = Duration(seconds: 25);
  static const Duration _staleThreshold = Duration(seconds: 75); // 心拍3回分の猶予
  static const Duration _cleanupInterval = Duration(seconds: 45);

  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;

  // 💡 直近で画面に表示されている部屋一覧（クリーンアップ対象の把握に使う）
  List<QueryDocumentSnapshot> _lastKnownRoomDocs = [];

  @override
  void initState() {
    super.initState();
    // 💡 この画面（広場一覧）が開かれている間、定期的に幽霊メンバーの掃除を行う
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanupStaleMembersInVisibleRooms();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _heartbeatTimer?.cancel();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  // 💡 Firestoreの値が数値・数値文字列・不正値のいずれであっても
  //    安全な非負整数として扱うためのヘルパー（型不整合への防御）
  int _asNonNegativeInt(dynamic value) {
    int result;
    if (value is num) {
      result = value.toInt();
    } else if (value is String) {
      result = int.tryParse(value) ?? 0;
    } else {
      result = 0;
    }
    return result < 0 ? 0 : result;
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _createRoomCooldownSeconds);
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

  // --- 部屋作成・自動遷移 ---
  void _showCreateRoomDialog() {
    final TextEditingController titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool isSubmitting = false;

          Future<void> handleCreate() async {
            final title = titleController.text.trim();
            if (title.isEmpty || isSubmitting) return;

            setDialogState(() => isSubmitting = true);

            try {
              // 💡 作成時は確実に1人。自分自身のmembersドキュメントも同時に作成する
              final docRef = FirebaseFirestore.instance
                  .collection('plaza_rooms')
                  .doc();

              final batch = FirebaseFirestore.instance.batch();
              batch.set(docRef, {
                'title': title,
                'ownerId': myUserId,
                'currentMemberCount': 1,
                'createdAt': FieldValue.serverTimestamp(),
              });
              batch.set(docRef.collection('members').doc(myUserId), {
                'joinedAt': FieldValue.serverTimestamp(),
                'lastActiveAt': FieldValue.serverTimestamp(),
              });
              await batch.commit().timeout(_networkTimeout);

              final newRoom = ChatRoom(
                id: docRef.id,
                title: title,
                ownerId: myUserId,
                currentMemberCount: 1,
              );

              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (!mounted) return;

              _startCooldown();
              _startHeartbeat(newRoom.id);

              // チャット画面へ遷移
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlazaChatScreen(room: newRoom),
                ),
              );

              // 💡 自分が作った部屋から戻ってきた時も、等しく退室処理を実行
              _stopHeartbeat();
              _handleExitRoom(newRoom.id);
            } catch (e) {
              debugPrint('部屋作成エラー: $e');
              setDialogState(() => isSubmitting = false);
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('部屋の作成に失敗しました。もう一度お試しください。'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              '新しく部屋を作る',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: TextField(
              controller: titleController,
              decoration: const InputDecoration(hintText: "部屋のタイトルを入力"),
              maxLength: 20,
              enabled: !isSubmitting,
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text(
                  'キャンセル',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey[400],
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
                    : const Text('作成', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- 💡 ハートビート：在室中、一定間隔で生存確認を送り続ける ---
  void _startHeartbeat(String roomId) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      FirebaseFirestore.instance
          .collection('plaza_rooms')
          .doc(roomId)
          .collection('members')
          .doc(myUserId)
          .set({
            'lastActiveAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .catchError((e) => debugPrint('ハートビート送信エラー: $e'));
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // --- 🔥 確実な退室・部屋削除ロジック ---
  // トランザクションをシンプルにし、不整合を防ぎます
  Future<void> _handleExitRoom(String roomId) async {
    final docRef = FirebaseFirestore.instance
        .collection('plaza_rooms')
        .doc(roomId);
    final myMemberRef = docRef.collection('members').doc(myUserId);

    try {
      await FirebaseFirestore.instance
          .runTransaction((transaction) async {
            final snapshot = await transaction.get(docRef);
            if (!snapshot.exists) return;

            final int currentCount = _asNonNegativeInt(
              (snapshot.data() ?? const {})['currentMemberCount'],
            );
            final int newCount = currentCount - 1;

            // 💡 自分のハートビート記録も忘れずに削除する
            transaction.delete(myMemberRef);

            if (newCount <= 0) {
              // 💡 0人以下になるなら、この瞬間に部屋ごとコレクションから物理削除！
              transaction.delete(docRef);
            } else {
              // まだ人が残っているなら、人数を1減らす
              transaction.update(docRef, {'currentMemberCount': newCount});
            }
          })
          .timeout(_networkTimeout);
    } catch (e) {
      debugPrint("退室処理エラー: $e");
    }
  }

  // --- 🔥 入室処理：定員チェックと加算をトランザクションで原子的に行う ---
  //    （複数人が同時にタップしても定員を超えないようにするための対策）
  Future<int?> _tryJoinRoom(String roomId) async {
    final docRef = FirebaseFirestore.instance
        .collection('plaza_rooms')
        .doc(roomId);
    final myMemberRef = docRef.collection('members').doc(myUserId);

    try {
      return await FirebaseFirestore.instance
          .runTransaction<int?>((transaction) async {
            final snapshot = await transaction.get(docRef);
            if (!snapshot.exists) return null;

            final int currentCount = _asNonNegativeInt(
              (snapshot.data() ?? const {})['currentMemberCount'],
            );

            if (currentCount >= _maxMembersPerRoom) {
              return null; // 💡 満室のため入室不可
            }

            final int newCount = currentCount + 1;
            transaction.update(docRef, {'currentMemberCount': newCount});
            // 💡 自分のハートビート記録を作成
            transaction.set(myMemberRef, {
              'joinedAt': FieldValue.serverTimestamp(),
              'lastActiveAt': FieldValue.serverTimestamp(),
            });
            return newCount;
          })
          .timeout(_networkTimeout);
    } catch (e) {
      debugPrint('入室処理エラー: $e');
      return null;
    }
  }

  Future<void> _handleJoinTap(ChatRoom room) async {
    if (_joiningRoomIds.contains(room.id)) return;
    setState(() => _joiningRoomIds.add(room.id));

    try {
      final int? newCount = await _tryJoinRoom(room.id);

      if (!mounted) return;

      if (newCount == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('この部屋は満室、または既に削除されています。')));
        return;
      }

      final updatedRoom = ChatRoom(
        id: room.id,
        title: room.title,
        ownerId: room.ownerId,
        currentMemberCount: newCount,
      );

      _startHeartbeat(room.id);

      // チャット画面へ遷移
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlazaChatScreen(room: updatedRoom),
        ),
      );

      // 💡 画面から戻ってきた（退室した）ら、ハートビートを止めて退室処理へ
      _stopHeartbeat();
      _handleExitRoom(room.id);
    } finally {
      if (mounted) {
        setState(() => _joiningRoomIds.remove(room.id));
      }
    }
  }

  // ==========================================
  // 💡 幽霊メンバーの自動クリーンアップ
  //    広場一覧を誰かが開いている間、定期的に実行される。
  //    「lastActiveAtが一定時間更新されていないメンバー」を検出し、
  //    そのメンバー分だけ人数を差し引く（強制終了・クラッシュ対策）
  // ==========================================
  Future<void> _cleanupStaleMembersInVisibleRooms() async {
    if (_lastKnownRoomDocs.isEmpty) return;

    final DateTime cutoff = DateTime.now().subtract(_staleThreshold);
    final Timestamp cutoffTimestamp = Timestamp.fromDate(cutoff);

    for (final roomDoc in _lastKnownRoomDocs) {
      try {
        final membersRef = roomDoc.reference.collection('members');

        // 💡 最終ハートビートが閾値より古いメンバーだけを取得する
        //    （全メンバーを毎回読み込むと無駄なコストがかかるため、クエリで絞り込む）
        final staleSnapshot = await membersRef
            .where('lastActiveAt', isLessThan: cutoffTimestamp)
            .get();

        if (staleSnapshot.docs.isEmpty) continue;

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final roomSnapshot = await transaction.get(roomDoc.reference);
          if (!roomSnapshot.exists) return;

          int currentCount = _asNonNegativeInt(
            (roomSnapshot.data() ?? const {})['currentMemberCount'],
          );

          int removedCount = 0;
          for (final staleDoc in staleSnapshot.docs) {
            transaction.delete(staleDoc.reference);
            removedCount += 1;
          }

          final int newCount = (currentCount - removedCount).clamp(0, 1 << 31);

          if (newCount <= 0) {
            transaction.delete(roomDoc.reference);
          } else {
            transaction.update(roomDoc.reference, {
              'currentMemberCount': newCount,
            });
          }
        });

        debugPrint(
          '幽霊メンバーを ${staleSnapshot.docs.length} 件クリーンアップしました（部屋: ${roomDoc.id}）',
        );
      } catch (e) {
        debugPrint('幽霊メンバーのクリーンアップエラー（部屋: ${roomDoc.id}）: $e');
        // 💡 1部屋の処理が失敗しても、他の部屋のクリーンアップは継続する
      }
    }
  }

  // --- 部屋の削除確認ダイアログ（誤タップ対策） ---
  void _showDeleteRoomConfirmation(ChatRoom room) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('部屋を削除しますか？'),
        content: Text('「${room.title}」を削除します。この操作は取り消せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseFirestore.instance
                    .collection('plaza_rooms')
                    .doc(room.id)
                    .delete()
                    .timeout(_networkTimeout);
              } catch (e) {
                debugPrint('部屋削除エラー: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('削除に失敗しました。もう一度お試しください。')),
                  );
                }
              }
            },
            child: const Text(
              '削除する',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 💡 部屋の通報機能（UGCコンテンツのモデレーション対応） ---
  //    Appleガイドライン1.2は、ユーザー生成コンテンツを含むアプリに対し
  //    「不適切なコンテンツを通報する仕組み」を要求している。
  //    個人プロフィールには通報機能が既にあるため、広場の部屋にも同様に用意する
  void _showReportRoomDialog(ChatRoom room) {
    final TextEditingController reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          bool isSubmitting = false;

          Future<void> handleSubmit() async {
            final String reason = reasonController.text.trim();
            if (reason.isEmpty || isSubmitting) return;

            setDialogState(() => isSubmitting = true);

            try {
              await FirebaseFirestore.instance
                  .collection('reports')
                  .add({
                    'type': 'plaza_room',
                    'reporterId': myUserId,
                    'reportedRoomId': room.id,
                    'reportedRoomTitle': room.title,
                    'reportedOwnerId': room.ownerId,
                    'reason': reason,
                    'createdAt': FieldValue.serverTimestamp(),
                  })
                  .timeout(_networkTimeout);

              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('報告ありがとうございます。運営で確認いたします。')),
                );
              }
            } catch (e) {
              debugPrint('部屋の通報エラー: $e');
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: const Text(
              'この部屋を通報',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '「${room.title}」\n不適切な内容がありましたか？理由を教えてください。',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  maxLength: 300,
                  enabled: !isSubmitting,
                  decoration: const InputDecoration(hintText: '通報理由を入力...'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text(
                  'キャンセル',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  disabledBackgroundColor: Colors.grey[400],
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
                    : const Text('通報する', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canCreateRoom = _cooldownSeconds == 0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '広場',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: OutlinedButton.icon(
              onPressed: canCreateRoom ? _showCreateRoomDialog : null,
              icon: const Icon(Icons.add, color: Colors.black, size: 18),
              label: Text(
                _cooldownSeconds > 0 ? '${_cooldownSeconds}秒待ち' : '部屋を作る',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.black, width: 1.2),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('plaza_rooms')
            .where('currentMemberCount', isGreaterThan: 0) // 0人より多い部屋のみ
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('エラーが発生しました'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          // 定員未満の空きがある部屋だけをリスト化
          final docs = snapshot.data!.docs.where((doc) {
            final count = _asNonNegativeInt(
              (doc.data() as Map<String, dynamic>)['currentMemberCount'],
            );
            return count < _maxMembersPerRoom;
          }).toList();

          // 💡 クリーンアップ処理が参照できるよう、最新の部屋一覧を保持しておく
          _lastKnownRoomDocs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('現在、入れる部屋はありません。'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.1,
            ),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;

              final int currentCount = _asNonNegativeInt(
                data['currentMemberCount'],
              );

              final room = ChatRoom(
                id: doc.id,
                title: data['title'] ?? '無題',
                ownerId: data['ownerId'] ?? '',
                currentMemberCount: currentCount,
              );

              final bool isOwner = room.ownerId == myUserId;
              final bool isJoining = _joiningRoomIds.contains(room.id);

              return GestureDetector(
                onTap: isJoining ? null : () => _handleJoinTap(room),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Icon(
                            Icons.forum_rounded,
                            color: AppColors.point,
                            size: 22,
                          ),
                          Row(
                            children: [
                              if (isJoining)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else if (isOwner)
                                // 💡 削除は確認ダイアログを挟むように変更（誤タップ対策）
                                GestureDetector(
                                  onTap: () =>
                                      _showDeleteRoomConfirmation(room),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                )
                              else
                                // 💡 自分が作った部屋以外には通報ボタンを表示する
                                GestureDetector(
                                  onTap: () => _showReportRoomDialog(room),
                                  child: const Icon(
                                    Icons.flag_outlined,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        room.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(
                            Icons.group_rounded,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$currentCount / $_maxMembersPerRoom',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.point,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
