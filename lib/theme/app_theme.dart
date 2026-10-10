import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// NoCapRX design system.
///
/// Central brand + clinical tokens and the Material 3 theme built from them.
/// Screens should read colors/spacing/radii from here instead of hard-coding
/// values so the whole app stays visually consistent.
class AppTheme {
  AppTheme._();

  // ── Brand palette ─────────────────────────────────────────────────────────
  static const Color primaryEmerald = Color(0xFF0F3A2E);
  static const Color primaryDarkEmerald = Color(0xFF12372A);
  static const Color accentEmerald = Color(0xFF2E7D5B);
  static const Color vibrantMint = Color(0xFF10B981);
  static const Color mintSurface = Color(0xFFE8F5E9);
  static const Color lightEmeraldPill = Color(0xFFE6F4EA);

  // ── Backgrounds & surfaces ────────────────────────────────────────────────
  static const Color bgLight = Color(0xFFF7F9F7);
  static const Color surfaceLight = Colors.white;
  static const Color cardBorder = Color(0xFFE2E7E4);

  // ── Typography ink ────────────────────────────────────────────────────────
  static const Color deepInk = Color(0xFF121C18);
  static const Color secondaryInk = Color(0xFF52665D);
  static const Color mutedGrey = Color(0xFF6B7280);
  static const Color subtleFill = Color(0xFFF1F5F3);

  // ── Clinical status & risk ────────────────────────────────────────────────
  static const Color safeGreen = Color(0xFF059669);
  static const Color safeGreenBg = Color(0xFFD1FAE5);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color warningAmberBg = Color(0xFFFEF3C7);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color dangerRedBg = Color(0xFFFEE2E2);
  static const Color unknownSlate = Color(0xFF4B5563);
  static const Color unknownSlateBg = Color(0xFFF3F4F6);
  static const Color infoBlue = Color(0xFF2563EB);
  static const Color infoBlueBg = Color(0xFFDBEAFE);

  // ── Dark mode surfaces ────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0B1B15);
  static const Color surfaceDark = Color(0xFF11261E);
  static const Color cardBorderDark = Color(0xFF1B3D30);
  static const Color surfaceDarkHigh = Color(0xFF16382C);

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient brandGradient = LinearGradient(
    colors: [primaryEmerald, accentEmerald],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF0F3A2E), Color(0xFF1B5E44)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Spacing scale ─────────────────────────────────────────────────────────
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // ── Corner radii ──────────────────────────────────────────────────────────
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;
  static const double radiusXl = 28;

