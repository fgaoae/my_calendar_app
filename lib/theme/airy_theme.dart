import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AiryPalette {
  static const Color canvas = Color(0xFFF4F7FF);
  static const Color canvasDeep = Color(0xFFEAF0FF);
  static const Color panel = Color(0xFFFFFFFF);
  static const Color panelTint = Color(0xFFF8FBFF);

  static const Color textPrimary = Color(0xFF10223C);
  static const Color textSecondary = Color(0xFF4A5D7A);
  static const Color textMuted = Color(0xFF7C8AA3);

  static const Color accent = Color(0xFF2D7EF7);
  static const Color accentSoft = Color(0xFFDCEAFF);
  static const Color success = Color(0xFF1EA97C);
  static const Color danger = Color(0xFFE25757);

  // Subtle cool-tone variants that stay within the Airy visual language.
  static const List<Color> databaseAccents = [
    Color(0xFF2D7EF7),
    Color(0xFF3A8CE9),
    Color(0xFF2F9BCF),
    Color(0xFF2CA7A0),
    Color(0xFF5B8DE3),
    Color(0xFF4F97BD),
  ];

  static const Color border = Color(0xFFD8E3F6);
  static const Color shadow = Color(0xFF8EA4C7);

  static int stableStringHash(String value) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return hash;
  }

  static Color databaseAccentForId(String? databaseId) {
    if (databaseId == null || databaseId.isEmpty) {
      return accent;
    }
    final index = stableStringHash(databaseId) % databaseAccents.length;
    return databaseAccents[index];
  }
}

class AiryTheme {
  static ThemeData get themeData {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AiryPalette.accent,
      brightness: Brightness.light,
    ).copyWith(
      primary: AiryPalette.accent,
      secondary: AiryPalette.accent,
      surface: AiryPalette.panel,
      error: AiryPalette.danger,
    );

    final textTheme = GoogleFonts.manropeTextTheme().copyWith(
      headlineSmall: GoogleFonts.manrope(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AiryPalette.textPrimary,
        letterSpacing: -0.2,
      ),
      titleLarge: GoogleFonts.manrope(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AiryPalette.textPrimary,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AiryPalette.textPrimary,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AiryPalette.textPrimary,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AiryPalette.textSecondary,
      ),
      bodySmall: GoogleFonts.manrope(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AiryPalette.textMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AiryPalette.canvas,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: AiryPalette.textPrimary,
        titleTextStyle: textTheme.titleLarge,
        centerTitle: false,
      ),
      dividerColor: AiryPalette.border,
      dividerTheme: const DividerThemeData(space: 1, thickness: 1),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: AiryPalette.panel.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AiryPalette.border.withValues(alpha: 0.7)),
        ),
      ),
      dialogTheme: DialogThemeData(
        elevation: 0,
        backgroundColor: AiryPalette.panel.withValues(alpha: 0.94),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AiryPalette.border.withValues(alpha: 0.9)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AiryPalette.panelTint.withValues(alpha: 0.85),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AiryPalette.border.withValues(alpha: 0.9)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AiryPalette.border.withValues(alpha: 0.9)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AiryPalette.accent, width: 1.8),
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodySmall,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: AiryPalette.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AiryPalette.border.withValues(alpha: 0.95)),
          foregroundColor: AiryPalette.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 13),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        indicatorColor: AiryPalette.accentSoft,
        backgroundColor: AiryPalette.panel.withValues(alpha: 0.9),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AiryPalette.accent : AiryPalette.textSecondary,
            size: selected ? 24 : 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? AiryPalette.accent : AiryPalette.textSecondary,
          );
        }),
      ),
    );
  }

  static const Duration quick = Duration(milliseconds: 220);
  static const Duration medium = Duration(milliseconds: 360);
  static const Duration slow = Duration(milliseconds: 520);

  static BoxDecoration get airySurfaceDecoration {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AiryPalette.panel.withValues(alpha: 0.87),
          AiryPalette.panelTint.withValues(alpha: 0.94),
        ],
      ),
      border: Border.all(color: AiryPalette.border.withValues(alpha: 0.82)),
      boxShadow: [
        BoxShadow(
          color: AiryPalette.shadow.withValues(alpha: 0.18),
          blurRadius: 28,
          spreadRadius: -6,
          offset: const Offset(0, 14),
        ),
      ],
    );
  }
}
