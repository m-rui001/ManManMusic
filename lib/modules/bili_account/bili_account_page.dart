import "package:bobomusic/modules/bili_account/bili_fav_page.dart";
import "package:bobomusic/modules/bili_account/bili_login_page.dart";
import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:flutter/material.dart";

/// 哔哩哔哩账号页：登录态 + 收藏夹导入入口
class BiliAccountPage extends StatefulWidget {
  const BiliAccountPage({super.key});

  @override
  State<BiliAccountPage> createState() => _BiliAccountPageState();
}

class _BiliAccountPageState extends State<BiliAccountPage> {
  final BiliAuth _auth = BiliAuth.instance;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _auth.init();
    if (_auth.isLogin) {
      await _auth.refreshUserInfo();
    }
    if (!mounted) return;
    setState(() => _checking = false);
  }

  Future<void> _login() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const BiliLoginPage()),
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("哔哩哔哩账号", style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: _checking
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _auth.isLogin
                          ? _buildUserInfo(primaryColor)
                          : _buildLoginPrompt(primaryColor),
                    ),
                    const SizedBox(height: 14),
                    if (_auth.isLogin) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.playlist_add_check,
                            size: 20,
                            color: primaryColor,
                          ),
                          title: const Text(
                            "从收藏夹导入",
                            style: TextStyle(fontSize: 13),
                          ),
                          subtitle: const Text(
                            "把 B 站收藏夹里的视频并进「满满音乐」",
                            style: TextStyle(fontSize: 10),
                          ),
                          trailing: const Icon(Icons.chevron_right, size: 18),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const BiliFavPage(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await confirmBiliLogout(context);
                          if (context.mounted) setState(() {});
                        },
                        icon: const Icon(Icons.logout, size: 17),
                        label: const Text("退出登录"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          minimumSize: const Size.fromHeight(42),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildUserInfo(Color primaryColor) {
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFEEEEEE),
          backgroundImage:
              _auth.face.isNotEmpty ? NetworkImage(_auth.face) : null,
          child: _auth.face.isEmpty
              ? const Icon(Icons.person_outline, color: Colors.grey)
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _auth.uname.isEmpty ? "哔哩哔哩用户" : _auth.uname,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildTag("Lv${_auth.level}", primaryColor),
                  const SizedBox(width: 6),
                  _buildTag(
                    _auth.vipStatus == 1 ? "大会员" : "普通会员",
                    _auth.vipStatus == 1 ? const Color(0xFFCE7EAB) : Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, color: color)),
    );
  }

  Widget _buildLoginPrompt(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_circle_outlined, size: 20, color: primaryColor),
            const SizedBox(width: 8),
            const Text(
              "登录后可以",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          "· 播放大会员 / Hi-Res 高音质音频\n"
          "· 把 B 站收藏夹一键并进「满满音乐」\n"
          "· 一起听时按 UID 认出名单里的人",
          style: TextStyle(fontSize: 11, height: 1.9, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _login,
          icon: const Icon(Icons.qr_code_scanner, size: 18),
          label: const Text("扫码登录哔哩哔哩"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFB7299),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ],
    );
  }
}

/// 退出登录确认
Future<void> confirmBiliLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("退出登录", style: TextStyle(fontSize: 14)),
      content: const Text(
        "退出后音质会回到最低档，收藏夹导入也会不可用。本机保存的登录凭证会被清除。",
        style: TextStyle(fontSize: 12, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text("取消"),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text("退出"),
        ),
      ],
    ),
  );

  if (ok == true) {
    await BiliAuth.instance.logout();
  }
}
