import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Base dark palette — premium glassmorphism foundation
  static const Color background = Color(0xFF050508);
  static const Color surface = Color(0xFF0F0F14);
  static const Color surfaceLight = Color(0xFF1A1A24);
  static const Color cardDark = Color(0xFF0D0D12);

  // Dopamine Tutor brand gradient colors
  static const Color dopamineStart = Color(0xFF7C3AED);  // Vivid Purple
  static const Color dopamineMid   = Color(0xFF2DD4BF);  // Teal
  static const Color dopamineEnd   = Color(0xFFEC4899);   // Hot Pink

  // Accent colors
  static const Color accent = Color(0xFF7C3AED);
  static const Color accentGlow = Color(0x337C3AED);
  static const Color xpGold = Color(0xFFFBBF24);          // XP / Streak gold
  static const Color streakFire = Color(0xFFEF4444);       // Missed-block fire

  // Text
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFA1A1AA);
  static const Color textHint = Color(0xFF71717A);

  // Subject card accents — vibrant study-subject colors
  static const List<Color> noteAccents = [
    Color(0xFF7C3AED),  // Purple — Math
    Color(0xFF2DD4BF),  // Teal — Science
    Color(0xFFEC4899),  // Pink — Literature
    Color(0xFFFBBF24),  // Gold — History
    Color(0xFF3B82F6),  // Blue — Programming
    Color(0xFF10B981),  // Green — Biology
    Color(0xFFF97316),  // Orange — Physics
    Color(0xFF8B5CF6),  // Violet — Art
  ];

  // Calendar study block colors
  static const List<Color> eventColors = [
    Color(0xFF7C3AED),
    Color(0xFF2DD4BF),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFFFBBF24),
  ];

  // Gradients
  static const LinearGradient dopamineGradient = LinearGradient(
    colors: [dopamineStart, dopamineMid, dopamineEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dopamineGradientHorizontal = LinearGradient(
    colors: [dopamineStart, dopamineMid, dopamineEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [surface, surfaceLight],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient xpGradient = LinearGradient(
    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B), Color(0xFFEF4444)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Glass tokens
  static const Color glassPrimary = Color(0xCC0F0F14);
  static const Color glassSecondary = Color(0x991A1A24);
  static const Color glassBorder = Color(0x1AFFFFFF);

  // Welwi compatibility colors
  static const Color welwiStart = dopamineStart;
  static const Color welwiEnd = dopamineEnd;
  static const LinearGradient welwiGradient = dopamineGradient;
  static const LinearGradient welwiGradientHorizontal = dopamineGradientHorizontal;
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        secondary: AppColors.dopamineStart,
        surface: AppColors.surface,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
          headlineLarge: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: AppColors.textPrimary,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: AppColors.textHint,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 8,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textHint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}
