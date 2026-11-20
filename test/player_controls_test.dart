import "dart:async";
import "dart:ui" show SemanticsAction;

import "package:bobomusic/constants/theme_color.dart";
import "package:bobomusic/components/pressable.dart";
import "package:bobomusic/modules/player/const.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_scroller.dart";
import "package:bobomusic/modules/player/player.dart";
import "package:bobomusic/modules/player/player_card/card.dart";
import "package:bobomusic/modules/player/player_card/progress.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_lyric/lyrics_reader_widget.dart";
import "package:flutter_test/flutter_test.dart";
import "package:provider/provider.dart";

class TestPlayer extends PlayerModel {
  TestPlayer(this.duration);

  @override
  final Duration? duration;

  Duration? seekTarget;
  Completer<void>? pendingSeek;

  @override
  Duration get bufferedPosition => const Duration(seconds: 80);

  @override
  Future<void> seek(Duration position) async {
    seekTarget = position;
    await pendingSeek?.future;
  }
}

void main() {
  testWidgets("按钮按下时立即缩小反馈，松开后复原", (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              pressScale: .9,
              onTap: () {},
              builder: (context, value) {
                pressed = value;
                return const SizedBox(width: 80, height: 48);
              },
            ),
          ),
        ),
      ),
    );

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(Pressable)));
    await tester.pump();
    expect(pressed, isTrue);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, .9);
    await gesture.up();
    await tester.pump();
    expect(pressed, isFalse);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets("前一次跳转返回时保留正在拖动的新位置", (tester) async {
    final player = TestPlayer(const Duration(seconds: 100));
    final pending = player.pendingSeek = Completer<void>();
    await showProgress(tester, player);
    final slider = find.byType(Slider);
    await tester.tap(slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(70, 0));
    await tester.pump();
    final dragged = tester.widget<Slider>(slider).value;
    expect(dragged, greaterThan(.5));
    pending.complete();
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, dragged);
    await gesture.up();
    await tester.pump();
    expect(player.seekTarget!.inMilliseconds, closeTo(dragged * 100000, 1));
  });

  testWidgets("读屏可识别播放进度并前后跳转", (tester) async {
    final player = TestPlayer(const Duration(seconds: 100));
    await showProgress(tester, player);
    final node = tester.getSemantics(find.byType(Slider));
    expect(node.value, startsWith("播放进度 "));
    expect(node.value, contains(" / 01:40"));
    final owner = tester.binding.renderViews.single.owner!.semanticsOwner!;
    owner.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(player.seekTarget, isNotNull);
    final later = player.seekTarget!;
    owner.performAction(node.id, SemanticsAction.decrease);
    await tester.pump();
    expect(player.seekTarget, lessThan(later));
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
    // 展开动画 520ms，等窗口长到位再断言
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(Theme.of(tester.element(close)).brightness, Brightness.dark);

    tester.view.physicalSize = const Size(800, 380);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byTooltip("播放队列").hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test("歌词行跳转抵消显示偏移，并限制在可播放范围", () {
    const duration = Duration(seconds: 100);
    expect(lyricSeekPosition(25000, 500, duration).inMilliseconds, 24500);
    expect(lyricSeekPosition(25000, -500, null).inMilliseconds, 25500);
    expect(lyricSeekPosition(0, 500, duration), Duration.zero);
    expect(lyricSeekPosition(99900, -500, duration), duration);
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

  testWidgets("歌词当前行比其余行亮，换主题色后高亮跟着换", (tester) async {
    final positions = StreamController<Duration>();
    final player = LyricTestPlayer(positions.stream);

    Widget app(Color accent) => ChangeNotifierProvider<PlayerModel>.value(
          value: player,
          child: MaterialApp(
            theme: buildAppTheme(accent, Brightness.light),
            home: const Scaffold(body: LyricsScroller()),
          ),
        );

    await tester.pumpWidget(app(Colors.blue));
    final reader = find.byType(LyricsReader);
    final blue = tester.widget<LyricsReader>(reader).ui;
    expect(blue.getPlayingMainTextStyle().color!.a,
        greaterThan(blue.getOtherMainTextStyle().color!.a));
    expect(blue.getLyricHightlightColor(),
        buildAppTheme(Colors.blue, Brightness.light).colorScheme.primary);

    await tester.pumpWidget(app(Colors.red));
    // MaterialApp 用 AnimatedTheme 过渡，单帧 pump 还停在旧主题上
    await tester.pump(const Duration(milliseconds: 300));
    final red = tester.widget<LyricsReader>(reader).ui;
    expect(red.getLyricHightlightColor(),
        buildAppTheme(Colors.red, Brightness.light).colorScheme.primary);

    await tester.pumpWidget(const SizedBox.shrink());
    unawaited(positions.close());
  });

  testWidgets("长按迷你播放器曲名复制干净文本", (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final player = LayoutPlayer(playing: false);
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerModel>.value(
        value: player,
        child: MaterialApp(
          navigatorObservers: [BotToastNavigatorObserver()],
          builder: BotToastInit(),
          home: const Scaffold(body: PlayerView()),
        ),
      ),
    );
    await tester.longPress(find.text(player.track.name));
    await tester.pump();
    final clip = calls.where((c) => c.method == "Clipboard.setData").single;
    expect((clip.arguments as Map)["text"], player.track.name);
    expect(tester.takeException(), isNull);
  });

  testWidgets("迷你播放器往上拖展开播放页", (tester) async {
    final player = LayoutPlayer(playing: false);
    await tester.pumpWidget(
      ChangeNotifierProvider<PlayerModel>.value(
        value: player,
        child: const MaterialApp(home: Scaffold(body: PlayerView())),
      ),
    );
    expect(find.byType(PlayerCard), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LinearProgressIndicator)),
    );
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.byType(PlayerCard), findsOneWidget);
    final transition = tester
        .widget<PlayerCard>(find.byType(PlayerCard))
        .transitionController!;
    expect(transition.value, greaterThan(.05));
    final first = transition.value;
    await gesture.moveBy(const Offset(0, -96));
    await tester.pump();
    expect(transition.value, greaterThan(first));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    final stage = find
        .descendant(
            of: find.byType(PlayerCard),
            matching: find.byWidgetPredicate((widget) =>
                widget is GestureDetector &&
                widget.onVerticalDragUpdate != null))
        .first;
    final pull = await tester.startGesture(tester.getCenter(stage));
    await pull.moveBy(const Offset(0, 30));
    await pull.moveBy(const Offset(0, 80));
    await tester.pump();
    final lowered = transition.value;
    expect(lowered, lessThan(1));
    await pull.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(transition.value, greaterThan(lowered));
    await pull.cancel();
    await tester.pumpAndSettle();
    expect(transition.value, 1);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets("Short drags settle after a pause or pointer cancellation",
      (tester) async {
    final player = LayoutPlayer(playing: false);
    await tester.pumpWidget(ChangeNotifierProvider<PlayerModel>.value(
      value: player,
      child: const MaterialApp(home: Scaffold(body: PlayerView())),
    ));
    for (final cancel in [false, true]) {
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(LinearProgressIndicator)));
      await gesture.moveBy(const Offset(0, -36),
          timeStamp: const Duration(milliseconds: 20));
      await tester.pump();
      expect(find.byType(PlayerCard), findsOneWidget);
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up(timeStamp: const Duration(milliseconds: 220));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PlayerCard), findsNothing);
      expect(tester.takeException(), isNull);
    }
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
