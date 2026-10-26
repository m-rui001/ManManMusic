// ignore_for_file: use_build_context_synchronously

import "package:bobomusic/components/custom_dialog/custom_dialog.dart";
import "package:bobomusic/components/ripple_icon/ripple_icon.dart";
import "package:bobomusic/components/sheet/bottom_sheet.dart";
import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/main.dart";
import "package:bobomusic/modules/player/lyrics_card/lyric_search.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:flutter_lyric/lyric_ui/ui_netease.dart";
import "package:flutter_lyric/lyrics_model_builder.dart";
import "package:flutter_lyric/lyrics_reader_model.dart";
import "package:flutter_lyric/lyrics_reader_widget.dart";
import 'dart:async';
import "package:provider/provider.dart";
import "package:shared_preferences/shared_preferences.dart";

Future<int?> getMusicPosition() async {
  final localStorage = await SharedPreferences.getInstance();
  final pos = localStorage.getInt(
    CacheKey.playerPosition,
  );
  return pos;
}

final db = DBOrder();

class LyricsScroller extends StatefulWidget {
  const LyricsScroller({super.key});

  @override
  LyricsScrollerState createState() => LyricsScrollerState();
}

class LyricsScrollerState extends State<LyricsScroller> with SingleTickerProviderStateMixin {
  String lyric = "";
  List<Map<String, dynamic>> parsedLyrics = [];
  int currentLine = 0;
  Timer? _timer;
  int currentTime = 0;
  late LyricsReaderModel lyricModel;
  var lyricUI = UINetease(defaultSize: 16);
  final List<StreamSubscription?> _subscriptions = [];

