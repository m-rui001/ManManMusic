# 项目记忆 — 满满音乐（bobomusic）

## 环境
- Flutter SDK：`D:/flutter`（3.27.1 stable / Dart 3.6.0）
- 每次命令前先：
  ```bash
  export PATH="/d/flutter/bin:$PATH"
  export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
  ```
- 验证手段：
  - `flutter analyze`（必须 No issues found）
  - `flutter test`（24 tests）
- **Android APK 走 GitHub Actions 构建**（本地已删除 devkit/gradle 缓存，不再本地出包）：
  - 仓库：`m-rui001/bobomusic`（**fork**，原仓库 Redstone-1/bobomusic 只有只读权限，推不上去）
  - 工作流：`.github/workflows/release-android.yaml`，`workflow_dispatch` 手动触发或 push `v*` tag
  - 触发：`gh workflow run release-android.yaml --repo m-rui001/bobomusic --ref master`
  - 下载产物（**gh run download 会超时，必须用 curl**）：
    ```bash
    gh api repos/m-rui001/bobomusic/actions/artifacts --jq '.artifacts[] | select(.workflow_run.id==<RUN_ID>) | .id'
    TOKEN=$(gh auth token)
    curl -sL -H "Authorization: Bearer $TOKEN" -o dist/a.zip       "https://api.github.com/repos/m-rui001/bobomusic/actions/artifacts/<ARTIFACT_ID>/zip"
    ```
  - 产物落地 `dist/`（已 gitignore）：`满满音乐-通用版.apk`（37M，装这个）+ 分架构包
- RTK 注意：跑 `flutter test` 前需关闭 testOutputAggregation 与 truncation，否则输出被吞。

## 代码结构要点
- 应用信息集中：`lib/constants/app_info.dart`（appName / appSlogan / appRepoOwner / appLogoAsset / appVersion + `loadAppInfo()`）
- B 站 SDK：`lib/origin_sdk/bili/` — `client.dart`（BiliClient，WBI 签名 / SPI / bili_ticket / playurl）、
  `auth.dart`（BiliAuth 单例，扫码登录 + Cookie 持久化 + 收藏夹）、`ticket.dart`、`utils.dart`（BiliId）
- 播放器：`lib/modules/player/` — `model.dart`（PlayerModel，`current` / `currentPosition` / `play` / `seek` / `pause`）、
  `instance.dart`（BBPlayer）、`player_card/card.dart`（播放页底部按钮区）
- 数据库：`lib/db/db.dart` — `DBOrder(version: 2)`，表：本地 / 我喜欢 / 待播放 / 收藏合集 + 自定义歌单
- 新增模块：
  - `lib/modules/bili_account/`（账号页、扫码登录页、收藏夹导入页）
  - `lib/modules/share/`（share_payload / share_sheet / share_handler）
  - `lib/modules/party/`（party_service / party_page）
  - `lib/utils/bili_link.dart`（B 站链接解析）

## 关键决策（勿改）
- **不部署服务器**：所有在线功能用免费公共服务
  - 一起听中继 = **ntfy.sh**（`GET /topic/json` 订阅、`POST /topic` 发布）。
    实测公共 MQTT broker（hivemq / emqx / mosquitto）在本网络下**跨客户端无法转发消息**，已弃用。
  - 分享 = base64url 载荷内嵌在 `manman://play?d=xxx` 链接里
- **B 站登录低风险原则**：只用官方登录页（内嵌 WebView）/ 扫码接口 + 只读 web 接口，
  用户操作才发请求，不做任何写操作。
  - **登录主路径是内嵌官方网页**（`flutter_inappwebview`），不是扫码：
    手机上没法扫自己屏幕的二维码，而二维码约 180 秒过期，
    截屏→切 App→相册选图走完必然超时。扫码仅作备选。
  - Cookie 从回调 URL 的 query 或 WebView 的 `CookieManager` 取，交给 `BiliAuth.applyLogin`。
- **收藏夹条目必须惰性补 cid**：`fav/resource/list` 不返回 cid，而 `getMusicUrl` 缺 cid 会抛错
  （表现为 source error）。已在 `BiliClient.getMusicUrl` 里按 `x/web-interface/view` 补查并缓存。
- **一起听名单默认空**：不把关注列表全量塞入。原因：关注列表多是 UP 主，
  真一起听歌的只有少数人，全量探测又慢又乱且无法移除。
- 高音质：登录后 `fnval=4048`，失败静默回退 `fnval=16`。
- Android 深链 + 系统分享：`MainActivity` 继承 `AudioServiceActivity`（保后台播放），
  通过 `MethodChannel("manman/share")` 把 `ACTION_SEND`/`ACTION_VIEW` 的文本交给 Dart。

## 歌单 / 设置 / 剪贴板（已重构）
- 歌单页 `lib/modules/music_order/music_order.dart`：已去掉「本地」Tab 与 `components/top_bar.dart`（TopBar）横向分栏，
  改为纵向卡片列表（我喜欢 + 自定义歌单），点击 push `Scaffold + AppBar + MusicListCommon`，长按删除该歌单歌曲。
  `TopBar` 仍被 `lib/modules/player/player_card/card.dart` 引用（FrozenTab.iLike），故文件保留。
- `pages/music_local.dart` 仍存在但已无入口（MusicLocal 不再被任何地方引用），文件保留。
- 设置页 `lib/modules/setting/setting.dart` 只保留：应用信息头、更换主题色、哔哩哔哩账号、检查更新、版本号、Copyright。
  已删 help_doc / limit / support_me / thanks 四个页面；一起听与「打开分享链接」入口也移除。
