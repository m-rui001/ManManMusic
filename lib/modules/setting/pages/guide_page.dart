import "package:flutter/material.dart";

/// 使用说明
///
/// 纯静态页面，把「怎么用」讲清楚，省得每个功能都靠猜。
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("使用说明", style: TextStyle(fontSize: 17)),
      ),
      body: SafeArea(
        bottom: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _Section(
              icon: Icons.search_rounded,
              title: "找歌听歌",
              color: primaryColor,
              lines: const [
                "顶部搜索框搜歌名或 UP 主，点结果直接播放。",
                "播放页可以拖进度、看歌词；通知栏和锁屏也能控制。",
                "登录 B 站账号后会自动用更高音质，不登录只能听最低档。",
              ],
            ),
            _Section(
              icon: Icons.favorite,
              title: "我的歌单",
              color: primaryColor,
              lines: const [
                "全 App 只有一张歌单「满满音乐」，点红心就进去，再点一次取消。",
                "长按或者点右边的菜单可以移除、加进待播放列表、下载。",
                "首页「我的歌单」里能看到全部内容，不需要先选歌单。",
              ],
            ),
            _Section(
              icon: Icons.playlist_add_check,
              title: "从 B 站收藏夹导入",
              color: primaryColor,
              lines: const [
                "入口只有一处：我的歌单 → 右上「同步 B 站」。",
                "导入 = 把收藏夹里「满满音乐还没有」的视频补进去，只增不删。",
                "不会自动同步。想拉新内容时自己点一次「同步」，B 站那边的收藏夹原样不动。",
              ],
            ),
            _Section(
              icon: Icons.headphones,
              title: "一起听",
              color: primaryColor,
              lines: const [
                "房间号就是你的 B 站 UID，朋友不用问你房间号。",
                "只有「一起听名单」里的人能进你的房间；名单在设置里维护。",
                "名单里点红心 = 永久共管：他一进房间就能和你一起换歌、拖进度。",
                "没点红心的人只能听。想自己点歌，先退出房间。",
                "有人进出会有一声很轻的提示音，可以在设置里关掉。",
              ],
            ),
            _Section(
              icon: Icons.online_prediction_outlined,
              title: "好友上线提醒",
              color: primaryColor,
              lines: const [
                "设置里打开后，名单里的好友开始听歌时会提醒你。",
                "App 在前台时一分钟探一次；切到后台改由系统低频唤醒，所以后台提醒会慢一些，换来的是几乎不耗电。",
              ],
            ),
            _Section(
              icon: Icons.lock_outline,
              title: "数据与隐私",
              color: primaryColor,
              lines: const [
                "登录凭证、歌单、历史、一起听名单全部只存在本机。",
                "一起听只把歌名、封面、进度、昵称发到公共中继，消息默认 12 小时后清空。",
                "对 B 站只读：不点赞、不投币、不改你的收藏夹。",
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;
  final Color color;

  const _Section({
    required this.icon,
    required this.title,
    required this.lines,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 7),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.7,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
