import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 향수 진열장 기록을 Firestore(클라우드 DB)에 저장하기 위한 초기화
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MoodAndScentApp());
}

class MoodAndScentApp extends StatelessWidget {
  const MoodAndScentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mood & Scent | Atelier d\'Art',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF9F8F6), // 럭셔리 오프화이트/크림톤
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E1E1E),
          primary: const Color(0xFF1E1E1E),
          surface: const Color(0xFFFFFFFF),
        ),
        textTheme: GoogleFonts.notoSansTextTheme(
          Theme.of(context).textTheme,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
