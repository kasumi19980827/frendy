// チャット画面

import 'package:flutter/material.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/main.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';

class TalkScreen extends StatefulWidget {
  final String userName; // MessageScreenから受け取った相手の名前

  const TalkScreen({super.key, required this.userName});

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  final TextEditingController _controller = TextEditingController();
  
  // ダミーのメッセージリスト（本来はFirebaseなどから取得）
  // reverse: true にするため、リストの [0] が一番新しいメッセージになります
  final List<String> _messages = [
    "了解です！",
    "じゃあ、渋谷に19時でどうですか？",
    "お元気ですか？",
    "こんにちは！",
  ];

  // メッセージ送信ロジック
  void _sendMessage() {
    if (_controller.text.isNotEmpty) {
      setState(() {
        // reverse: true なので、リストの最初に（一番下に）追加する
        _messages.insert(0, _controller.text); 
        _controller.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1. 背景色をご要望の AppColors.blue に設定
      backgroundColor: AppColors.blue,
      
      appBar: AppBar(
        title: Text(widget.userName), // 相手の名前を表示
        backgroundColor: Colors.white, // AppBarは白にして背景と分ける
        elevation: 1,
        centerTitle: true,
        // 広場画面のような人数表示（actions）は、1対1トークなので削除しました
      ),
      
      body: Column(
        children: [
          // 2. メッセージ表示エリア (ListView)
          Expanded(
            child: ListView.builder(
              reverse: true, // 3. 下から上に並べる（最新が下）
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                
                // 本来は「自分」か「相手」かでAlignを変えますが、
                // 今回は広場デザインを踏襲し、一旦すべて左寄せ（相手からのメッセージ風）にします
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 15), // メッセージ間の余裕
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      // 4. 広場と同じ「少し透過した白」のバルーン
                      color: Colors.white.withOpacity(0.9), 
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(15),
                        topRight: Radius.circular(15),
                        bottomRight: Radius.circular(15),
                        bottomLeft: Radius.circular(0), // 左下だけ角を尖らせる
                      ),
                    ),
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.appbarText, // main.dartで定義された文字色
                        fontSize: 15,
                        height: 1.4, // 行間を少し広くして読みやすく
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const Divider(height: 1), // 境界線
          
          // 5. メッセージ入力エリア（広場と同じデザイン）
          Container(
            color: Colors.white, // 入力欄は白に固定
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            // iPhoneなどの「下の棒（ホームバー）」の領域を考慮する
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'メッセージを入力...',
                        border: OutlineInputBorder(
                          borderSide: BorderSide.none, // 枠線を消す
                        ),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      maxLines: null, // 複数行入力を許可
                    ),
                  ),
                  // 送信ボタン
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
                    color: AppColors.point, // アクセントカラー
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}