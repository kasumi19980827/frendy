// main.dart
import 'package:flutter/material.dart';
import 'package:matching_app/screens/friends_screen.dart';
import 'package:matching_app/screens/home_screen.dart';
import 'package:matching_app/screens/message_screen.dart';
import 'package:matching_app/screens/mypage_screen.dart';
import 'package:matching_app/screens/search_screen.dart';

class AppColors {
  static const primary = Color(0xFF58FCF1);
  static const bg = Color.fromARGB(255, 119, 214, 208);
  static const button = Color.fromARGB(255, 113, 203, 197);
  static const point = Color.fromARGB(255, 76, 183, 176);
  static const green = Color.fromARGB(255, 27, 117, 102);
  static const appbarText = Color.fromARGB(255, 14, 60, 59);
  static const pink = Color(0xFFFF8A80);
  static const white = Color.fromARGB(255, 255, 255, 255);
}

class PlaceholderScreen extends StatelessWidget {
  final String label;
  const PlaceholderScreen({required this.label, super.key});

  @override
  Widget build(BuildContext context) =>
      Center(child: Text(label));
}

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
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
          titleTextStyle: TextStyle(
            color: AppColors.appbarText, 
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const HomeScreen(),
      const SearchScreen(),
      const MessageScreen(),
      const FriendsScreen(),
      const MypageScreen(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.point,
        unselectedItemColor: Colors.black26,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '探す'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'メッセージ'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '友達'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: 'マイページ'),
        ],
      ),
    );
  }
}