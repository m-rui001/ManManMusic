import "dart:io";
import "dart:ui";

import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:workmanager/workmanager.dart";

/// 后台好友上线检查
///
/// 没有自建服务器、也没有推送通道，所以只能用系统给的最低成本方案：
/// WorkManager 每隔 15 分钟（Android 允许的最短周期）醒一次，
/// 探一下名单里的好友，有新的就开始提醒。
///
/// 代价是后台提醒会滞后，换来的是几乎不耗电、不需要常驻前台服务。
class PartyBackground {
  PartyBackground._();

  static const String taskName = "manman_party_friend_watch";
  static const String _kEnabled = "manman_party_watch_friends";
  static const String _kLastOnline = "manman_party_watch_last";
  static const String _kBaseline = "manman_party_watch_baseline";

  static const int _maxProbe = 8;

  static bool _inited = false;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_inited) return;
    _inited = true;
    try {
      await Workmanager().initialize(partyBackgroundDispatcher);
    } catch (_) {
      // 初始化失败不影响前台功能
    }
  }

  static Future<void> enable() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().registerPeriodicTask(
        taskName,
        taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {}
  }

  static Future<void> disable() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await Workmanager().cancelByUniqueName(taskName);
    } catch (_) {}
  }

  /// 跑一次检查：有新的好友上线就发系统通知
  static Future<void> checkOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_kEnabled) ?? false)) return;

    await PartyRoster.instance.init();
    final members = PartyRoster.instance.members.take(_maxProbe).toList();
    if (members.isEmpty) return;

    final online = <int>{};
    for (final m in members) {
      try {
        final probe = await PartyService.instance.probeRoom(m.roomId);
        if (probe != null && probe.isFresh) online.add(m.mid);
      } catch (_) {
        // 单个失败不影响其他人
      }
    }

    final last = (prefs.getStringList(_kLastOnline) ?? const [])
        .map((e) => int.tryParse(e) ?? 0)
        .where((e) => e > 0)
        .toSet();

    // 第一次跑只建立基线，不提醒
    if (!(prefs.getBool(_kBaseline) ?? false)) {
      await prefs.setBool(_kBaseline, true);
      await prefs.setStringList(
        _kLastOnline,
        online.map((e) => "$e").toList(),
      );
      return;
    }

    final fresh = online.difference(last);
    await prefs.setStringList(
      _kLastOnline,
      online.map((e) => "$e").toList(),
    );

    if (fresh.isEmpty) return;

    final names = members
        .where((m) => fresh.contains(m.mid))
        .map((m) => m.uname.isEmpty ? "好友" : m.uname)
        .toList();

    await _notify(names);
  }

  static Future<void> _notify(List<String> names) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings("@mipmap/ic_launcher"),
        ),
      );

      final title = names.length == 1
          ? "${names.first} 开始听歌了"
          : "${names.length} 位好友开始听歌";

      await plugin.show(
        1001,
        title,
        "点开满满音乐，进「一起听」就能加进去",
        const NotificationDetails(
          android: AndroidNotificationDetails(
            "party_friend_online",
            "好友上线提醒",
            channelDescription: "名单里的好友开始听歌时提醒你",
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    } catch (_) {}
  }
}

/// WorkManager 的回调入口，必须顶层 + vm:entry-point
@pragma("vm:entry-point")
void partyBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 后台 isolate 里插件不会自动注册，要手动来一下
    DartPluginRegistrant.ensureInitialized();
    try {
      await PartyBackground.checkOnce();
    } catch (_) {}
    return true;
  });
}
