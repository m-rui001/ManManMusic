import "dart:io";

import "package:bobomusic/constants/app_info.dart";
import "package:flutter/material.dart";
import "package:window_manager/window_manager.dart";

initWindowManage() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(460, 900),
    minimumSize: Size(400, 700),
    center: true,
    title: appName,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.setMaximizable(false);
  if (Platform.isWindows) {
    windowManager.setIcon(appLogoAsset);
  }
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
