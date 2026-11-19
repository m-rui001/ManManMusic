import "package:bobomusic/modules/player/utils.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:provider/provider.dart";

import "package:bobomusic/origin_sdk/origin_types.dart";

class LyricPreview extends StatefulWidget {
  final String lyric;
  final MusicItem track;
  const LyricPreview({super.key, required this.lyric, required this.track});

  @override
  LyricPreviewState createState() => LyricPreviewState();
}

class LyricPreviewState extends State<LyricPreview> {
  @override
  Widget build(BuildContext context) {
    double height = MediaQuery.of(context).size.height / 2;
    double topHeight = 56;
    return Consumer<PlayerModel>(
      builder: (context, player, child) {
        return SizedBox(
          height: height,
          width: MediaQuery.of(context).size.width,
          child: Flex(
            direction: Axis.vertical,
            children: [
              _buildTopBar(context, player, topHeight),
              _buildList(context, player, height - topHeight)
            ],
          ),
        );
      },
    );
  }

  Widget _buildList(
      BuildContext context, PlayerModel player, double listHeight) {
    List<Map<String, dynamic>> parsedLyrics = parseLyrics(widget.lyric);
    return Expanded(
      child: Container(
        height: listHeight,
        padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
        child: ListView.builder(
          itemCount: parsedLyrics.length,
          itemBuilder: (context, index) {
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              child: Text(parsedLyrics[index]['text']),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(
      BuildContext context, PlayerModel player, double topHeight) {
    return Container(
      height: topHeight,
      padding: const EdgeInsets.only(
        left: 15,
        right: 15,
        top: 5,
        bottom: 5,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Row(
              children: [
                Text(
                  "歌词预览",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                final applied =
                    await player.setLyrics(widget.track, widget.lyric);
                if (!context.mounted) return;
                if (!applied) {
                  BotToast.showText(text: "歌曲已切换，请重新匹配");
                  return;
                }
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.pop();
                BotToast.showText(text: "歌词已应用");
              } catch (_) {
                if (context.mounted) BotToast.showText(text: "歌词应用失败");
              }
            },
            child: Text("应用歌词",
                style: TextStyle(color: Theme.of(context).primaryColor)),
          )
        ],
      ),
    );
  }
}
