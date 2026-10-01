import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;
  void setMode(ThemeMode mode) => state = mode;
}

class AppColors extends ThemeExtension<AppColors> {
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color dialogSurface;
  final Color border;
  final Color coolAccent;
  final Color warmAccent;
  final Color dangerAccent;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.dialogSurface,
    required this.border,
    required this.coolAccent,
    required this.warmAccent,
    required this.dangerAccent,
  });

  /// Level colors are separate from the theme's primary accent.
  Color levelAccent(double db) => db >= 85
      ? dangerAccent
      : db >= 50
      ? warmAccent
      : coolAccent;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceLight,
    Color? textPrimary,
    Color? textSecondary,
    Color? dialogSurface,
    Color? border,
    Color? coolAccent,
    Color? warmAccent,
    Color? dangerAccent,
  }) => AppColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceLight: surfaceLight ?? this.surfaceLight,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    dialogSurface: dialogSurface ?? this.dialogSurface,
    border: border ?? this.border,
    coolAccent: coolAccent ?? this.coolAccent,
    warmAccent: warmAccent ?? this.warmAccent,
    dangerAccent: dangerAccent ?? this.dangerAccent,
  );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceLight: Color.lerp(surfaceLight, other.surfaceLight, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      dialogSurface: Color.lerp(dialogSurface, other.dialogSurface, t)!,
      border: Color.lerp(border, other.border, t)!,
      coolAccent: Color.lerp(coolAccent, other.coolAccent, t)!,
      warmAccent: Color.lerp(warmAccent, other.warmAccent, t)!,
      dangerAccent: Color.lerp(dangerAccent, other.dangerAccent, t)!,
    );
  }
}

class AppTheme {
  static const double recordingStatFontSize = 20;
  static const double recordingTimelineHeight = 160;
  static const double recordingPagePadding = 20;
  static const double recordingSectionSpacing = 16;
  static const double recordingControlHeight = 48;
  static const double recordingControlRadius = 12;
  static const double recordingToolbarRowWidth = 260;
  static const double recordingDetailsRowWidth = 280;
  static const double meterScaleLabelGap = 10;
  static const double meterAverageFontSize = 12;
  static const double meterIntermediateLabelScale = 0.85;
  static const double timeHistoryLineWidth = 1.5;
  static const double spectrumPeakOpacity = 0.5;
  static const double dbChartVerticalZoom = 2;
  static const double dbChartTickInterval = 10;

  static const Color coolDark = Color(0xFF80AEFF);
  static const Color warmDark = Color(0xFFFFD44D);
  static const Color coolLight = Color(0xFF245BC7);
  static const Color warmLight = Color(0xFF9C6900);
  static const Color dangerDark = Color(0xFFFF747B);
  static const Color dangerLight = Color(0xFFAA2635);
  static const Color errorDark = Color(0xFFFF8D86);
  static const Color errorLight = Color(0xFFB3261E);

  static const Color backgroundDark = Color(0xFF0B0D12);
  static const Color surfaceDark = Color(0xFF171A22);
  static const Color surfaceLightDark = Color(0xFF252A35);
  static const Color textPrimaryDark = Color(0xFFF8F9FC);
  static const Color textSecondaryDark = Color(0xFFAEB5C4);
  static const Color dialogSurfaceDark = Color(0xFF1C2029);
  static const Color borderDark = Color(0xFF3A4150);

  static const Color backgroundLight = Color(0xFFF6F8FC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightLight = Color(0xFFE9EEF7);
  static const Color textPrimaryLight = Color(0xFF161B28);
  static const Color textSecondaryLight = Color(0xFF586275);
  static const Color dialogSurfaceLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFD4DCE9);

  static const darkAppColors = AppColors(
    background: backgroundDark,
    surface: surfaceDark,
    surfaceLight: surfaceLightDark,
    textPrimary: textPrimaryDark,
    textSecondary: textSecondaryDark,
    dialogSurface: dialogSurfaceDark,
    border: borderDark,
    coolAccent: coolDark,
    warmAccent: warmDark,
    dangerAccent: dangerDark,
  );

  static const lightAppColors = AppColors(
    background: backgroundLight,
    surface: surfaceLight,
    surfaceLight: surfaceLightLight,
    textPrimary: textPrimaryLight,
    textSecondary: textSecondaryLight,
    dialogSurface: dialogSurfaceLight,
    border: borderLight,
    coolAccent: coolLight,
    warmAccent: warmLight,
    dangerAccent: dangerLight,
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundDark,
    primaryColor: warmDark,
    colorScheme: const ColorScheme.dark(
      primary: warmDark,
      onPrimary: backgroundDark,
      primaryContainer: Color(0xFF574518),
      onPrimaryContainer: Color(0xFFFFE29A),
      secondary: coolDark,
      onSecondary: backgroundDark,
      secondaryContainer: Color(0xFF253C66),
      onSecondaryContainer: Color(0xFFD7E5FF),
      surface: surfaceDark,
      onSurface: textPrimaryDark,
      surfaceContainerHighest: surfaceLightDark,
      onSurfaceVariant: textSecondaryDark,
      outlineVariant: borderDark,
      error: errorDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundDark,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: textPrimaryDark),
      titleTextStyle: TextStyle(
        color: textPrimaryDark,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(color: surfaceDark, elevation: 0),
    extensions: const [darkAppColors],
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: backgroundLight,
    primaryColor: coolLight,
    colorScheme: const ColorScheme.light(
      primary: coolLight,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE8FF),
      onPrimaryContainer: Color(0xFF173D87),
      secondary: warmLight,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFE9A9),
      onSecondaryContainer: Color(0xFF503600),
      surface: surfaceLight,
      onSurface: textPrimaryLight,
      surfaceContainerHighest: surfaceLightLight,
      onSurfaceVariant: textSecondaryLight,
      outlineVariant: borderLight,
      error: errorLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: backgroundLight,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: textPrimaryLight),
      titleTextStyle: TextStyle(
        color: textPrimaryLight,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: const CardThemeData(color: surfaceLight, elevation: 0),
    extensions: const [lightAppColors],
  );
}
