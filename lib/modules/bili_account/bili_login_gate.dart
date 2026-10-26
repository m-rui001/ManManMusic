import "dart:async";

import "package:bobomusic/modules/bili_account/bili_login_page.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// 哔哩哔哩登录引导
///
/// 设计取向：
/// - 不登录 B 站也能用 App，但音质只能拿到最低档；
/// - 登录后即可拿到更高音质（大会员另说），不需要任何额外付费；
/// - 所以登录价值很大，但绝不强迫 —— 首次进首页弹一次，用户拒绝就不再打扰。
class BiliLoginGate {
  BiliLoginGate._();

  static const String _kAsked = "bili_login_asked";
  static const String _kSkipped = "bili_login_skipped";

  static final BiliAuth auth = BiliAuth.instance;

  /// 已经登录
  static bool get isLoggedIn => auth.isLogin;

  /// 首次进入首页时调用：未登录且没问过，就弹一次引导
  static Future<void> maybePromptOnStartup(BuildContext context) async {
    if (isLoggedIn) return;

    final storage = await SharedPreferences.getInstance();
    if (storage.getBool(_kAsked) == true) return;
    final skipped = storage.getBool(_kSkipped) == true;
    if (skipped) return;

    await storage.setBool(_kAsked, true);
    if (!context.mounted) return;

    await showPrompSheet(context);
  }

  /// 主动弹一次登录引导（比如点「提高音质」时）
  static Future<bool> showPrompSheet(BuildContext context) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LoginPromptSheet(),
    );
    return ok == true;
  }

  /// 打开扫码登录页，返回是否登录成功
  static Future<bool> openLoginPage(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BiliLoginPage()),
    );
    return ok == true;
  }

  /// 要求已登录：没有就引导，成功返回 true
  static Future<bool> ensureLoggedIn(BuildContext context) async {
    if (isLoggedIn) return true;
    final go = await showPrompSheet(context);
    if (!go) return false;
    if (!context.mounted) return false;
    return openLoginPage(context);
  }

  /// 退出登录
  static Future<void> logout() async {
    await auth.logout();
  }

  /// 用户选择「以后再说」
  static Future<void> markSkipped() async {
    final storage = await SharedPreferences.getInstance();
    await storage.setBool(_kSkipped, true);
  }
}

/// 登录引导面板
class _LoginPromptSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    final benefits = [
      (Icons.high_quality_outlined, "解锁高音质", "登录后可用 Hi-Res / 无损音源"),
      (Icons.folder_special_outlined, "导入收藏夹", "把 B 站收藏夹一键搬过来"),
      (Icons.people_outline, "找到好友", "一起听里能看到互关好友在听什么"),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 22,
        bottom: 24 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note, color: primaryColor, size: 22),
              const SizedBox(width: 8),
              const Text(
                "登录哔哩哔哩，音质更好",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "不登录也能听，只是只能拿到最低音质",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 18),
          ...benefits.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(b.$1, size: 18, color: primaryColor),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.$2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        b.$3,
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("现在登录", style: TextStyle(fontSize: 14)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                BiliLoginGate.markSkipped();
                Navigator.of(context).pop(false);
              },
              child: const Text(
                "先随便听听",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
