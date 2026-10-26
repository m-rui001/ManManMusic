import "dart:async";
import "dart:io";

import "package:app_links/app_links.dart";
import "package:audio_service/audio_service.dart";
import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/constants/notification.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/model.dart";
import "package:bobomusic/modules/history/play_history.dart";
import "package:bobomusic/permission/permission.dart";
import "package:bobomusic/utils/get_cache_color.dart";
import "package:bobomusic/utils/window_manage.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/home/home.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/service.dart";
import "package:bobomusic/modules/share/share_handler.dart";
import "package:bobomusic/modules/share/share_payload.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bobomusic/utils/bili_link.dart";
import "package:flutter/services.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:just_audio_media_kit/just_audio_media_kit.dart";
import "package:provider/provider.dart";

// toast 初始化
final botToastBuilder = BotToastInit();
// 主题
Color primaryColor = Colors.black;
// 数据库
final DBOrder db = DBOrder(version: 2);

ThemeData theme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.white,
    primary: primaryColor,
    brightness: Brightness.light,
  ),
  primaryColor: primaryColor,
  appBarTheme: const AppBarTheme(
    backgroundColor: Color.fromARGB(255, 245, 245, 245)
  ),
  popupMenuTheme: const PopupMenuThemeData(
    color: Color.fromARGB(255, 245, 245, 245)
  ),
  scaffoldBackgroundColor: const Color.fromARGB(255, 245, 245, 245),
  bottomSheetTheme: BottomSheetThemeData(
    backgroundColor: Colors.grey[200],
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(10),
        topRight: Radius.circular(10),
      ),
    ),
  ),
);

final _playerHandler = AudioPlayerHandler();

void main() async {
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await initWindowManage();
  }

  WidgetsFlutterBinding.ensureInitialized();
  await loadAppInfo();
  JustAudioMediaKit.ensureInitialized(
    iOS: false,
    android: false,
    windows: true,
    linux: true,
    macOS: false,
  );
  final playerService = await AudioService.init(
    builder: () => _playerHandler,
    config: AudioServiceConfig(
      androidNotificationChannelId: NotificationAudio.channelId,
      androidNotificationChannelName: NotificationAudio.channelName,
      androidNotificationOngoing: true,
    ),
  );

  await db.deleteAll(TableName.musicWaitPlay);

  // 读取 B 站登录态（失败不影响启动）
  await BiliAuth.instance.init();

  // 历史播放（纯本地）
  await PlayHistory.instance.init();

  primaryColor = await getCacheColor();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => PlayerModel()),
        ChangeNotifierProvider(create: (context) => DownloadModel()),
      ],
      child: MyApp(
        initialTheme: theme.copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.white,
            primary: primaryColor,
            brightness: Brightness.light,
          ),
          primaryColor: primaryColor,
        ),
        playerHandler: _playerHandler,
        playerService: playerService,
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  final ThemeData initialTheme;
  final AudioPlayerHandler playerHandler;
  final AudioHandler playerService;

  const MyApp({
    super.key,
    required this.initialTheme,
    required this.playerHandler,
    required this.playerService,
  });

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late ThemeData _currentTheme;
  StreamSubscription? _themeColorSubscription;

  @override
  void initState() {
    super.initState();
    Provider.of<PlayerModel>(context, listen: false).init(
      playerHandler: widget.playerHandler,
      playerService: widget.playerService,
    );

    // 记录历史播放
    widget.playerHandler.player.onPlayRecord = (music) {
      PlayHistory.instance.record(music);
    };
    _currentTheme = widget.initialTheme;

    // 一起听：挂载播放器
    PartySession.instance.attach(
      Provider.of<PlayerModel>(context, listen: false),
    );

    _initDeepLinks();
    IncomingShare.listen((text) => _onSharedText(text));

    _themeColorSubscription = eventBus.on<ThemeColorChanged>().listen((event) {
      setState(() {
        primaryColor = event.newColor;
        _currentTheme = _currentTheme.copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.white,
            primary: primaryColor,
            brightness: Brightness.light,
          ),
          primaryColor: primaryColor,
        );
      });
    });

    Permissions.requestNotificationPermission();

    // 冷启动延时读取剪贴板，自动识别分享链接（避开首页登录弹窗）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        autoCheckClipboard(context);
      });
    });
  }

  StreamSubscription<Uri>? _linkSub;

  /// 监听深度链接（满满音乐 / manman:// 与 B 站分享）
  void _initDeepLinks() {
    final appLinks = AppLinks();
    _linkSub = appLinks.uriLinkStream.listen(_onUri);

    // 冷启动时可能已有链接
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _onUri(uri);
    });
  }

  /// 其它 App 分享过来的文本
  Future<void> _onSharedText(String text) async {
    if (!mounted) return;
    final payload = parseManmanShareText(text);
    if (payload != null) {
      await handleSharePayload(context, payload);
      return;
    }
    if (extractBiliUrl(text) != null) {
      await openBiliShareText(context, text);
      return;
    }
    BotToast.showText(text: "没有识别到可播放的内容");
  }

  Future<void> _onUri(Uri uri) async {
    if (!mounted) return;

    // 满满音乐分享
    final payload = parseManmanUri(uri);
    if (payload != null) {
      await handleSharePayload(context, payload);
      return;
    }

    // B 站链接
    final text = uri.toString();
    if (extractBiliUrl(text) != null) {
      await openBiliShareText(context, text);
    }
  }

  @override
  void dispose() {
    _themeColorSubscription?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 隐藏 Android 底部导航条
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return MaterialApp(
      theme: _currentTheme,
      home: const HomeView(),
      debugShowCheckedModeBanner: false,
      navigatorObservers: [BotToastNavigatorObserver()],
      builder: (context, child) {
        child = EasyLoading.init()(context, child);
        child = botToastBuilder(context, child);
        // 消息提示框的默认配置
        BotToast.defaultOption.text.duration = const Duration(seconds: 3);
        BotToast.defaultOption.text.textStyle = TextStyle(
          fontSize: 12,
          color: Theme.of(context).cardColor,
        );
        EasyLoading.instance.indicatorType = EasyLoadingIndicatorType.cubeGrid;
        return child;
      },
    );
  }
}
