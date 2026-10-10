import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'providers/app_providers.dart';
import 'services/firebase_service.dart';
import 'services/local_discovery_cache.dart';
import 'services/medicine_analysis_service.dart';
import 'services/redacting_logger.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await FlutterGemma.initialize(inferenceEngines: const [MediaPipeEngine()]);
  } catch (e) {
    RedactingLogger.log('On-device AI initialization error: $e');
  }

  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    RedactingLogger.log('Dotenv load info: $e');
  }

  try {
    await FirebaseService.init();
  } catch (e) {
    RedactingLogger.log('Firebase startup error: $e');
  }

  if (FirebaseService.isCloudAvailable) {
    try {
      if (kIsWeb) {
        final siteKey = dotenv.env['FIREBASE_APPCHECK_WEB_KEY'];
        if (siteKey != null && siteKey.isNotEmpty) {
          await FirebaseAppCheck.instance.activate(
            providerWeb: ReCaptchaV3Provider(siteKey),
          );
        } else if (kDebugMode) {
          await FirebaseAppCheck.instance.activate(
            providerWeb: WebDebugProvider(),
          );
          RedactingLogger.log(
            'Register the App Check debug token shown in the browser console before calling protected cloud functions.',
          );
        } else {
          RedactingLogger.log(
            'App Check is not configured for Web; protected cloud functions will be unavailable.',
          );
        }
      } else if (kDebugMode) {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: const AndroidDebugProvider(),
          providerApple: const AppleDebugProvider(),
        );
      } else {
        await FirebaseAppCheck.instance.activate();
      }
    } catch (e) {
      RedactingLogger.log('App Check startup error: $e');
    }
  }

  await LocalDiscoveryCache.init();
  await MedicineAnalysisService.instance.initialize();

  runApp(const ProviderScope(child: PharmaGuardApp()));
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
