import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_service.dart";
import "package:bobomusic/utils/clear_html_tags.dart";
import "package:flutter/material.dart";

/// 自己的状态卡
class PartySelfCard extends StatelessWidget {
  final String nick;
  final String face;
  final bool inRoom;
  final bool connected;
  final String roomId;
  final bool isLogin;

  /// 是不是在别人的房间里当听众
  final bool isGuest;
  final VoidCallback onToggleOnline;
  final VoidCallback? onEditName;

  const PartySelfCard({
    super.key,
    required this.nick,
    required this.face,
    required this.inRoom,
    required this.connected,
    required this.roomId,
    required this.isLogin,
    required this.onToggleOnline,
    this.isGuest = false,
    this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (face.isNotEmpty)
                CircleAvatar(
                  radius: 21,
                  backgroundColor: const Color.fromARGB(255, 240, 240, 240),
                  backgroundImage: NetworkImage(face),
                )
              else
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.person_outline,
                    size: 21,
                    color: primaryColor,
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nick,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: inRoom && connected
                                ? Colors.green
                                : Colors.grey[350],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          inRoom
                              ? (connected
                                  ? (isGuest ? "正在跟房主一起听" : "正在分享你的收听")
                                  : "连接中…")
                              : "已下线",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 30,
                child: inRoom
                    ? OutlinedButton(
                        onPressed: onToggleOnline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 30),
                        ),
                        child: Text(
                          isGuest ? "退出" : "下线",
                          style: const TextStyle(fontSize: 11),
                        ),
                      )
                    : FilledButton(
                        onPressed: onToggleOnline,
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 30),
                        ),
                        child: const Text(
                          "上线",
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 248, 248, 248),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.tag, size: 14, color: primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    inRoom && roomId.isNotEmpty ? roomId : "未上线",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: inRoom ? primaryColor : Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  isGuest
                      ? "在别人的房间里"
                      : (isLogin ? "名单里的人才能进" : "登录后才能开房"),
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 名单里一个人的卡片
class PartyRosterTile extends StatelessWidget {
  final RosterMember member;
  final PartyProbe? probe;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback? onToggleControl;

  const PartyRosterTile({
    super.key,
    required this.member,
    required this.probe,
    required this.onTap,
    required this.onRemove,
    this.onToggleControl,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final listening = probe != null;

    // 只有点右边的叉才会移除，长按不再误删
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: listening
              ? Border.all(
                  color: primaryColor.withValues(alpha: 0.25),
                )
              : null,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Opacity(
                  opacity: listening ? 1 : 0.5,
                  child: CircleAvatar(
                    radius: 21,
                    backgroundColor: const Color.fromARGB(255, 240, 240, 240),
                    backgroundImage:
                        member.face.isNotEmpty ? NetworkImage(member.face) : null,
                    child: member.face.isEmpty
                        ? Icon(Icons.person, size: 20, color: Colors.grey[400])
                        : null,
                  ),
                ),
                if (listening)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.uname.isEmpty ? "未知用户" : member.uname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          listening ? FontWeight.bold : FontWeight.normal,
                      color: listening ? Colors.black87 : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (listening
                            ? "正在听《${clearHtmlTags(probe!.musicName)}》"
                            : "没在听歌") +
                        (member.canControl ? " · 共管" : ""),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: listening ? primaryColor : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: member.canControl
                  ? "取消共管（随时可以再点回来）"
                  : "设为共管：以后他一进房间就能换歌",
              onPressed: onToggleControl,
              icon: Icon(
                member.canControl
                    ? Icons.favorite
                    : Icons.favorite_border_rounded,
                size: 17,
                color: member.canControl ? Colors.redAccent : Colors.grey[350],
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            ),
            IconButton(
              tooltip: "从名单移除",
              onPressed: onRemove,
              icon: Icon(
                Icons.close,
                size: 16,
                color: Colors.grey[400],
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 房间成员 chip 列表
class PartyMemberChips extends StatelessWidget {
  final String myName;
  final String myFace;
  final bool inRoom;
  final Map<String, String> members;

  /// clientId -> UID，用来判断谁是共管
  final Map<String, int> memberUids;

  /// 有控制权的 UID
  final Set<int> controlUids;

  const PartyMemberChips({
    super.key,
    required this.myName,
    required this.myFace,
    required this.inRoom,
    required this.members,
    this.memberUids = const {},
    this.controlUids = const {},
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    if (members.isEmpty && !inRoom) {
      return const Text(
        "没人在房间里",
        style: TextStyle(fontSize: 11, color: Colors.grey),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        if (inRoom) _chip("$myName（我）", myFace, primaryColor, true, true),
        for (final entry in members.entries)
          _chip(
            entry.value,
            "",
            primaryColor,
            false,
            controlUids.contains(memberUids[entry.key] ?? 0),
          ),
      ],
    );
  }

  Widget _chip(
    String name,
    String face,
    Color primaryColor,
    bool highlight,
    bool canControl,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? primaryColor.withValues(alpha: 0.08)
            : const Color.fromARGB(255, 245, 245, 245),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: const Color.fromARGB(255, 235, 235, 235),
            backgroundImage: face.isNotEmpty ? NetworkImage(face) : null,
            child: face.isEmpty
                ? Icon(Icons.person, size: 10, color: Colors.grey[400])
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 11,
              color: highlight ? primaryColor : Colors.black87,
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (canControl) ...[
            const SizedBox(width: 4),
            const Icon(Icons.favorite, size: 10, color: Colors.redAccent),
          ],
        ],
      ),
    );
  }
}

/// 分区标题
class PartySectionTitle extends StatelessWidget {
  final String title;
  final String? trailingText;
  final Widget? action;

  const PartySectionTitle({
    super.key,
    required this.title,
    this.trailingText,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          if (trailingText != null) ...[
            const SizedBox(width: 6),
            Text(
              trailingText!,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}
