import 'package:flutter/material.dart';
import 'package:matching_app/screens/friends_screen.dart';
import 'package:matching_app/screens/home_screen.dart';
import 'package:matching_app/screens/profile_detail_screen.dart';
import 'package:matching_app/screens/search_screen.dart'; // プロフ詳細

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'frendy',
      theme: ThemeData(
        // frendyのテーマカラー（アクア系）
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 88, 252, 241)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'frendy'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  // 各タブに対応する画面リスト
  List<Widget> _getPages(){
  return [
    const HomeScreen(),
    const SearchScreen(), 
    const Center(child: Text('トーク')), 
    const FriendsScreen(),
    const Center(child: Text('プロフ設定')), 
  ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _getPages(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color.fromARGB(255, 40, 180, 170),
        unselectedItemColor: Colors.black26,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '探す'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'トーク'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '友達'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: 'プロフ'),
        ],
      ),
    );
  }
}