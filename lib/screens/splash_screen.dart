import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../services/patient_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_emblem.dart';
import 'home_screen.dart';
import 'organization_dashboard_screen.dart';
import 'sign_in_screen.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final Animation<Offset> _rise;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.82,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _rise = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    _checkAuthAndNavigate();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Let the intro animation play before resolving auth state.
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final currentUser = FirebaseService.currentUser;

    if (currentUser != null) {
      // A profile is nice to have, but a slow/unavailable network must not
      // leave the user on the splash screen forever.
      final profile = await FirebaseService.getUserProfile(
        currentUser.uid,
      ).timeout(const Duration(seconds: 3), onTimeout: () => null);
      final savedPatientProfile = await PatientProfileService.load();
      if (mounted) {
        ref.read(patientProfileProvider.notifier).state = savedPatientProfile;
        if (profile != null) {
          ref.read(userProfileProvider.notifier).state = profile;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => profile?.role == 'organization'
                ? const OrganizationDashboardScreen()
                : const HomeScreen(),
          ),
        );
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SignInScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Stack(
          children: [
            // Soft ambient geometry for depth.
            Positioned(
              top: -60,
              right: -40,
              child: _glow(220, AppTheme.vibrantMint.withValues(alpha: 0.18)),
            ),
            Positioned(
              bottom: -80,
              left: -50,
              child: _glow(260, Colors.white.withValues(alpha: 0.06)),
            ),
            SafeArea(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _fade,
                      child: ScaleTransition(
                        scale: _scale,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(34),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                            ),
                          ),
                          child: const NoCapRxEmblem(
                            size: 108,
                            borderRadius: 30,
                            showShadow: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _rise,
                        child: Column(
                          children: [
                            Text(
                              'NoCapRX',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Know your genes. Understand your medicines.',
                              style: GoogleFonts.inter(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 44),
                    FadeTransition(
                      opacity: _fade,
                      child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.vibrantMint,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 26,
              child: FadeTransition(
                opacity: _fade,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Raw genetic data stays on your device',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
