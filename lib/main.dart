import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';

import 'providers/app_providers.dart';
import 'services/firebase_service.dart';
import 'services/local_discovery_cache.dart';
import 'services/medicine_analysis_service.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FlutterGemma.initialize(
      inferenceEngines: const [MediaPipeEngine()],
    );
  } catch (e) {
    debugPrint('On-device AI initialization error: $e');
  }

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
  await MedicineAnalysisService.instance.initialize();

  runApp(
    const ProviderScope(
      child: PharmaGuardApp(),
    ),
  );
}

class PharmaGuardApp extends ConsumerWidget {
  const PharmaGuardApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
        return MaterialApp(
          title: 'NoCapRX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashScreen(),
    );
  }
}
