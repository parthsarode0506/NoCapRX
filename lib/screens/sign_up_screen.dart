import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/app_providers.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/security_cards.dart';
import 'home_screen.dart';
import 'organization_dashboard_screen.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key, this.organizationWorkspaceRequested = false});

  final bool organizationWorkspaceRequested;

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _organizationNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _invitationCodeController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _privacyNoticeAccepted = false;
  bool _accountSetupIncomplete = false;
  bool _awaitingInvitationEmailVerification = false;
  late bool _organizationAccount = widget.organizationWorkspaceRequested;
  String? _errorMessage;
  String _locale = 'en';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _organizationNameController.dispose();
    _cityController.dispose();
    _invitationCodeController.dispose();
    super.dispose();
  }

  int _calculateStrengthScore(String password) {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;
    if (score == 0 && password.isNotEmpty) score = 1;
    return score;
  }

  Color _getStrengthSegmentColor(int index, int score) {
    if (index >= score) return AppTheme.cardBorder;
    if (score == 1) return AppTheme.dangerRed;
    if (score == 2) return AppTheme.warningAmber;
    if (score == 3) return const Color(0xFF10B981);
    return AppTheme.safeGreen;
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return;
    if (!_privacyNoticeAccepted) {
      setState(() {
        _errorMessage = 'Please acknowledge the privacy notice to continue.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final existingUser = FirebaseService.currentUser;
      if (existingUser != null &&
          existingUser.email == _emailController.text.trim()) {
        await FirebaseService.completeAccountOnboarding(
          user: existingUser,
          displayName: _nameController.text.trim(),
          locale: _locale,
          privacyNoticeAccepted: _privacyNoticeAccepted,
          accountType: _organizationAccount ? 'organization' : 'patient',
          organizationName: _organizationNameController.text,
          city: _cityController.text,
        );
      } else {
        await FirebaseService.signUpWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
          locale: _locale,
          privacyNoticeAccepted: _privacyNoticeAccepted,
          accountType: _organizationAccount ? 'organization' : 'patient',
          organizationName: _organizationNameController.text,
          city: _cityController.text,
        );
      }

      if (!_organizationAccount &&
          _invitationCodeController.text.trim().isNotEmpty) {
        await FirebaseService.sendCurrentUserEmailVerification();
        if (mounted) {
          setState(() => _awaitingInvitationEmailVerification = true);
        }
        return;
      }

      final user = FirebaseService.currentUser;
      if (user != null) {
        final profile = await FirebaseService.getUserProfile(user.uid);
        if (profile != null) {
          ref.read(userProfileProvider.notifier).state = profile;
        }
      }

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => _organizationAccount
                ? const OrganizationDashboardScreen()
                : const HomeScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        final authAccountExists =
            FirebaseService.currentUser?.email?.toLowerCase() ==
            _emailController.text.trim().toLowerCase();
        setState(() {
          _accountSetupIncomplete = authAccountExists;
          _errorMessage = FirebaseService.mapAccountSetupError(
            e,
            authAccountExists: authAccountExists,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignUp() async {
    if (_isLoading) return;
    if (!_privacyNoticeAccepted) {
      setState(() {
        _errorMessage = 'Please acknowledge the privacy notice to continue.';
      });
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Enter your name before continuing.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final cred = await FirebaseService.signInWithGoogle();
      if (cred != null && cred.user != null) {
        var profile = await FirebaseService.getUserProfile(cred.user!.uid);
        await FirebaseService.completeAccountOnboarding(
          user: cred.user!,
          displayName: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : profile?.displayName ?? cred.user!.displayName ?? 'User',
          locale: _locale,
          privacyNoticeAccepted: _privacyNoticeAccepted,
          accountType: _organizationAccount ? 'organization' : 'patient',
          organizationName: _organizationNameController.text,
          city: _cityController.text,
        );
        profile = await FirebaseService.getUserProfile(cred.user!.uid);
        _accountSetupIncomplete = false;
        if (profile != null) {
          ref.read(userProfileProvider.notifier).state = profile;
        }

        if (!_organizationAccount &&
            _invitationCodeController.text.trim().isNotEmpty) {
          await _verifyAndCompletePatientInvitation();
          return;
        }

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => _organizationAccount
                  ? const OrganizationDashboardScreen()
                  : const HomeScreen(),
            ),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accountSetupIncomplete = FirebaseService.currentUser != null;
          _errorMessage = FirebaseService.mapAuthError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyAndCompletePatientInvitation() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = await FirebaseService.reloadCurrentUser();
      if (!user.emailVerified) {
        setState(() {
          _errorMessage =
              'Verify the invitation email first, then tap “I verified my email”.';
        });
        return;
      }
      final invitation = await FirebaseService.previewPatientAccountInvitation(
        _invitationCodeController.text,
      );
      if (!mounted) return;
      var shareDerivedProfile = false;
      final response = await showDialog<(bool, bool)>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Review patient invitation'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${invitation.organizationName}${invitation.organizationCity.isEmpty ? '' : ', ${invitation.organizationCity}'} invited you to link the patient record for ${invitation.patientName}.',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: shareDerivedProfile,
                  onChanged: (value) => setDialogState(
                    () => shareDerivedProfile = value ?? false,
                  ),
                  title: const Text(
                    'I agree to share derived profile data with this organization.',
                  ),
                  subtitle: const Text(
                    'Raw VCF files stay on your device. No profile data is synced by this link today.',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, (false, false)),
                child: const Text('Decline link'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(dialogContext, (true, shareDerivedProfile)),
                child: const Text('Accept link'),
              ),
            ],
          ),
        ),
      );
      if (response == null) return;
      final result = await FirebaseService.respondToPatientAccountInvitation(
        code: _invitationCodeController.text,
        accepted: response.$1,
        shareDerivedProfile: response.$2,
      );
      final profile = await FirebaseService.getUserProfile(user.uid);
      if (profile != null) {
        ref.read(userProfileProvider.notifier).state = profile;
      }
      if (!mounted) return;
      if (result['accepted'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Patient record linked. Your VCF file and analysis remain on this device.',
            ),
          ),
        );
      }
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = FirebaseService.mapAuthError(error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final passwordText = _passwordController.text;
    final strengthScore = _calculateStrengthScore(passwordText);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Status badges
              _buildHeaderSection(),
              const SizedBox(height: 18),

              // Card Form Container
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.cardBorder, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Inline Error Banner if present
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.dangerRedBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.dangerRed.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: AppTheme.dangerRed,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.inter(
                                    color: AppTheme.dangerRed,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Text(
                        'Choose which workspace to open after signup. Organization name and city are publicly listed as unverified organization details.',
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Patient'),
                            icon: Icon(Icons.person_outline),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Organization'),
                            icon: Icon(Icons.apartment_outlined),
                          ),
                        ],
                        selected: {_organizationAccount},
                        onSelectionChanged: (selection) => setState(
                          () => _organizationAccount = selection.first,
                        ),
                      ),
                      if (_organizationAccount) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'This opens the organization dashboard and lists the organization name and city in patient search as self-registered and unverified. It does not grant access to patient data.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _organizationNameController,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Organization name',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          validator: (value) {
                            if (_organizationAccount &&
                                (value?.trim().isEmpty ?? true)) {
                              return 'Enter your organization name.';
                            }
                            return null;
                          },
                        ),
                        TextFormField(
                          controller: _cityController,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            prefixIcon: Icon(Icons.location_city_outlined),
                          ),
                          validator: (value) {
                            if (_organizationAccount &&
                                (value?.trim().isEmpty ?? true)) {
                              return 'Enter your organization city.';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      _buildLocaleSelector(),
                      const SizedBox(height: 16),

                      // Full Name field with Legal name sublabel
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Full Name',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.deepInk,
                            ),
                          ),
                          Text(
                            'Legal name',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                              color: AppTheme.mutedGrey,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.deepInk,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Alex Morgan',
                          prefixIcon: const Icon(
                            Icons.badge_outlined,
                            size: 20,
                            color: AppTheme.secondaryInk,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter your full name.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Email Address field
                      Text(
                        'Email Address',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.deepInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.deepInk,
                        ),
                        decoration: InputDecoration(
                          hintText: 'alex@example.com',
                          prefixIcon: const Icon(
                            Icons.alternate_email_rounded,
                            size: 19,
                            color: AppTheme.secondaryInk,
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter an email address.';
                          }
                          if (!val.contains('@') || !val.contains('.')) {
                            return 'Please enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      if (!_organizationAccount) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _invitationCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Hospital invitation code (optional)',
                            helperText:
                                'Enter a code supplied by your hospital to review a patient-record link.',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Password Field
                      Text(
                        'Password',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.deepInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.deepInk,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(
                            Icons.lock_outline_rounded,
                            size: 20,
                            color: AppTheme.secondaryInk,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppTheme.secondaryInk,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Please enter a password.';
                          }
                          if (val.length < 8) {
                            return 'Password must be at least 8 characters long.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),

                      // 4-segment visual security meter
                      Row(
                        children: List.generate(4, (i) {
                          return Expanded(
                            child: Container(
                              height: 4,
                              margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                              decoration: BoxDecoration(
                                color: _getStrengthSegmentColor(
                                  i,
                                  strengthScore,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Min. 8 characters',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.mutedGrey,
                            ),
                          ),
                          if (passwordText.isNotEmpty)
                            Text(
                              strengthScore >= 3
                                  ? 'Strong'
                                  : 'Required: 8+ chars',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _getStrengthSegmentColor(
                                  strengthScore - 1,
                                  strengthScore,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password Field
                      Text(
                        'Confirm Password',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.deepInk,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppTheme.deepInk,
                        ),
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          prefixIcon: const Icon(
                            Icons.shield_outlined,
                            size: 20,
                            color: AppTheme.secondaryInk,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: AppTheme.secondaryInk,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) {
                            return 'Please confirm your password.';
                          }
                          if (val != _passwordController.text) {
                            return 'Passwords do not match.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.mintSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: const Text(
                          'Privacy notice v1.1: your name, account type, and language are stored with your account. If you sign up as an organization, its name and city are listed in patient search as self-registered and unverified. This public listing does not grant access to patient data. Raw VCF files are parsed locally and are not uploaded. Analysis reports remain on this device unless a separately designed, explicit sharing feature is offered. Cloud AI stays off unless you opt in for a specific use. This signup does not collect professional registration details.',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.transparent,
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _privacyNoticeAccepted,
                          onChanged: (value) => setState(() {
                            _privacyNoticeAccepted = value ?? false;
                          }),
                          title: const Text(
                            'I acknowledge the privacy notice above.',
                          ),
                        ),
                      ),
                      if (_awaitingInvitationEmailVerification) ...[
                        const SizedBox(height: 12),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: Text(
                              'A verification email was sent to your signup email. Verify it, then continue to review or decline the hospital link.',
                            ),
                          ),
                        ),
                      ],

                      // Primary CTA: Create Account →
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : _awaitingInvitationEmailVerification
                              ? _verifyAndCompletePatientInvitation
                              : _handleSignUp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryEmerald,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      _awaitingInvitationEmailVerification
                                          ? 'I verified my email'
                                          : _accountSetupIncomplete
                                          ? 'Retry account setup'
                                          : 'Create Account',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Divider: OR
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppTheme.cardBorder)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: GoogleFonts.inter(
                                color: AppTheme.mutedGrey,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: AppTheme.cardBorder)),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Secondary Button: Continue with Google
                      OutlinedButton(
                        onPressed: _isLoading ? null : _handleGoogleSignUp,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(
                            color: AppTheme.cardBorder,
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          backgroundColor: Colors.white,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text(
                                  'G',
                                  style: TextStyle(
                                    color: Color(0xFFEA4335),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Continue with Google',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.deepInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Footer & Disclaimers
              const SecurityCalloutCard(
                text:
                    'Raw VCF files are parsed on this device. Organization dashboard access is assigned by an organization administrator.',
              ),
              const SizedBox(height: 18),

              // Switch link: Already have an account? Sign In
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Already have an account?',
                    style: GoogleFonts.inter(
                      color: AppTheme.secondaryInk,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text(
                      'Sign In',
                      style: GoogleFonts.inter(
                        color: AppTheme.primaryEmerald,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocaleSelector() => DropdownButtonFormField<String>(
    initialValue: _locale,
    decoration: const InputDecoration(
      labelText: 'Preferred language',
      prefixIcon: Icon(Icons.language),
    ),
    items: const [
      DropdownMenuItem(value: 'en', child: Text('English')),
      DropdownMenuItem(value: 'hi', child: Text('Hindi')),
      DropdownMenuItem(value: 'mr', child: Text('Marathi')),
    ],
    onChanged: (value) => setState(() => _locale = value ?? 'en'),
  );

  Widget _buildHeaderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top status badges row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.lightEmeraldPill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accentEmerald.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 13,
                    color: AppTheme.primaryEmerald,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'PRIVATE BY DEFAULT • ADVISORY',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDarkEmerald,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Text(
                'v2.4 Ready',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.secondaryInk,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Heading & Subtitle
        Text(
          'Create your NoCapRX account',
          style: GoogleFonts.inter(
            fontSize: 23,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppTheme.deepInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Start checking drug-gene compatibility safely.',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            color: AppTheme.secondaryInk,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}
