import 'package:flutter/material.dart';

/// Peran warna bermakna dengan kontras >= 4.5:1 (WCAG AA).
enum MetricRole {
  tekanan, // Biru
  suhu, // Merah-Oranye
  volume, // Ungu
  mol, // Hijau
}

class MetricPalette {
  const MetricPalette({
    required this.accent,
    required this.cardBgLight,
    required this.cardBorderLight,
    required this.textLight,
    required this.subtextLight,
    required this.cardBgDark,
    required this.cardBorderDark,
    required this.textDark,
  });

  final Color accent;
  final Color cardBgLight;
  final Color cardBorderLight;
  final Color textLight;
  final Color subtextLight;
  final Color cardBgDark;
  final Color cardBorderDark;
  final Color textDark;
}

class AppColors {
  AppColors._();

  // Identitas Biru Utama
  static const Color primary = Color(0xFF1A56DB);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primarySoft = Color(0xFFEFF6FF);

  // Aksen Jepang (Sakura & Seigaiha)
  static const Color sakuraPink = Color(0xFFF472B6);
  static const Color sakuraSoft = Color(0xFFFDF2F8);
  static const Color waveNavy = Color(0xFF1E3A8A);

  // Latar Polos Lembut (Mode Terang & Malam)
  static const Color bgLight = Color(0xFFF6F8FC);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFDCE4F0);
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF334155);

  static const Color bgDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color borderDark = Color(0xFF334155);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);

  // Status Koneksi & Umpan Balik (Kontras >= 4.5:1)
  static const Color success = Color(0xFF15803D);
  static const Color successBg = Color(0xFFF0FDF4);
  static const Color successBorder = Color(0xFF86EFAC);

  static const Color warning = Color(0xFF9A3412);
  static const Color warningBg = Color(0xFFFFF7ED);
  static const Color warningBorder = Color(0xFFFDBA74);

  static const Color danger = Color(0xFFB91C1C);
  static const Color dangerBg = Color(0xFFFEF2F2);
  static const Color dangerBorder = Color(0xFFFCA5A5);

  // Palet Warna Sensor Bermakna (Kontras Teks >= 5.0:1)
  static const MetricPalette tekananPalette = MetricPalette(
    accent: Color(0xFF1D4ED8),
    cardBgLight: Color(0xFFEFF6FF),
    cardBorderLight: Color(0xFFBFDBFE),
    textLight: Color(0xFF1E3A8A),
    subtextLight: Color(0xFF1E40AF),
    cardBgDark: Color(0xFF172554),
    cardBorderDark: Color(0xFF1D4ED8),
    textDark: Color(0xFFEFF6FF),
  );

  static const MetricPalette suhuPalette = MetricPalette(
    accent: Color(0xFFC2410C),
    cardBgLight: Color(0xFFFFF7ED),
    cardBorderLight: Color(0xFFFED7AA),
    textLight: Color(0xFF7C2D12),
    subtextLight: Color(0xFF9A3412),
    cardBgDark: Color(0xFF431407),
    cardBorderDark: Color(0xFFC2410C),
    textDark: Color(0xFFFFF7ED),
  );

  static const MetricPalette volumePalette = MetricPalette(
    accent: Color(0xFF6D28D9),
    cardBgLight: Color(0xFFF5F3FF),
    cardBorderLight: Color(0xFFDDD6FE),
    textLight: Color(0xFF4C1D95),
    subtextLight: Color(0xFF5B21B6),
    cardBgDark: Color(0xFF2E1065),
    cardBorderDark: Color(0xFF7C3AED),
    textDark: Color(0xFFF5F3FF),
  );

  static const MetricPalette molPalette = MetricPalette(
    accent: Color(0xFF15803D),
    cardBgLight: Color(0xFFF0FDF4),
    cardBorderLight: Color(0xFFBBF7D0),
    textLight: Color(0xFF14532D),
    subtextLight: Color(0xFF166534),
    cardBgDark: Color(0xFF052E16),
    cardBorderDark: Color(0xFF16A34A),
    textDark: Color(0xFFF0FDF4),
  );

  static MetricPalette paletteFor(MetricRole role) {
    switch (role) {
      case MetricRole.tekanan:
        return tekananPalette;
      case MetricRole.suhu:
        return suhuPalette;
      case MetricRole.volume:
        return volumePalette;
      case MetricRole.mol:
        return molPalette;
    }
  }
}

