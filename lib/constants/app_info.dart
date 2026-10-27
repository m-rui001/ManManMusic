import "package:package_info_plus/package_info_plus.dart";

/// 应用显示名称（各处统一引用，改名只需改这里）
const String appName = "满满音乐";

/// 应用副标题 / slogan
const String appSlogan = "听歌自由";

/// GitHub 仓库信息（检查更新用）
/// 指向自己的分支，避免总是提示原项目（啵啵音乐）的新版本
const String appRepoOwner = "m-rui001";
const String appRepoName = "ManManMusic";

/// 私有仓库需要带 token 才能绕过 API 限流/鉴权；公开仓库留空即可
const String appRepoToken = "";

/// 版本号。启动时由 [loadAppInfo] 从包信息读取，读取失败则保留兜底值。
String appVersion = "2.9.1";

/// 应用内展示的 logo（由 tools/gen_icons.py 从 logo.jpg 生成）
const String appLogoAsset = "assets/logo.png";

/// 启动时调用，读取真实版本号
Future<void> loadAppInfo() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) {
      appVersion = info.version;
    }
  } catch (_) {
    // 读取失败时用兜底版本号，不影响功能
  }
}
