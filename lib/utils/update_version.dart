import "package:bobomusic/constants/app_info.dart";
import "package:bot_toast/bot_toast.dart";
import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:url_launcher/url_launcher.dart";

/// 检查更新
///
/// 只查询 [appRepoOwner]/[appRepoName] 自己的 release，
/// 不会去查上游（啵啵音乐）的版本。
Future<void> updateAppVersion(BuildContext context, {bool? showToast = true}) async {
  try {
    final checker = ReleaseChecker(
      owner: appRepoOwner,
      repo: appRepoName,
    );

    EasyLoading.show(maskType: EasyLoadingMaskType.black);
    final info = await checker.check();
    EasyLoading.dismiss();

    if (info == null) {
      if (showToast!) BotToast.showText(text: "网络请求失败，检查网络后重试");
      return;
    }

    if (!info.hasUpdate) {
      if (showToast!) BotToast.showText(text: "已经是最新版本（v$appVersion）");
      return;
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _UpdateDialog(info: info, current: appVersion),
    );
  } catch (e) {
    EasyLoading.dismiss();
    BotToast.showText(text: "更新检查出错了 QAQ，稍后再试");
  }
}

/// 发现新版本时的弹窗
class _UpdateDialog extends StatelessWidget {
  final ReleaseInfo info;
  final String current;

  const _UpdateDialog({required this.info, required this.current});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.new_releases_outlined, size: 18, color: primaryColor),
                const SizedBox(width: 6),
                Text(
                  "发现新版本 v${info.latestVersion}",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "当前版本 v$current",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            if (info.body.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 247, 247, 247),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Text(
                      info.body,
                      style: const TextStyle(fontSize: 11, height: 1.5),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              "下载后直接覆盖安装，歌单和登录状态都会保留",
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("以后再说", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final url = info.apkUrl.isNotEmpty ? info.apkUrl : info.pageUrl;
                    if (url.isEmpty) {
                      BotToast.showText(text: "这个版本没有可下载的安装包");
                      return;
                    }
                    await launchUrl(
                      Uri.parse(url),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Text(
                    info.apkUrl.isNotEmpty ? "下载安装包" : "打开下载页",
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 版本信息
class ReleaseInfo {
  final String latestVersion;
  final String body;

  /// 直接下载 APK 的地址（优先）
  final String apkUrl;

  /// release 页面地址（兜底）
  final String pageUrl;

  final bool hasUpdate;

  const ReleaseInfo({
    required this.latestVersion,
    required this.body,
    required this.apkUrl,
    required this.pageUrl,
    required this.hasUpdate,
  });
}

class ReleaseChecker {
  final String owner;
  final String repo;

  ReleaseChecker({required this.owner, required this.repo});

  String get _base => "https://api.github.com/repos/$owner/$repo";

  Dio _dio() {
    return Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          "Accept": "application/vnd.github+json",
          if (appRepoToken.isNotEmpty) "Authorization": "Bearer $appRepoToken",
        },
        validateStatus: (_) => true,
      ),
    );
  }

  /// 查询最新 release
  ///
  /// 优先用 releases/latest；仓库没有正式 release 时，
  /// 退回到 Actions 产物说明，提示用户去 Actions 页面下载。
  Future<ReleaseInfo?> check() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final resp = await _dio().get("$_base/releases/latest");

    if (resp.statusCode == 200 && resp.data is Map) {
      final data = Map<String, dynamic>.from(resp.data as Map);
      final tag = "${data["tag_name"] ?? ""}";
      if (tag.isEmpty) return null;

      final assets = data["assets"];
      String apkUrl = "";
      if (assets is List) {
        for (final a in assets) {
          if (a is! Map) continue;
          final name = "${a["name"] ?? ""}";
          if (name.toLowerCase().endsWith(".apk")) {
            apkUrl = "${a["browser_download_url"] ?? ""}";
            if (apkUrl.isNotEmpty) break;
          }
        }
      }

      return ReleaseInfo(
        latestVersion: tag.replaceAll("v", ""),
        body: "${data["body"] ?? ""}",
        apkUrl: apkUrl,
        pageUrl: "${data["html_url"] ?? "https://github.com/$owner/$repo/releases"}",
        hasUpdate: _compareVersions(tag, currentVersion),
      );
    }

    // 404：还没发过 release
    if (resp.statusCode == 404) {
      return ReleaseInfo(
        latestVersion: currentVersion,
        body: "",
        apkUrl: "",
        pageUrl: "https://github.com/$owner/$repo/actions",
        hasUpdate: false,
      );
    }

    return null;
  }

  /// latest > current 时返回 true
  bool _compareVersions(String latest, String current) {
    final latestParts = latest.replaceAll("v", "").split(".");
    final currentParts = current.split(".");

    for (int i = 0; i < 3; i++) {
      final latestPart =
          i < latestParts.length ? (int.tryParse(latestParts[i]) ?? 0) : 0;
      final currentPart =
          i < currentParts.length ? (int.tryParse(currentParts[i]) ?? 0) : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }

    return false;
  }
}