  @override
  void initState() {
    super.initState();

    _subscriptions.add(eventBus.on<ScrollLyric>().listen((event) {
      doScroll();
    }));

    // 初始化一个空的 lyricModel
    lyricModel = LyricsModelBuilder.create().getModel();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      doScroll();
    });
  }

  @override
  void dispose() {
    resetState();
    for (var sub in _subscriptions) {
      sub?.cancel();
    }
    super.dispose();
  }

  resetState() {
    if (context.mounted && mounted) {
      setState(() {
        _timer?.cancel();
        lyric = "";
        parsedLyrics = [];
        currentLine = 0;
        currentTime = 0;
      });
    }
  }

  Future<void> doScroll() async {
    if (!context.mounted || !mounted) {
      return;
    }

    final player = context.read<PlayerModel>();

    if(player.current!.orderName.isEmpty) {
      return;
    }

    List<Map<String, dynamic>> dbMusic = [];

    dbMusic = await db.queryByParam(player.current!.orderName, player.current!.playId);

    if (dbMusic.isEmpty) {
      dbMusic = await db.queryByParam(player.current!.orderName, player.current!.id);
    }

    if (dbMusic.isEmpty) {
      resetState();
      return;
    }

    if (dbMusic.isNotEmpty) {
      final MusicItem musicItem = row2MusicItem(dbRow: dbMusic[0]);

      if (musicItem.lyric.isEmpty) {
        resetState();
        return;
      }

      setState(() {
        lyric = musicItem.lyric;
        parsedLyrics = parseLyrics(lyric);
        lyricModel = LyricsModelBuilder.create()
          .bindLyricToMain(lyric)
          .getModel();
      });
    }

    final initialPosition = await getMusicPosition();

    // 找到初始位置对应的歌词行
    for (int i = 0; i < parsedLyrics.length; i++) {
      if (parsedLyrics[i]["time"] > initialPosition) {
        currentLine = i > 0? i - 1 : 0;
        break;
      }
      if (i == parsedLyrics.length - 1) {
        currentLine = i;
      }
    }

    currentTime = parsedLyrics[currentLine]["time"];

    if (!player.isPlaying) {
      _timer?.cancel(); // 确保先取消之前的 Timer
      return;
    }

    startTimer();
  }

  void startTimer() {
    _timer?.cancel(); // 确保先取消之前的 Timer
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          currentTime += 100;
        });
      }
    });
  }

  void moveLyricsBackward(int speed, String tip) {
    BotToast.showText(text: "歌词减速 $tip s");
    setState(() {
      currentTime -= speed;
      // 重新找到后退后的歌词行
      for (int i = 0; i < parsedLyrics.length; i++) {
        if (parsedLyrics[i]["time"] > currentTime) {
          currentLine = i > 0? i - 1 : 0;
          break;
        }
        if (i == parsedLyrics.length - 1) {
          currentLine = i;
        }
      }
    });
  }

  void moveLyricsForward(int speed, String tip) {
    BotToast.showText(text: "歌词加速 $tip s");
    setState(() {
      currentTime += speed;
      // 重新找到前进后的歌词行
      for (int i = 0; i < parsedLyrics.length; i++) {
        if (parsedLyrics[i]["time"] > currentTime) {
          currentLine = i > 0? i - 1 : 0;
          break;
        }
        if (i == parsedLyrics.length - 1) {
          currentLine = i;
        }
      }
    });
  }

  Future<bool> checkLyric() async {
    final player = context.read<PlayerModel>();
    final dbMusic = await db.queryByParam(player.current!.orderName, player.current!.playId);

    if (dbMusic.isNotEmpty) {
      final MusicItem musicItem = row2MusicItem(dbRow: dbMusic[0]);

      if (musicItem.lyric.isEmpty) {
        BotToast.showText(text: "没有歌词");
        return false;
      }

      return true;
    } else {
      BotToast.showText(text: "出错了，请重新播放歌曲试试");
    }

    return false;
  }

  Future<void> deleteLyric() async {
    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    try {
      final player = context.read<PlayerModel>();

      final music = player.current!.copyWith(lyric: "");
      await db.update(player.current!.orderName, musicItem2Row(music: music));

      resetState();

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch(error) {
      BotToast.showText(text: "歌词删除失败");
    }

    EasyLoading.dismiss();
  }

  openMoreMenu() {
    openBottomSheet(context, [
      SheetItem(
        title: Text(
          "删除歌词",
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        onPressed: () async {
          if (!await checkLyric()) {
            return;
          }

          showDialog(
            context: context,
            builder: (BuildContext context) {
              return CustomDialog(
                body: const Text("删除歌词?"),
                onConfirm: () async {
                  deleteLyric();
                },
                onCancel: () {
                  Navigator.of(context).pop();
                },
              );
            },
          );
        }
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<PlayerModel>(
          builder: (context, player, child) {
            return Container(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 60),
              child: lyric.isNotEmpty ? LyricsReader(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                model: lyricModel,
                position: currentTime,
                lyricUi: lyricUI,
                playing: player.isPlaying,
                size: Size(double.infinity, MediaQuery.of(context).size.height - 160),
              ) : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "没有歌词",
                      style: TextStyle(color: primaryColor, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 30),
                    if(player.current!.orderName.isEmpty)
                        Text(
                          "当前歌曲不在任何歌单或者合集内，不支持匹配歌词",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: primaryColor, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                    if(player.current!.orderName.isNotEmpty)
                      TextButton(
                        style: TextButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.only(left: 32, right: 32),
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4)))
                        ),
                        onPressed: () async {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (BuildContext context) {
                                return const SearchLyricMusicView();
                              },
                            ),
                          );
                        },
                        child: const Text("去匹配歌词"),
                      ),
                  ],
                )
              ),
            );
          },
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(
              horizontal: 40,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                buildIconButton(
                  icon: Icons.keyboard_double_arrow_left_outlined,
                  onTap: () async {
                    if (!await checkLyric()) {
                      return;
                    }
                    moveLyricsBackward(2000, "2");
                  },
                  width: getButtonWidth(context, 0.1), // 使用自适应宽度
                ),
                buildIconButton(
                  icon: Icons.keyboard_arrow_left_rounded,
                  onTap: () async {
                    if (!await checkLyric()) {
                      return;
                    }
                    moveLyricsBackward(500, "0.5");
                  },
                  width: getButtonWidth(context, 0.1), // 使用自适应宽度
                ),
                buildIconButton(
                  icon: Icons.keyboard_arrow_right_outlined,
                  onTap: () async {
                    if (!await checkLyric()) {
                      return;
                    }
                    moveLyricsForward(500, "0.5");
                  },
                  width: getButtonWidth(context, 0.1), // 使用自适应宽度
                ),
                buildIconButton(
                  icon: Icons.keyboard_double_arrow_right_outlined,
                  onTap: () async {
                    if (!await checkLyric()) {
                      return;
                    }
                    moveLyricsForward(2000, "2");
                  },
                  width: getButtonWidth(context, 0.1), // 使用自适应宽度
                ),
                Transform.translate(
                  offset: const Offset(0, 1),
                  child: buildIconButton(
                    icon: Icons.more_vert_rounded,
                    onTap: () async {
                      openMoreMenu();
                    },
                    width: getButtonWidth(context, 0.1), // 使用自适应宽度
                    size: 24
                  )
                )
              ],
            ),
          ),
        )
      ],
    );
  }

  // 辅助方法：获取按钮的自适应宽度
  double getButtonWidth(BuildContext context, double percentage) {
    final screenWidth = MediaQuery.of(context).size.width - 80;
    return screenWidth * percentage;
  }

  // 辅助方法：构建图标按钮
  Widget buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    double width = 50,
    double size = 30,
  }) {
    final primaryColor = Theme.of(context).primaryColor;

    return RippleIcon(
      size: size,
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: width, // 使用相同的宽高比
        child: Center(
          child: Icon(icon, color: primaryColor, size: size),
        ),
      ),
    );
  }
}
