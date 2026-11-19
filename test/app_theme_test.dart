import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/constants/theme_color.dart";
import "package:bobomusic/modules/music_plaza/music_plaza.dart";
import "package:bobomusic/modules/setting/components/setting_card.dart";
import "package:bobomusic/modules/setting/setting.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:shared_preferences/shared_preferences.dart";

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test("深浅主题中的所有主题色均可用于文字和按钮", () {
    for (final brightness in Brightness.values) {
      for (final accent in ThemeColor.availableColors) {
        final theme = buildAppTheme(accent, brightness);
        final colors = theme.colorScheme;
        expect(_contrast(colors.primary, colors.surfaceContainerLow),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.onPrimary, colors.primary),
            greaterThanOrEqualTo(4.5));
      }
    }
  });

  test("首页继续播放卡在所有主题色下都读得清", () {
    for (final brightness in Brightness.values) {
      for (final accent in ThemeColor.availableColors) {
        final colors = buildAppTheme(accent, brightness).colorScheme;
        final palette = continuePlayingPalette(colors.primary);
        expect(_contrast(palette.foreground, palette.top),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(palette.foreground, palette.bottom),
            greaterThanOrEqualTo(4.5));
      }
    }
  });

  testWidgets("系统切换主题时设置页即时更新并保留品牌栏", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final platform = tester.platformDispatcher;
    platform.platformBrightnessTestValue = Brightness.light;
    addTearDown(platform.clearPlatformBrightnessTestValue);
    final light = buildAppTheme(Colors.black, Brightness.light);
    final dark = buildAppTheme(Colors.black, Brightness.dark);

    await tester.pumpWidget(MaterialApp(
      theme: light,
      darkTheme: dark,
      themeMode: ThemeMode.system,
      home: const SettingView(),
    ));
    await tester.pumpAndSettle();

    void checkTheme(ThemeData theme, Brightness systemIcons) {
      final branding = find.text(appSlogan);
      expect(branding.hitTestable(), findsOneWidget);
      expect(find.text(appName).hitTestable(), findsOneWidget);
      expect(Theme.of(tester.element(branding)).brightness, theme.brightness);
      final card = find.ancestor(
        of: branding,
        matching: find.byType(SettingCard),
      );
      final background = find
          .descendant(
            of: card,
            matching: find.byType(Material),
          )
          .first;
      expect(tester.widget<Material>(background).color,
          theme.colorScheme.surfaceContainerLow);
      expect(appSystemOverlayStyle(theme.brightness).statusBarIconBrightness,
          systemIcons);
      expect(
          appSystemOverlayStyle(theme.brightness)
              .systemNavigationBarIconBrightness,
          systemIcons);
    }

    checkTheme(light, Brightness.dark);
    platform.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    checkTheme(dark, Brightness.light);
    platform.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    checkTheme(light, Brightness.dark);
    expect(tester.takeException(), isNull);
  });
}
