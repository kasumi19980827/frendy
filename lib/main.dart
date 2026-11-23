import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matching_app/constants/app_colors.dart';
import 'package:matching_app/screens/auth/email_verification_pending_screen.dart';
import 'package:matching_app/screens/auth/login_screen.dart';
import 'package:matching_app/screens/friends/friends_screen.dart';
import 'package:matching_app/screens/home/home_screen.dart';
import 'package:matching_app/screens/mypage/mypage_screen.dart';
import 'package:matching_app/screens/search/search_screen.dart';
import 'package:matching_app/screens/talk/message_screen.dart';

import 'firebase_options.dart';

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// 💡 メールアドレスの確認をプロバイダ側で済ませているログイン方法
//    （Apple は「メールを非公開」でも Apple が中継アドレスを保証している）
const Set<String> _trustedProviders = {'google.com', 'apple.com'};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 💡 App Check：Firebase の各サービスを使う前に有効化する。
  //    本物のアプリからのリクエストだけを受け付けるようにし、
  //    改造アプリやスクリプトからの Cloud Functions 呼び出しを防ぐ。
  //    デバッグ実行時はログに出るデバッグトークンを
  //    Firebase コンソール「App Check → アプリ → デバッグトークンを管理」に登録すること
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestProvider(),
  );

  // 💡 開発中だけ、起動直後に App Check の証明書を取りに行く。
  //    これにより、Xcode のコンソールに「Debug Token」が起動時すぐに表示される。
  //    （トークン未登録の間は失敗するが、アプリの起動は止めない）
  if (kDebugMode) {
    try {
      await FirebaseAppCheck.instance.getToken().timeout(
        const Duration(seconds: 5),
      );
      debugPrint('App Check: 証明書の取得に成功しました');
    } catch (e) {
      debugPrint('App Check: 証明書を取得できませんでした（デバッグトークン未登録の可能性）: $e');
    }
  }

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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = snapshot.data;
          if (user == null) return const LoginScreen();

          final bool isTrustedProvider = user.providerData.any(
            (info) => _trustedProviders.contains(info.providerId),
          );

          if (isTrustedProvider || user.emailVerified) {
            // 💡 ユーザーIDをキーにすることで、アカウントが切り替わったときに
            //    画面の状態（前のユーザーの友達一覧など）を必ず作り直す
            return MyHomePage(key: ValueKey(user.uid));
          }
          return const EmailVerificationPendingScreen();
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
    _pages = const [
      HomeScreen(),
      SearchScreen(),
      MessageScreen(),
      FriendsScreen(),
      MypageScreen(),
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
