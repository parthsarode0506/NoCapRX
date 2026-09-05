import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/firebase_service.dart';
import 'services/local_discovery_cache.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Dotenv load info: $e');
  }

  try {
    await FirebaseService.init();
  } catch (e) {
    debugPrint('Firebase startup error: $e');
  }

  await LocalDiscoveryCache.init();

  runApp(
    const ProviderScope(
      child: NoCapRxApp(),
    ),
  );
}

class NoCapRxApp extends StatelessWidget {
  const NoCapRxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoCapRX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      home: const SplashScreen(),
    );
  }
}
