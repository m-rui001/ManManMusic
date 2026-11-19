import "dart:async";

import "package:bobomusic/constants/theme_color.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_scroller.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/player_card/card.dart";
import "package:bobomusic/modules/player/player_card/progress.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter/material.dart";
import "package:flutter_lyric/lyrics_reader_widget.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";

class TestPlayer extends PlayerModel {
  TestPlayer(this.duration);

  @override
  final Duration? duration;

  Duration? seekTarget;

  @override
  Duration get bufferedPosition => const Duration(seconds: 80);

  @override
  Future<void> seek(Duration position) async {
    seekTarget = position;
  }
}

void main() {
  test("顺序模式从第 1 集播到第 4 集后停止，循环模式回到第 1 集", () {
    int? next(int current, PlayerMode mode) => nextQueueIndex(
          length: 4,
          current: current,
          offset: 1,
          mode: mode,
        );

    expect(next(-1, PlayerMode.listOrder), 0);
    expect(next(0, PlayerMode.listOrder), 1);
    expect(next(1, PlayerMode.listOrder), 2);
    expect(next(2, PlayerMode.listOrder), 3);
    expect(next(3, PlayerMode.listOrder), isNull);
    expect(next(3, PlayerMode.listLoop), 0);
    expect(next(1, PlayerMode.random), isNot(1));
  });

  Future<void> showProgress(WidgetTester tester, TestPlayer player,
          {TextDirection direction = TextDirection.ltr}) =>
      tester.pumpWidget(
        ChangeNotifierProvider<PlayerModel>.value(
          value: player,
          child: MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: const Scaffold(
                body: Center(
                  child: SizedBox(
                      width: 300, child: PlayerProgress(color: Colors.indigo)),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets("蝌蚪进度条显示缓冲并支持点击跳转", (tester) async {
    final player = TestPlayer(const Duration(seconds: 100));
    await showProgress(tester, player);
    final slider = find.byType(Slider);
    expect(tester.widget<Slider>(slider).secondaryTrackValue, .8);
    await tester.tap(slider);
    await tester.pump();
    expect(player.seekTarget!.inMilliseconds, closeTo(50000, 500));
    expect(tester.takeException(), isNull);
  });

  testWidgets("反向布局从右侧开始，时长未知时禁用跳转", (tester) async {
    final player = TestPlayer(const Duration(seconds: 100));
    await showProgress(tester, player, direction: TextDirection.rtl);
    final slider = find.byType(Slider);
    final bounds = tester.getRect(slider);
    await tester.tapAt(Offset(bounds.right - 42, bounds.center.dy));
    await tester.pump();
    expect(player.seekTarget!.inSeconds, lessThan(20));

    final loading = TestPlayer(null);
    await showProgress(tester, loading);
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets("播放时进度条有波动，系统减少动态效果时用平直轨道", (tester) async {
    final player = LayoutPlayer();
    await showProgress(tester, player);
    TadpoleTrackShape shape() => SliderTheme.of(
          tester.element(find.byType(Slider)),
        ).trackShape! as TadpoleTrackShape;
    expect(shape().amplitude, greaterThan(0));
    final before = shape().phase;
    await tester.pump(const Duration(milliseconds: 140));
    expect(shape().phase, isNot(before));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(shape().amplitude, 0);
  });

  testWidgets("全屏播放器避开状态栏且可以在窄屏和横屏使用", (tester) async {
    final player = LayoutPlayer(playing: false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 590);
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 24);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerModel>.value(
        value: player,
        child: MaterialApp(
          theme: buildAppTheme(Colors.black, Brightness.light),
          darkTheme: buildAppTheme(Colors.black, Brightness.dark),
          home: const Scaffold(body: PlayerView()),
        ),
      ),
    );
    await tester.tap(find.text(player.track.name));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(LyricsScroller), findsNothing);
    final close = find.byTooltip("收起播放器");
    expect(tester.getTopLeft(close).dy, greaterThanOrEqualTo(28));
    final play = find.descendant(
      of: find.byType(PlayerCard),
      matching: find.byTooltip("播放"),
    );
    expect(tester.getSize(play).width, greaterThan(80));
    expect(tester.takeException(), isNull);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(close)).brightness, Brightness.dark);

    tester.view.physicalSize = const Size(800, 380);
    await tester.pumpAndSettle();
    expect(find.byTooltip("播放队列").hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("歌词在暂停时跟随真实跳转位置", (tester) async {
    final positions = StreamController<Duration>();
    final player = LyricTestPlayer(positions.stream);

    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerModel>.value(
        value: player,
        child: const MaterialApp(home: Scaffold(body: LyricsScroller())),
      ),
    );

    final reader = find.byType(LyricsReader);
    expect(tester.widget<LyricsReader>(reader).position, 0);
    positions.add(const Duration(seconds: 26));
    await tester.pump();
    expect(tester.widget<LyricsReader>(reader).position, 26000);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<LyricsReader>(reader).position, 26000);
    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(positions.close());
  });
}

class LyricTestPlayer extends PlayerModel {
  LyricTestPlayer(this.positions);

  @override
  final Stream<Duration> positions;

  @override
  MusicItem get current => track;

  final track = MusicItem(
    id: "lyric_test",
    cover: "",
    name: "歌词测试",
    duration: 100,
    author: "",
    origin: OriginType.bili,
    lyric: "[00:00.00] 第一行\n[00:25.00] 第二行",
  );
}

class LayoutPlayer extends TestPlayer {
  LayoutPlayer({this.playing = true}) : super(const Duration(seconds: 906));

  final bool playing;

  @override
  bool get isPlaying => playing;

  @override
  Duration get currentPosition => const Duration(seconds: 430);

  @override
  MusicItem get current => track;

  final track = MusicItem(
    id: "",
    name: "第一乐章 · Andante con moto",
    author: "柏林爱乐乐团",
    cover: "",
    duration: 906,
    origin: OriginType.bili,
    lyric: "",
  );
}