class AppSpacing {
  AppSpacing._();

  static const double s4 = 4.0;
  static const double s8 = 8.0;
  static const double s12 = 12.0;
  static const double s16 = 16.0;
  static const double s24 = 24.0;
  static const double s32 = 32.0;

  static const double screenMargin = 16.0;
  static const double cardGap = 12.0;
  static const double minTouchTarget = 48.0;
  static const double actionButtonHeight = 52.0;
}

class AppRadius {
  AppRadius._();

  static const double card = 20.0;
  static const double button = 16.0;
  static const double pill = 24.0;

  static BorderRadius get cardBorder => BorderRadius.circular(card);
  static BorderRadius get buttonBorder => BorderRadius.circular(button);
}

class AppTextStyles {
  AppTextStyles._();

  // Judul Layar: 22-24 bold
  static TextStyle screenTitle({bool modeTerang = true}) => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.2,
    color: modeTerang ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
  );

  // Subjudul Bagian: 18 bold
  static TextStyle sectionTitle({bool modeTerang = true}) => TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.25,
    color: modeTerang ? AppColors.textPrimaryLight : AppColors.textPrimaryDark,
  );

  // Angka Sensor Utama: 28-32 bold
  static TextStyle sensorValue({Color? color}) => TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.1,
    color: color ?? AppColors.textPrimaryLight,
  );

  // Satuan di samping angka sensor: 14 bold
  static TextStyle sensorUnit({Color? color}) => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: color ?? AppColors.textSecondaryLight,
  );

  // Label Kartu / Umum: 14
  static TextStyle label({bool modeTerang = true, Color? color}) => TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color:
        color ??
        (modeTerang
            ? AppColors.textSecondaryLight
            : AppColors.textSecondaryDark),
  );

  // Label Tebal: 14 bold
  static TextStyle labelBold({bool modeTerang = true, Color? color}) =>
      TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color:
            color ??
            (modeTerang
                ? AppColors.textPrimaryLight
                : AppColors.textPrimaryDark),
      );

  // Teks Terkecil (Caption / Axis / Badge): minimal 12sp
  static TextStyle caption({bool modeTerang = true, Color? color}) => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color:
        color ??
        (modeTerang
            ? AppColors.textSecondaryLight
            : AppColors.textSecondaryDark),
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData build({required bool modeTerang}) {
    final brightness = modeTerang ? Brightness.light : Brightness.dark;
    final bg = modeTerang ? AppColors.bgLight : AppColors.bgDark;
    final card = modeTerang ? AppColors.cardLight : AppColors.cardDark;
    final textPrimary = modeTerang
        ? AppColors.textPrimaryLight
        : AppColors.textPrimaryDark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
        primary: AppColors.primary,
        surface: card,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardBorder,
          side: BorderSide(
            color: modeTerang ? AppColors.borderLight : AppColors.borderDark,
          ),
        ),
      ),
      textTheme: TextTheme(
        headlineSmall: AppTextStyles.screenTitle(modeTerang: modeTerang),
        titleMedium: AppTextStyles.sectionTitle(modeTerang: modeTerang),
        bodyMedium: AppTextStyles.label(modeTerang: modeTerang),
        bodySmall: AppTextStyles.caption(modeTerang: modeTerang),
      ).apply(bodyColor: textPrimary, displayColor: textPrimary),
    );
  }
}
