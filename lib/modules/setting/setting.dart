import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/icons/icons_svg.dart";
import "package:bobomusic/modules/setting/components/setting_card.dart";
import "package:bobomusic/modules/bili_account/bili_account_page.dart";
import "package:bobomusic/modules/party/party_pick_page.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/party/party_roster.dart";
import "package:bobomusic/modules/party/party_tone.dart";
import "package:bobomusic/modules/setting/pages/guide_page.dart";
import "package:bobomusic/modules/setting/pages/theme_color_setting.dart";
import "package:bobomusic/modules/setting/playback_prefs.dart";
import "package:bobomusic/utils/get_cache_color.dart";
import "package:bobomusic/utils/update_version.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/svg.dart";
import "package:shared_preferences/shared_preferences.dart";

final db = DBOrder();

class SettingView extends StatefulWidget {
  const SettingView({super.key});

  @override
  State<SettingView> createState() => SettingViewState();
}

class SettingViewState extends State<SettingView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _autoOnline = true;
  int _rosterCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshRoster();
    PartyRoster.isAutoOnline().then((v) {
      if (mounted) setState(() => _autoOnline = v);
    });
  }

  Future<void> _refreshRoster() async {
    await PartyRoster.instance.init();
    if (!mounted) return;
    setState(() => _rosterCount = PartyRoster.instance.length);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    final primaryColor = colors.primary;

    return Scaffold(
      body: SafeArea(
        bottom: true,
        child: Container(
          padding: const EdgeInsets.only(top: 10, left: 20, right: 20),
          height: MediaQuery.of(context).size.height,
          child: SingleChildScrollView(
            child: Column(
              children: [
                SettingCard(
                  settingItems: [
                    SettingItem(
                      customTitle: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const CircleAvatar(
                            radius: 12,
                            backgroundImage: AssetImage(appLogoAsset),
                          ),
                          Text(
                            appName,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            appSlogan,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  sectionTitle: "外观",
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.color_lens,
                      title: "更换主题色",
                      subtitle: "整个界面的强调色跟着它走",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () async {
                        Color initialColor = await getCacheColor();

                        if (context.mounted) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (BuildContext context) {
                                return ThemeColorSetting(
                                  initialColor: initialColor,
                                  onColorChanged: (color, colorName, callback) async {
                                    eventBus.fire(ThemeColorChanged(color));
                                    final localStorage = await SharedPreferences.getInstance();
                                    // ignore: deprecated_member_use
                                    localStorage.setString(CacheKey.themeColor, colorName);
                                    callback();
                                  }
                                );
                              },
                            ),
                          );
                        }
                      }
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  sectionTitle: "播放",
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.replay_rounded,
                      title: "「上一首」先回到开头",
                      subtitle: "播放超过 3 秒时先重听本曲，连按两次才切歌",
                      trailing: Switch(
                        value: PlaybackPrefs.instance.restartOnPrevious,
                        onChanged: (v) async {
                          await PlaybackPrefs.instance.setRestartOnPrevious(v);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    SettingItem(
                      leadingIcon: Icons.lyrics_outlined,
                      title: "自动匹配歌词",
                      subtitle: "打开歌词时先按曲名和时长静默找一次",
                      trailing: Switch(
                        value: PlaybackPrefs.instance.autoLyrics,
                        onChanged: (v) async {
                          await PlaybackPrefs.instance.setAutoLyrics(v);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    SettingItem(
                      leadingIcon: Icons.blur_on_rounded,
                      title: "播放页流动背景",
                      subtitle: "封面色块缓慢旋转，关掉更省电",
                      trailing: Switch(
                        value: PlaybackPrefs.instance.fluidBackground,
                        onChanged: (v) async {
                          await PlaybackPrefs.instance.setFluidBackground(v);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    SettingItem(
                      leadingIcon: Icons.vibration_rounded,
                      title: "触感反馈",
                      subtitle: "播放、收藏、切模式时轻微震动",
                      trailing: Switch(
                        value: PlaybackPrefs.instance.haptics,
                        onChanged: (v) async {
                          await PlaybackPrefs.instance.setHaptics(v);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  sectionTitle: "账号",
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.account_circle_outlined,
                      title: "哔哩哔哩账号",
                      subtitle: "登录后才能取到无损和杜比音轨",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return const BiliAccountPage();
                            },
                          ),
                        );
                        if (context.mounted) setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  sectionTitle: "一起听",
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.headphones_outlined,
                      title: "打开 App 自动上线一起听",
                      subtitle: "关掉后只能手动上线",
                      // 默认开启，关掉后只能手动上线
                      trailing: Switch(
                        value: _autoOnline,
                        onChanged: (v) async {
                          await PartyRoster.setAutoOnline(v);
                          if (mounted) setState(() => _autoOnline = v);
                        },
                      ),
                    ),
                    SettingItem(
                      leadingIcon: Icons.notifications_active_outlined,
                      title: "有人进出时播放提示音",
                      subtitle: "只在 App 打开时响",
                      trailing: Switch(
                        value: PartyTone.instance.enabled,
                        onChanged: (v) async {
                          await PartyTone.instance.setEnabled(v);
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    SettingItem(
                      leadingIcon: Icons.group_outlined,
                      title: "一起听名单",
                      subtitle: "只有名单里的人能进房间",
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "$_rosterCount 人",
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          Icon(Icons.chevron_right, color: primaryColor),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PartyPickPage(),
                          ),
                        );
                        await _refreshRoster();
                        // 名单改了要立刻生效：新加的人能进，移出的人被请出去
                        PartySession.instance.refreshPermissions();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  sectionTitle: "关于",
                  settingItems: [
                    SettingItem(
                      customLeadingIcon: Container(
                        padding: const EdgeInsets.only(left: 2),
                        child: SvgPicture.string(
                          IconsSVG.update,
                          // ignore: deprecated_member_use
                          color: primaryColor,
                          width: 21,
                          height: 21,
                        ),
                      ),
                      title: "检查更新",
                      subtitle: "新版本发布后这里会提示",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        updateAppVersion(context);
                      }
                    ),
                    SettingItem(
                      leadingIcon: Icons.menu_book_outlined,
                      title: "使用说明",
                      subtitle: "搜歌、收藏、一起听怎么用",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const GuidePage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 8,
                      backgroundImage: AssetImage(appLogoAsset),
                    ),
                    const SizedBox(width: 6),
                    Text("$appName v$appVersion", style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ],
            ),
          )
        )
      )
    );
  }
}
