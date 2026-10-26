import "package:bobomusic/components/custom_dialog/custom_dialog.dart";
import "package:bobomusic/constants/app_info.dart";
import "package:bot_toast/bot_toast.dart";
import "package:dio/dio.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_easyloading/flutter_easyloading.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:url_launcher/url_launcher.dart";

// 检查更新版本
updateAppVersion(BuildContext context, {bool? showToast = true}) async {
  try {
    final checker = ReleaseChecker(
      owner: appRepoOwner,
      repo: appRepoName,
    );

    EasyLoading.show(maskType: EasyLoadingMaskType.black);

    final isUpdateAvailable = await checker.isUpdateAvailable();

    EasyLoading.dismiss();

    if (!isUpdateAvailable && showToast!) {
      BotToast.showText(text: "已经是最新版本");
      return;
    }

    if (isUpdateAvailable) {
      if (context.mounted) {
         showDialog(
          context: context,
          builder: (BuildContext context) {
            return CustomDialog(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      text: "检查到新版本 ",
                      style: const TextStyle(color: Colors.black, fontSize: 12),
                      children: [
                        TextSpan(
                          text: "${checker.latestVersion}",
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12
                          ),
                        ),
                        const TextSpan(
                          text: "，是否立即更新？",
                          style: TextStyle(color: Colors.black, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text("备注：请下载 app-release.apk", style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      text: "无法访问？请点击这里下载：",
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      children: [
                        TextSpan(
                          text: appName,
                          style: const TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: () {
                            final gesture = TapGestureRecognizer()
                              ..onTap = () {
                                // 处理点击事件
                                launchUrl(
                                  Uri.parse(
                                    "https://pan.baidu.com/s/1S0mF6PhN4aXM4VVFPc7PAQ",
                                  ),
                                );
                              };
                            return gesture;
                          }(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              onConfirm: () async {
                launchUrl(
                  Uri.parse(
                    "https://github.com/Redstone-1/bobomusic/releases/latest",
                  ),
                );
              },
              onCancel: () {
                Navigator.of(context).pop();
              },
            );
          },
        );
      }
    }
  } catch (e) {
    BotToast.showText(text: "更新出错了 QAQ，不好意思 ~");
  }
}

class ReleaseChecker {
  final String owner;
  final String repo;
  String? _latestVersion;
  String? get latestVersion => _latestVersion;

  ReleaseChecker({
    required this.owner,
    required this.repo,
  });

  Future<String?> getLatestReleaseVersion() async {
    try {
      final dio = Dio();

      final response = await dio.get(
        "https://api.github.com/repos/$owner/$repo/releases/latest",
      );

      if (response.statusCode == 200) {
        final data = response.data;
        _latestVersion = data["tag_name"];
        return _latestVersion;
      } else {
        BotToast.showText(text: "网络请求错误，检查网络连接或稍后再试");
      }
    } catch (e) {
      BotToast.showText(text: "网络请求错误，检查网络连接或稍后再试");
    }
    return null;
  }

  Future<bool> isUpdateAvailable() async {
    final latestVersion = await getLatestReleaseVersion();
    if (latestVersion == null) return false;

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    return _compareVersions(latestVersion, currentVersion);
  }

  bool _compareVersions(String latest, String current) {
    final latestParts = latest.replaceAll("v", "").split(".");
    final currentParts = current.split(".");

    for (int i = 0; i < 3; i++) {
      final latestPart = int.tryParse(latestParts[i]) ?? 0;
      final currentPart = int.tryParse(currentParts[i]) ?? 0;

      if (latestPart > currentPart) {
        return true;
      } else if (latestPart < currentPart) {
        return false;
      }
    }

    return false;
  }
}
