import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/firebase_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load local .env file (for Groq AI API Key & Firebase config) safely
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Dotenv load warning (using offline pre-bundled asset mode): $e');
  }

  // Initialize Firebase (Core, Auth, Firestore, Analytics, App Check, Crashlytics)
  await FirebaseService.init();

  runApp(
    const ProviderScope(
      child: PharmaGuardApp(),
    ),
  );
}

class PharmaGuardApp extends StatelessWidget {
  const PharmaGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PharmaGuard (OnDeviceRx)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1), // Professional Medical Blue
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
