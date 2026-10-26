import "package:bobomusic/modules/party/party_service.dart";
import "package:bot_toast/bot_toast.dart";

/// 一起听的播放控制锁
///
/// 听众（没被点红心的人）在房间里只能听：换歌、暂停、拖进度都会被拦下来，
/// 想自己操作必须先退出房间。
class PartyControl {
  PartyControl._();

  /// 现在是不是被锁住了
  static bool get locked => PartyService.instance.isLocked;

  /// 被锁住时提示一句并返回 true（调用方直接 return 即可）
  static bool blocked() {
    if (!locked) return false;
    BotToast.showText(
      text: "房主在控制播放，想自己点歌请先退出一起听",
      duration: const Duration(seconds: 3),
    );
    return true;
  }
}
