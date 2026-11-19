import "package:flutter/material.dart";
import "package:flutter/services.dart";

class ThemeColor {
  static final List<Color> availableColors = [
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.black,
  ];

  static final List<String> colorNames = [
    "晚霞红",
    "秋日橙",
    "柠檬黄",
    "自然绿",
    "海洋蓝",
    "暮色靛",
    "韵味紫",
    "深空黑",
  ];
}

ThemeData buildAppTheme(Color accent, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final neutral = accent == Colors.black;
  final generated = ColorScheme.fromSeed(
    seedColor: neutral ? const Color(0xFF777780) : accent,
    brightness: brightness,
  );
  final colors = generated.copyWith(
    primary: neutral
        ? dark
            ? const Color(0xFFE9E9ED)
            : Colors.black
        : generated.primary,
    onPrimary: neutral
        ? dark
            ? const Color(0xFF17171B)
            : Colors.white
        : generated.onPrimary,
    surface: dark ? const Color(0xFF121215) : const Color(0xFFF5F5F5),
    onSurface: dark ? const Color(0xFFF0F0F2) : const Color(0xFF202024),
    onSurfaceVariant: dark ? const Color(0xFFBABAC4) : const Color(0xFF5C5C65),
    surfaceContainerLowest: dark ? const Color(0xFF0D0D10) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF19191E) : Colors.white,
    surfaceContainer: dark ? const Color(0xFF202026) : const Color(0xFFEEEEEE),
    surfaceContainerHigh:
        dark ? const Color(0xFF292930) : const Color(0xFFE8E8E8),
    surfaceContainerHighest:
        dark ? const Color(0xFF34343C) : const Color(0xFFE0E0E0),
    outline: dark ? const Color(0xFF90909B) : const Color(0xFF777780),
    outlineVariant: dark ? const Color(0xFF42424C) : const Color(0xFFD5D5DA),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    primaryColor: colors.primary,
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      systemOverlayStyle: appSystemOverlayStyle(brightness),
    ),
    popupMenuTheme: PopupMenuThemeData(color: colors.surfaceContainerLow),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
    ),
  );
}

SystemUiOverlayStyle appSystemOverlayStyle(Brightness brightness) {
  final style = brightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  return style.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: style.statusBarIconBrightness,
    systemNavigationBarContrastEnforced: false,
  );
}
