import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/player/utils.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:provider/provider.dart";

final db = DBOrder();

class LyricPreview extends StatefulWidget {
  final String lyric;
  const LyricPreview({super.key, required this.lyric});

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

  Widget _buildList(BuildContext context, PlayerModel player, double listHeight) {
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
              child: Text(
                parsedLyrics[index]['text'],
                style: const TextStyle(
                  color: Colors.black,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, PlayerModel player, double topHeight) {
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
              EasyLoading.show(maskType: EasyLoadingMaskType.black);

              try {
                if (player.current!.orderName.isNotEmpty) {
                  final musicItem = player.current!.copyWith(lyric: widget.lyric);
                  final id = await db.update(player.current!.orderName, musicItem2Row(music: musicItem));

                  if (id > -1) {
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      Navigator.of(context).pop();
                    }
                    player.current = musicItem;
                    EasyLoading.dismiss();
                    eventBus.fire(ScrollLyric());
                    BotToast.showText(text: "应用成功");
                  }
                }
              } catch(error) {
                EasyLoading.dismiss();
                print("$error");
              }
            },
            child: Text("应用歌词", style: TextStyle(color: Theme.of(context).primaryColor)),
          )
        ],
      ),
    );
  }
}
