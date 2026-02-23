import 'package:flutter/material.dart';
import 'package:matching_app/screens/profile_detail_screen.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      // RowとNavigationRailを消して、bodyを直接GridViewにする
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, // 1画面に2つ並べる
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.8, // 高さを少し調整
        ),
        itemCount: 10,
        itemBuilder: (context, index) {
          final String name = 'ユーザー $index';

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileDetailScreen(userName: name),
                ),
              );
            },
            child: Card(
              elevation: 4,
              child: Column(
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      child: const Icon(Icons.person, size: 50, color: Colors.white),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      // 左のメニューの代わりに、下にナビゲーションを配置（スマホアプリ風）
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.black26,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined), // 家のマーク（線）
            activeIcon: Icon(Icons.home),    // 家のマーク（塗り）
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.whatshot_outlined), 
            activeIcon: Icon(Icons.whatshot),
            label: 'マッチ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum_outlined),
            activeIcon: Icon(Icons.forum),
            label: 'トーク',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_outline), // 星マーク（線）に変更
            activeIcon: Icon(Icons.star),    // 星マーク（塗り）に変更
            label: 'お気に入り',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle_outlined),
            activeIcon: Icon(Icons.account_circle),
            label: 'プロフ',
          ),
        ],
      ),
    );
  }
}