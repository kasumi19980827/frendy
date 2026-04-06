import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String senderId;   // 送信者のID
  final String text;       // 本文
  final DateTime createdAt; // 送信日時（履歴を並べるのに必須）

  Message({
    required this.senderId,
    required this.text,
    required thsis.createdAt,
  });

  // FirestoreのデータをDartのオブジェクトに変換する
  factory Message.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Message(
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  // DartのオブジェクトをFirestore用のデータに変換する
  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(), // サーバーの時間を使用
    };
  }
}