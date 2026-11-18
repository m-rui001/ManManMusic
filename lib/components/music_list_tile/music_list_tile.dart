import "package:bobomusic/components/ripple_icon/ripple_icon.dart";
import "package:bobomusic/components/text_tags/tags.dart";
import "package:bobomusic/modules/player/model.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";
import "package:provider/provider.dart";

class MusicListTile extends StatefulWidget {
  final MusicItem music;
  final void Function() onMore;
  final VoidCallback? onPlay;
  final bool showAddIcon;
  final bool showOrderName;
  final bool showOrgin;

  const MusicListTile(
    this.music,
    {
      super.key,
      required this.onMore,
      this.onPlay,
      this.showAddIcon = true,
      this.showOrderName = false,
      this.showOrgin = true
    }
  );

   @override
  MusicListTitleState createState() => MusicListTitleState();
}

class MusicListTitleState extends State<MusicListTile> with SingleTickerProviderStateMixin {
  bool isPlaying = false;

  Color color = const Color.fromARGB(255, 37, 37, 37);

  @override
  Widget build(BuildContext context) {
    final List<String> tags = [];

    if (widget.showOrgin) {
      tags.add(widget.music.origin.name);
    }

    if (widget.music.author.isNotEmpty) {
      tags.add(widget.music.author);
    }

    if (widget.showOrderName) {
      tags.add(widget.music.orderName);
    }

    tags.add(seconds2duration(widget.music.duration));

    return Consumer<PlayerModel>(builder: (context, player, child) {
      if (player.current != null) {
        if (player.current!.playId.isNotEmpty && player.current!.orderName.isNotEmpty) {
          isPlaying = player.current!.playId == widget.music.playId && player.current!.orderName == widget.music.orderName;
        } else if (player.current!.orderName.isEmpty && widget.music.orderName.isEmpty) {
          isPlaying = player.current!.id == widget.music.id;
        } else {
          isPlaying = false;
        }
      }

      final mainColor = isPlaying ? Theme.of(context).primaryColor : color;

      final playingIcon = isPlaying
        ? Icon(
            player.isPlaying ? Icons.pause : Icons.play_arrow,
            size: 18,
            color: Theme.of(context).primaryColor,
          )
        : const Text("");
      return ListTile(
        title: Row(
          children: [
            Flexible(
              child: Text(
                maxLines: 1,
                widget.music.name,
                style: TextStyle(
                  overflow: TextOverflow.ellipsis,
                  color: mainColor,
                  fontSize: 14
                ),
              ),
            ),
            const SizedBox(width: 10),
            playingIcon
          ],
        ),
        leading: widget.showAddIcon ? RippleIcon(
          size: 20,
          onTap: () {
            Provider.of<PlayerModel>(context, listen: false).addPlayerList([widget.music], showToast: true);
          },
          child: Icon(Icons.add_circle, size: 20, color: mainColor),
        ) : null,
        subtitle: TextTags(tags: tags, textStyle: TextStyle(fontSize: 8, color: mainColor)),
        trailing: InkWell(
          borderRadius: BorderRadius.circular(4.0),
          onTap: widget.onMore,
          child: Icon(Icons.more_vert, color: mainColor, size: 22),
        ),
        onTap: widget.onPlay ?? () {
          Provider.of<PlayerModel>(context, listen: false).play(music: widget.music);
        },
        onLongPress: widget.onMore,
      );
    });
  }
}
