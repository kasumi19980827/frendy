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
import 'package:flutter/services.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'frendy',
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.appbar,
          titleTextStyle: TextStyle(
            color: AppColors.appbarText,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      // main.dart の StreamBuilder 部分を以下のように修正
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = snapshot.data;

          if (user != null) {
            // 💡 ここを修正
            // Googleログイン（google.com）の場合はメール認証チェックをスキップする
            bool isGoogleUser = user.providerData.any(
              (info) => info.providerId == 'google.com',
            );

            if (isGoogleUser || user.emailVerified) {
              return const MyHomePage();
            } else {
              return const EmailVerificationPendingScreen();
            }
          }

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
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.point,
        unselectedItemColor: AppColors.txt,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.groups), label: '広場'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: '探す'),
          BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'トーク'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '友達'),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'プロフ',
          ),
        ],
      ),
    );
  }
}
