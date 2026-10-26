import "package:bobomusic/constants/app_info.dart";
import "package:bobomusic/constants/cache_key.dart";
import "package:bobomusic/db/db.dart";
import "package:bobomusic/event_bus/event_bus.dart";
import "package:bobomusic/icons/icons_svg.dart";
import "package:bobomusic/modules/setting/components/setting_card.dart";
import "package:bobomusic/modules/setting/pages/help_doc.dart";
import "package:bobomusic/modules/setting/pages/limit.dart";
import "package:bobomusic/modules/setting/pages/support_me.dart";
import "package:bobomusic/modules/setting/pages/thanks.dart";
import "package:bobomusic/modules/bili_account/bili_account_page.dart";
import "package:bobomusic/modules/party/party_page.dart";
import "package:bobomusic/modules/setting/pages/theme_color_setting.dart";
import "package:bobomusic/modules/share/share_handler.dart";
import "package:bobomusic/utils/get_cache_color.dart";
import "package:bobomusic/utils/update_version.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/svg.dart";
import "package:shared_preferences/shared_preferences.dart";

final db = DBOrder(version: 2);

class SettingView extends StatefulWidget {
  const SettingView({super.key});

  @override
  State<SettingView> createState() => SettingViewState();
}

class SettingViewState extends State<SettingView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      body: SafeArea(
        bottom: true,
        child: Container(
          color: const Color.fromARGB(255, 245, 245, 245),
          padding: const EdgeInsets.only(top: 10, left: 20, right: 20),
          height: MediaQuery.of(context).size.height,
          child: SingleChildScrollView(
            child: Column(
              children: [
                SettingCard(
                  settingItems: [
                    SettingItem(
                      customTitle: Row(
                        children: [
                          const CircleAvatar(
                            radius: 12,
                            backgroundImage: AssetImage(appLogoAsset),
                          ),
                          const SizedBox(width: 18),
                          Text(appName, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(width: 12),
                          const Text(appSlogan, style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.color_lens,
                      title: "更换主题色",
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
                    )
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.account_circle_outlined,
                      title: "哔哩哔哩账号",
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
                    SettingItem(
                      leadingIcon: Icons.link,
                      title: "打开分享链接",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        openFromClipboard(context);
                      },
                    ),
                    SettingItem(
                      leadingIcon: Icons.headphones_outlined,
                      title: "一起听",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return const PartyPage();
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
                  settingItems: [
                    SettingItem(
                      leadingIcon: Icons.info,
                      title: "使用帮助",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return const HelpDoc();
                            },
                          ),
                        );
                      }
                    ),
                    SettingItem(
                      leadingIcon: Icons.warning_rounded,
                      title: "声明与限制",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return const Limit();
                            },
                          ),
                        );
                      }
                    )
                  ],
                ),
                const SizedBox(height: 16),
                SettingCard(
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
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        updateAppVersion(context);
                      }
                    ),
                    SettingItem(
                      leadingIcon: Icons.coffee,
                      title: "支持开发",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return const SupportMe();
                            },
                          ),
                        );
                      }
                    ),
                    SettingItem(
                      customLeadingIcon: Container(
                        margin: const EdgeInsets.only(left: 3),
                        child: SvgPicture.string(
                          IconsSVG.thanks,
                          // ignore: deprecated_member_use
                          color: primaryColor,
                          width: 17,
                          height: 17,
                        ),
                      ),
                      title: "鸣谢",
                      trailing: Icon(Icons.chevron_right, color: primaryColor),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (BuildContext context) {
                              return const Thanks();
                            },
                          ),
                        );
                      }
                    )
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
                    Text("$appName v$appVersion", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Copyright @ Xiwenge", style: TextStyle(color: Colors.grey, fontSize: 12)),
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