- 分享改为冷启动自动读剪贴板：`share_handler.dart` 的 `autoCheckClipboard(context)`，
  在 `main.dart` initState 里 postFrameCallback + 1.5s 延迟调用；同一内容 30s 内不重复处理。

## 信息架构（已定稿，勿随意改）
- 底部只三个：**首页 / 一起听 / 设置**（`lib/modules/tabbar/app_navigation.dart`）
- 首页 `lib/modules/music_plaza/music_plaza.dart`：
  - AppBar 搜索栏 + 右上角收起/展开
  - `_AccountCard`：未登录显示「登录解锁高音质」，已登录显示 B 站头像 + 昵称
  - `_TabHeader` 双分栏：**历史播放（默认）/ 我的歌单**，TabController + PageView 双向联动，可左右滑动
  - `_HistoryTab` 用 `PlayHistory`；`_OrdersTab` 用 `MusicOrderView(embedded: true)`
- 歌单页 `MusicOrderView` 新增 `embedded` 参数：true 时不渲染自己的 Scaffold/AppBar
- 历史播放 `lib/modules/history/play_history.dart`：SharedPreferences 持久化，最多 100 条，
  同 `id+playId` 去重提前，`changes` 广播流；`BBPlayer.onPlayRecord` 在 `_play()` 真正播放时回调
- 一起听 `lib/modules/party/party_tab.dart`（`PartyTabView`）：
  - 进页面自动 `createRoom(name, id: 个人房间号)` + `session.startBroadcasting()`
  - 个人房间号：登录后 `bili_<mid>`，未登录用 SharedPreferences `manman_party_self_id` 随机 id
  - 好友列表 `BiliAuth.fetchFriends()`（`x/relation/followings`，**注意是「我关注的」不是互关**）
  - 探测 `PartyService.probeRoom(roomId)`：`GET {relayBase}/{topic}/json?poll=1&since=60s` 一次性拉取，
    解析 NDJSON 取最新 `ty=="state"`；`PartyProbe.isFresh` 90 秒内有效；**不做定时轮询**
- 登录引导 `lib/modules/bili_account/bili_login_gate.dart`：`maybePromptOnStartup`（首次进首页弹一次，
  SharedPreferences `bili_login_asked`/`bili_login_skipped`）、`showPrompSheet`、`openLoginPage`、`ensureLoggedIn`
- 历史播放 UI `lib/modules/history/history_tab.dart`：长按进多选，全选/批量删/单条删；
  `PlayHistory.removeWhere(test)` 支持按条件删除
- 一起听拆成三个文件：`party_tab.dart`（PartyTabView 主页）、`party_widgets.dart`
  （PartySelfCard / PartyRosterTile / PartyMemberChips / PartySectionTitle）、
  `party_pick_page.dart`（从关注列表勾选人）、`party_roster.dart`（名单 + 自动上线开关 + `selfPartyRoomId()`）
- 收藏夹同步 `lib/modules/bili_account/fav_sync.dart`：`FavSyncService`
  - 绑定关系 key `manman_fav_bindings`（favId → tableName）
  - `importFolder` 幂等（已导入则增量：补新增、删已移除）
  - `syncAll` 会删掉 B 站上已不存在的收藏夹歌单
  - `safeTableName` 公开，供测试使用

## 常用命令
```bash
# 图标重新生成
python tools/gen_icons.py
# 检查
export PATH="/d/flutter/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter analyze && flutter test
# 出包（CI）
git push fork master
gh workflow run release-android.yaml --repo m-rui001/bobomusic --ref master
```

## 当前状态
- `flutter analyze` No issues / 35 tests passed
- APK 由 GitHub Actions 构建成功，产物已下载到 `dist/`
- 文档：`docs/新增功能说明.md`
- 待办（需真机）：扫码登录、收藏导入、深链/系统分享唤起、剪贴板自动识别、两机一起听同步

## 坑（踩过，别再踩）
- `flutter analyze` 在 CI 上会因**依赖版本漂移**报 info 级 deprecated → 工作流已用
  `--no-fatal-infos --no-fatal-warnings`，且 `pub get` 带 pub 镜像环境变量与 lock 对齐
- `share_plus 12.0.2` 的 kotlin-stdlib 元数据是 2.2.0 → Kotlin 必须 ≥ 2.2.0（1.9.20 会编译失败）
- `androidx.core:core 1.16.0` 要求 AGP ≥ 8.6.0 → AGP 8.6.0 + Gradle 8.9
- **heredoc 写 Dart 文件会在特定位置截断**（`inRoom` 处反复被切）→ 一律用 write 工具整文件写
- `/tmp` 在 Git Bash 下与 Python 的路径解析不一致 → Python 用 `C:/Users/hp/AppData/Local/Temp/...`
- **CI 每次构建都会重新生成随机 debug keystore**，导致每次覆盖安装都签名冲突。
  已改为正式签名：`.github/workflows/gen-keystore.yaml` 生成一次，
  导出后存进 Secrets `KEYSTORE_BASE64` / `KEY_PROPERTIES`（已配置）。
- `flutter_inappwebview` 要求 AGP ≥ 8.0.1、minSdk 19、compileSdk 34，当前配置（AGP 8.6.0）满足
- `flutter pub add` 在 Windows 上会提示 "Building with plugins requires symlink support"，
  这只影响本地 Windows 构建，CI（Linux）不受影响
