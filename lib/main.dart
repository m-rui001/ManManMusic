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
import "package:bobomusic/modules/party/party_tone.dart";
import "package:bobomusic/modules/party/party_background.dart";
import "package:bobomusic/modules/party/party_watcher.dart";
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
final DBOrder db = DBOrder();

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

  // 一起听提示音设置
  await PartyTone.instance.initFromStorage();

  // 好友上线提醒：前台自己轮询，后台交给 WorkManager
  await PartyBackground.init();
  await PartyWatcher.instance.init();

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

class MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late ThemeData _currentTheme;
  StreamSubscription? _themeColorSubscription;

  /// 回前台时提示剪贴板链接要用，不能拿 MaterialApp 外面的 context
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 以前用 immersiveSticky 把系统导航栏藏起来，结果底部三个 tab
    // 正好压在返回键 / 圆圈 / 方框上，退出还得先上滑。
    // 改成 edgeToEdge：系统栏常驻，SafeArea 会自动让出高度。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );

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

    // 打开 App 自动上线一起听（设置里可关）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PartySession.instance.autoOnlineIfEnabled();
    });

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _checkClipboardOnResume();
  }

  /// 从后台回到前台：剪贴板里有新的分享链接就提示一下，不自动播放
  ///
  /// 冷启动才直接处理（那是用户主动复制的），
  /// 回前台只给一个 SnackBar，点「打开」才真的处理。
  Future<void> _checkClipboardOnResume() async {
    final text = await ClipboardShareWatcher.pollNewShare();
    if (text == null || !mounted) return;

    // 等页面转场稳定再弹，别一回来就糊一脸
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final messenger = _messengerKey.currentState;
    if (messenger == null) return;

    final isParty = parseManmanShareText(text) != null;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isParty ? "剪贴板里有一个一起听邀请" : "剪贴板里有 B 站链接",
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: "打开",
          onPressed: () {
            final ctx = _navKey.currentContext;
            if (ctx == null) return;
            final payload = parseManmanShareText(text);
            if (payload != null) {
              handleSharePayload(ctx, payload);
            } else {
              openBiliShareText(ctx, text);
            }
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeColorSubscription?.cancel();
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: _currentTheme,
      home: const HomeView(),
      debugShowCheckedModeBanner: false,
      navigatorKey: _navKey,
      scaffoldMessengerKey: _messengerKey,
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