  // ── Elevation ─────────────────────────────────────────────────────────────
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x0F0F3A2E),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x080F3A2E),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];

  static const List<BoxShadow> liftedShadow = [
    BoxShadow(
      color: Color(0x1A0F3A2E),
      blurRadius: 28,
      offset: Offset(0, 14),
    ),
    BoxShadow(
      color: Color(0x0A0F3A2E),
      blurRadius: 6,
      offset: Offset(0, 3),
    ),
  ];

  // ── Light theme ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.interTextTheme();
    const scheme = ColorScheme.light(
      primary: primaryEmerald,
      onPrimary: Colors.white,
      primaryContainer: lightEmeraldPill,
      onPrimaryContainer: primaryDarkEmerald,
      secondary: accentEmerald,
      onSecondary: Colors.white,
      secondaryContainer: mintSurface,
      onSecondaryContainer: primaryDarkEmerald,
      tertiary: vibrantMint,
      onTertiary: Colors.white,
      surface: surfaceLight,
      onSurface: deepInk,
      surfaceContainerHighest: subtleFill,
      onSurfaceVariant: secondaryInk,
      outline: cardBorder,
      outlineVariant: cardBorder,
      error: dangerRed,
      onError: Colors.white,
      errorContainer: dangerRedBg,
      onErrorContainer: dangerRed,
    );

    return _baseTheme(
      scheme: scheme,
      scaffoldBackground: bgLight,
      surface: surfaceLight,
      border: cardBorder,
      textTheme: baseTextTheme.copyWith(
        displaySmall: GoogleFonts.inter(
          color: deepInk,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineLarge: GoogleFonts.inter(
          color: deepInk,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.inter(
          color: deepInk,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        headlineSmall: GoogleFonts.inter(
          color: deepInk,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: GoogleFonts.inter(
          color: deepInk,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.inter(
          color: deepInk,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(
          color: deepInk,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          color: secondaryInk,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.45,
        ),
        bodySmall: GoogleFonts.inter(
          color: mutedGrey,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          height: 1.35,
        ),
        labelLarge: GoogleFonts.inter(
          color: primaryEmerald,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Dark theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const scheme = ColorScheme.dark(
      primary: vibrantMint,
      onPrimary: primaryDarkEmerald,
      primaryContainer: surfaceDarkHigh,
      onPrimaryContainer: Colors.white,
      secondary: accentEmerald,
      onSecondary: Colors.white,
      secondaryContainer: surfaceDarkHigh,
      onSecondaryContainer: Colors.white,
      tertiary: vibrantMint,
      onTertiary: primaryDarkEmerald,
      surface: surfaceDark,
      onSurface: Colors.white,
      surfaceContainerHighest: surfaceDarkHigh,
      onSurfaceVariant: Color(0xFFB6CCC0),
      outline: cardBorderDark,
      outlineVariant: cardBorderDark,
      error: Color(0xFFF87171),
      onError: Color(0xFF3B0A0A),
      errorContainer: Color(0xFF4A1515),
      onErrorContainer: Color(0xFFFCA5A5),
    );

    final darkText = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return _baseTheme(
      scheme: scheme,
      scaffoldBackground: bgDark,
      surface: surfaceDark,
      border: cardBorderDark,
      textTheme: darkText.copyWith(
        headlineLarge: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        headlineMedium: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        headlineSmall: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5),
        bodyMedium: GoogleFonts.inter(
          color: const Color(0xFFB6CCC0),
          fontSize: 13,
          height: 1.45,
        ),
        bodySmall: GoogleFonts.inter(
          color: const Color(0xFF8FA89B),
          fontSize: 11.5,
          height: 1.35,
        ),
        labelLarge: GoogleFonts.inter(
          color: vibrantMint,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Shared builder so light and dark stay in lock-step.
  static ThemeData _baseTheme({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color surface,
    required Color border,
    required TextTheme textTheme,
  }) {
    final isLight = scheme.brightness == Brightness.light;
    final inputFill = isLight ? Colors.white : surfaceDarkHigh;
    final buttonSurface = isLight ? Colors.white : surfaceDarkHigh;

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      primaryColor: scheme.primary,
      scaffoldBackgroundColor: scaffoldBackground,
      colorScheme: scheme,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: border),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: scheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: scheme.primaryContainer,
        elevation: 3,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.inter(color: mutedGrey, fontSize: 14),
        labelStyle: GoogleFonts.inter(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: buttonSurface,
          elevation: 0,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm + 2),
          ),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          highlightColor: scheme.primary.withValues(alpha: 0.08),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isLight ? subtleFill : surfaceDarkHigh,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border),
        labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : buttonSurface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color>(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
          side: WidgetStateProperty.all(BorderSide(color: border)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? deepInk : surfaceDarkHigh,
        contentTextStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm + 2),
        ),
        insetPadding: const EdgeInsets.all(16),
        elevation: 3,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: scheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
        circularTrackColor: scheme.primaryContainer,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : (isLight ? Colors.white : const Color(0xFF6B7F76)),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : (isLight ? const Color(0xFFCBD5D0) : surfaceDarkHigh),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: BorderSide(color: scheme.onSurfaceVariant, width: 1.4),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: spaceLg,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isLight ? deepInk : surfaceDarkHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
