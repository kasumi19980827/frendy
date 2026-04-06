import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 1. 追加
import 'package:matching_app/screens/email_verification_pending_screen.dart';
import 'firebase_options.dart';

// 各画面のインポート（既存のもの）
import 'package:matching_app/screens/friends_screen.dart';
import 'package:matching_app/screens/home_screen.dart';
import 'package:matching_app/screens/message_screen.dart';
import 'package:matching_app/screens/mypage_screen.dart';
import 'package:matching_app/screens/plaza_screen.dart';
import 'package:matching_app/screens/search_screen.dart';
import 'package:matching_app/screens/login_screen.dart'; // 2. 追加
import 'package:matching_app/constants/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      // 3. home を StreamBuilder に書き換え
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 1. 通信中のぐるぐる（これがないと一瞬真っ白になります）
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          // 2. ユーザーがログインしているかチェック
          final user = snapshot.data; // snapshot.data を使うのが StreamBuilder の基本です

          if (user != null) {
            // 3. ログインしている場合、メール認証済みかチェック
            if (user.emailVerified) {
              return const MyHomePage();
            } else {
              return const EmailVerificationPendingScreen();
            }
          }

          // 4. ユーザーが null（未ログイン・ログアウト後）ならログイン画面へ
          return const LoginScreen();
        },
      ),
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
      const PlazaScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: '広場'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '探す'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'トーク'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '友達'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: 'プロフ'),
        ],
      ),
    );
  }
}