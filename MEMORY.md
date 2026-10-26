# 项目记忆 — 满满音乐（bobomusic）

## 环境
- Flutter SDK：`D:/flutter`（3.27.1 stable / Dart 3.6.0）
- 每次命令前先：
  ```bash
  export PATH="/d/flutter/bin:$PATH"
  export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
  ```
- 验证手段：`flutter analyze`（必须 No issues found）+ `flutter test`（38 tests）
- **Android APK 走 GitHub Actions 构建**（本地没有 gradle 缓存）：
  - 新仓库：`m-rui001/ManManMusic`（public，MIT）；旧 fork `m-rui001/bobomusic` 只用来出包
  - 工作流：`.github/workflows/release-android.yaml`，`workflow_dispatch` 或 push `v*` tag
  - 下载产物必须用 curl（`gh run download` 会超时）：
    ```bash
    gh api repos/m-rui001/bobomusic/actions/artifacts --jq '.artifacts[] | select(.workflow_run.id==<RUN_ID>) | .id'
    TOKEN=$(gh auth token)
    curl -sL -H "Authorization: Bearer $TOKEN" -o dist/a.zip "https://api.github.com/repos/m-rui001/bobomusic/actions/artifacts/<ARTIFACT_ID>/zip"
    ```
  - 产物落 `dist/`（已 gitignore）

## 代码结构要点
- 应用信息集中：`lib/constants/app_info.dart`
- B 站 SDK：`lib/origin_sdk/bili/`（client / auth / ticket / utils / sign）
- 播放器：`lib/modules/player/` — `model.dart`（PlayerModel）、`instance.dart`（BBPlayer）、
  `service.dart`（AudioPlayerHandler，**播放控制的唯一拦截点**）、`player_card/card.dart`（播放页）
- 数据库：`lib/db/db.dart` — `DBOrder(version: 3)`，表：满满音乐 / 本地 / 待播放
- 一起听：`lib/modules/party/`
  - `party_service.dart` 协议 + 准入 + 共管 + 保活 + probe
  - `party_page.dart` PartySession（跟随 / 广播 / 提示音 / Toast）+ PartyJoinPage
  - `party_roster.dart` 名单（含 canControl）、`party_tone.dart` 提示音、`party_control.dart` 控制锁
  - `party_tab.dart` / `party_widgets.dart` / `party_pick_page.dart` 界面
- 收藏夹：`lib/modules/bili_account/fav_sync.dart`（并入满满音乐）+ `bili_fav_page.dart`

## 关键决策（勿改）
- **不部署服务器**：一起听用 ntfy.sh（`GET /topic/json` 订阅、`POST /topic` 发布），
  分享用 base64url 载荷内嵌在 `manman://play?d=xxx`
- **B 站登录低风险原则**：只用官方登录页（内嵌 WebView）+ 只读 web 接口，不做任何写操作
- **全 App 只有一张歌单「满满音乐」**：红心 / 导入都进这张表。
  不再按收藏夹建表（v2 的表名取自标题，重名或空标题就 `table already exists`）
- **导入的条目必须带 playId**：`getUpdatedMusicList` 用 playId 链算 prev/next，
  缺了 playId 整个列表会被算成「一首歌」，表现为「只能播放一首」
- **不做自动同步**：收藏夹只增不删，用户点「同步」才请求接口
- **一起听权限**：房主按 UID 校验名单准入；名单里点红心 = 共管；其余只能听
- **播放控制锁放在 AudioPlayerHandler**：通知栏 / 锁屏 / 页面按钮一次全管住，
  远端同步时用 `PartyService.applyingRemote` 放行
- 高音质：登录后 `fnval=4048`，失败静默回退 `fnval=16`
- 一起听名单默认空；未登录不开房（uid=0 认不出人）

## 数据库升级（v2 → v3）
- `我喜欢` → 改名 `满满音乐`（若目标表已存在则按 mid 合并后删除旧表）
- 所有 `收藏夹_*` 表按 mid 合并进 `满满音乐` 后 DROP
- `orderTableSql()` 一律 `CREATE TABLE IF NOT EXISTS`

## 常用命令
```bash
# 提示音重新生成（assets/sounds/*.wav）
python tools/gen_sounds.py
# 图标
python tools/gen_icons.py
# 检查
export PATH="/d/flutter/bin:$PATH"
flutter analyze && flutter test
```

## 当前状态
- `flutter analyze` No issues / 38 tests passed
- 文档：`README.md`、`docs/新增功能说明.md`
- 待真机验证：网页登录、收藏夹导入、两机一起听（准入 / 共管 / 提示音 / 掉线）

## 坑（踩过，别再踩）
- **Write 工具覆盖文件前必须先 Read**，否则报 "File has been modified since read" 并静默失败
- 用 REPL 写 Dart 源码时，模板字符串里的 ${ 会被 JS 插值 → 用 String.raw + 占位符替换
- `flutter analyze` 在 CI 上会因依赖漂移报 info 级 deprecated → 工作流用 `--no-fatal-infos --no-fatal-warnings`
- `share_plus 12.0.2` 要求 Kotlin ≥ 2.2.0；`androidx.core 1.16.0` 要求 AGP ≥ 8.6.0
- **CI 每次构建会生成随机 debug keystore** → 已改用正式签名（Secrets：`KEYSTORE_BASE64` / `KEY_PROPERTIES`）
- `flutter_inappwebview` 要求 AGP ≥ 8.0.1 / minSdk 19 / compileSdk 34
- 命令行输出里连续空行可能被折叠，看文件请用 `python -c "print(repr(...))"` 确认
