import 'package:flutter/material.dart';
import 'package:matching_app/screens/home_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'frendy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color.fromARGB(255, 88, 252, 241)),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'frendy'), // home_screen.dartにあるクラスを呼び出す
    );
  }
}