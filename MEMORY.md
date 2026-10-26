# 项目记忆 — 满满音乐（bobomusic）

## 环境
- Flutter SDK：`D:/flutter`（3.27.1 stable / Dart 3.6.0）
- 每次命令前先：
  ```bash
  export PATH="/d/flutter/bin:$PATH"
  export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
  ```
- 验证手段（本机无 Android SDK / 无 VS C++ 工作负载，Android / Windows 无法编译）：
  - `flutter analyze`（必须 No issues found）
  - `flutter test`
  - `flutter build web --release`
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
- **B 站登录低风险原则**：只用 passport 官方扫码接口 + 只读 web 接口，用户操作才发请求，不做任何写操作。
- 高音质：登录后 `fnval=4048`，失败静默回退 `fnval=16`。
- Android 深链 + 系统分享：`MainActivity` 继承 `AudioServiceActivity`（保后台播放），
  通过 `MethodChannel("manman/share")` 把 `ACTION_SEND`/`ACTION_VIEW` 的文本交给 Dart。

## 常用命令
```bash
# 图标重新生成
python tools/gen_icons.py
# 联调一起听（双进程）
dart run test/party_relay_test.dart host <room>
dart run test/party_relay_test.dart guest <room>
```

## 当前状态
- `flutter analyze` No issues / 24 tests passed / web 构建通过
- 文档：`docs/新增功能说明.md`
- 待办（需用户本地环境）：构建 Android APK 实测扫码登录、深链、系统分享
