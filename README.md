<div align="center">

<img src="./logo.jpg" alt="ManManMusic" width="120" />

# 满满音乐 · ManManMusic

听歌自由。一个 Flutter 写的 B 站音频播放器，外加一个「一起听」。

![Flutter](https://img.shields.io/badge/Flutter-3.27-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow)

</div>

---

## 这是什么

满满音乐把 B 站上的音频（音乐区、翻唱、live、播客……）当成一个巨大的曲库来听：

- 搜索、播放、歌词、后台播放、通知栏控制
- 登录 B 站账号后自动拿高音质
- 只有**一张歌单**：点红心就进「满满音乐」，没有一堆歌单要管
- 收藏夹内容可以手动导进这张歌单，导完也能在 B 站找到原收藏夹
- 「一起听」：把歌同步给朋友，谁都能开、谁都能加

整个 App **没有自建服务器**，只用了 B 站官方 web 接口和免费的 ntfy.sh 做中继。

## 功能

| | |
| --- | --- |
| 搜索与播放 | 关键词搜索 B 站视频，直接当音频播放；支持歌词、进度拖动等基础播放控制 |
| 满满音乐 | 全 App 唯一的歌单。点红心加进来，长按或菜单里可以删掉 |
| 收藏夹导入 | 登录后可以把任意 B 站收藏夹「导入」进满满音乐，重复导入只补新歌 |
| 手动同步 | 不自动同步。想拉收藏夹里的新视频时点一次「同步」 |
| 历史播放 | 自动记录最近 100 首，支持批量删除 |
| 待播放列表 | 临时队列，最多 1000 首 |
| 一起听 | 房间准入 + 共管权限 + 进出提示音，详见下一节 |
| 分享 | 单曲 / 一起听房间都能生成链接，也能识别 B 站分享链接 |
| 主题 | 主题色可换，数据全部存在本机 |

## 一起听是怎么管的

房间号就是你的 B 站 UID（`bili_你的UID`），所以朋友不用问你房间号。

| 角色 | 怎么来的 | 能做什么 |
| --- | --- | --- |
| 房主 | 自己上线 | 换歌、暂停、拖进度，广播给房间 |
| 共管 | 在房主的「一起听名单」里，并且被点了红心 | 和房主一样，可以换歌、拖进度 |
| 听众 | 在名单里，但没被点红心 | 只能听；换歌 / 拖进度会被锁住，想自己操作要先退出房间 |
| 路人 | 不在名单里 | 进不来（房主会直接拒绝） |

- 有人进来 / 离开时，双方都会收到提示并听到一声很轻的提示音（可以关），不会打断音乐
- 房主下线会广播一条 `bye`，房间立刻结束，不会留一堆「幽灵成员」
- 听众掉线 40 秒没有心跳会被移出成员列表；房主 45 秒没有动静，听众会自动退出

## 构建

需要 Flutter 3.27.x（Dart 3.6）和 JDK 17。

```bash
flutter pub get
flutter run            # 连上设备直接跑
flutter analyze
flutter test
```

打 Android 包走 GitHub Actions（`.github/workflows/release-android.yaml`），
手动触发或推 `v*` tag，产物里挑 `满满音乐-通用版.apk` 安装即可。

## 代码结构

```
lib/
  db/                     单库，v3 起只有「满满音乐 / 本地 / 待播放」三张歌单表
  modules/
    player/               播放器（just_audio + audio_service）与播放页
    music_plaza/          首页：搜索、历史、我的歌单
    music_order/          满满音乐列表与导入同步入口
    party/                一起听：协议、会话、权限、提示音、页面
    bili_account/         扫码 / 网页登录、收藏夹导入
    history/              历史播放
    share/                分享链接
  origin_sdk/bili/        B 站接口封装（WBI 签名、playurl、收藏夹）
```

数据库升级是自动的：老版本的「我喜欢」和一堆「收藏夹_xxx」会在第一次启动时合并进「满满音乐」。

## 数据与隐私

- 登录 Cookie、歌单、历史、一起听名单全部存在本机，不上传
- 一起听只把「歌名 / 封面 / 播放进度 / 昵称 / UID」发到 ntfy.sh 的公开 topic 里，消息默认 12 小时后清空
- 不做任何 B 站写操作（不点赞、不投币、不改收藏夹），只读

## 上游与许可

本项目是 [Redstone-1/bobomusic](https://github.com/Redstone-1/bobomusic) 的二次开发版本：

- 播放器、搜索等基础能力来自 bobomusic，其播放器与互联网搜索部分又基于 [bb-music/flutter-app](https://github.com/bb-music/flutter-app)
- 在原项目基础上重做了歌单模型、收藏夹导入、一起听权限、播放页布局

本仓库**新增与修改的代码以 MIT 发布**（见 `LICENSE`）；
来自上游的 Apache-2.0 部分仍遵循 Apache-2.0（见 `LICENSE-APACHE`），并保留原项目署名。

> 本项目仅供学习与个人使用，音源版权归哔哩哔哩及原 UP 主所有。
