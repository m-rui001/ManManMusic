import "dart:io";

import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/modules/download/types.dart";
import "package:bobomusic/modules/player/source.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bot_toast/bot_toast.dart";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:permission_handler/permission_handler.dart";

final dio = Dio();

class DownloadModel extends ChangeNotifier {
  // 列表
  final List<DownloadItem> list = [];
  // 并行数量
  int parallelCount = 3;

  // 添加下载任务
  void addDownloadTask(DownloadItem item) {
    list.add(item);
    notifyListeners();
  }

  // 下载
  void download(List<MusicItem> musics) async {
    for (final item in musics) {
      try {
        final resultPath = await _downloadMusic(item);
        BotToast.showText(text: "下载完成: $resultPath");
        eventBus.fire(ScanLocalListWithoutLoading());
      } catch (_) {
        BotToast.showText(text: "下载失败");
      }
    }
  }
}

Future<Directory?> getDownloadDir() async {
  if (Platform.isAndroid) {
    return Directory("/storage/emulated/0/Download/满满音乐");
  }
  return getDownloadsDirectory();
}

Future<String> _downloadMusic(MusicItem music) async {
  if (Platform.isAndroid &&
      !await Permission.manageExternalStorage.status.isGranted &&
      !await Permission.manageExternalStorage.request().isGranted) {
    throw StateError("未授权");
  }
  final directory = await getDownloadDir();
  if (directory == null) throw StateError("找不到下载目录");
  await directory.create(recursive: true);

  final extension =
      music.localPath.isEmpty ? ".m4a" : path.extension(music.localPath);
  final destination = path.join(directory.path, "${music.name}$extension");
  final temporary = await directory.createTemp(".manman-download-");
  final partial = File(path.join(temporary.path, "audio.part"));
  try {
    await for (final source in musicAudioCandidates(music)) {
      final file = source.file;
      final remote = source.remote;
      try {
        if (file != null) {
          await file.copy(partial.path);
        } else {
          await dio.download(
            remote!.url,
            partial.path,
            options: Options(headers: remote.headers),
          );
        }
      } on DioException {
        continue;
      } on FileSystemException {
        if (file != null && !await file.exists()) continue;
        rethrow;
      }
      await partial.rename(destination);
      return destination;
    }
    throw StateError("找不到可下载的音轨");
  } finally {
    if (await partial.exists()) await partial.delete();
    await temporary.delete();
  }
}
