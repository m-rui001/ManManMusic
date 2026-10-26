

import "package:bobomusic/components/custom_dialog/custom_dialog.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:flutter/material.dart";

Future checkMusicLocalRepeat(BuildContext context, MusicItem target, VoidCallback callback) async {
  final db = DBOrder();
  final dbMusics = await db.queryAll(TableName.musicLocal);
  MusicItem? repeatMusic;

  for (var dbm in dbMusics) {
    final musicName = (dbm["name"] as String);
    if ((musicName.contains(target.name) || target.name.contains(musicName))) {
      repeatMusic = row2MusicItem(dbRow: dbm);
    }
  }

  if (repeatMusic != null && context.mounted) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return CustomDialog(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("已存在下面相似歌曲，确认下载吗？"),
              const SizedBox(height: 10),
              Text("歌曲：${repeatMusic!.name}"),
              Text("歌手：${repeatMusic.author}"),
            ],
          ),
          onConfirm: () async {
            callback();

            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        );
      },
    );
  } else {
    callback();
  }
}
