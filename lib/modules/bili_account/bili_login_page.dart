import "dart:async";

import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:bot_toast/bot_toast.dart";
import "package:flutter/material.dart";
import "package:qr_flutter/qr_flutter.dart";

/// 哔哩哔哩扫码登录
///
/// 说明：只走官方 web 端扫码接口，不在客户端保存密码，
/// 也不会做任何批量/自动化请求，尽量避免账号被风控。
class BiliLoginPage extends StatefulWidget {
  const BiliLoginPage({super.key});

  @override
  State<BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends State<BiliLoginPage> {
  final BiliAuth _auth = BiliAuth.instance;

  BiliQrCode? _qr;
  BiliQrStatus _status = BiliQrStatus.waiting;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _refreshQr();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshQr() async {
    _pollTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _status = BiliQrStatus.waiting;
    });

    try {
      final qr = await _auth.qrGenerate();
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _loading = false;
      });
      _startPoll(qr.key);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "获取二维码失败，请检查网络后重试";
      });
    }
  }

  void _startPoll(String key) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_done) {
        timer.cancel();
        return;
      }
      try {
        final res = await _auth.qrPoll(key);
        if (!mounted) return;

        if (res.status == BiliQrStatus.expired) {
          timer.cancel();
          setState(() => _status = BiliQrStatus.expired);
          return;
        }

        if (res.status == BiliQrStatus.success) {
          timer.cancel();
          _done = true;
          final cookies = res.cookies;
          if (cookies == null) {
            setState(() {
              _status = BiliQrStatus.failed;
              _done = false;
            });
            return;
          }
          setState(() => _status = BiliQrStatus.success);
          final ok = await _auth.applyLogin(cookies);
          if (!mounted) return;
          if (ok) {
            Navigator.of(context).pop(true);
          } else {
            setState(() {
              _status = BiliQrStatus.failed;
              _done = false;
            });
          }
          return;
        }

        if (res.status != _status) {
          setState(() => _status = res.status);
        }
      } catch (_) {
        // 单次轮询失败不打断流程
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("哔哩哔哩账号", style: TextStyle(fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _status.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _status.tip,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const SizedBox(height: 18),
                    _buildQrArea(primaryColor),
                    const SizedBox(height: 16),
                    if (_status == BiliQrStatus.expired ||
                        _status == BiliQrStatus.failed)
                      ElevatedButton(
                        onPressed: _refreshQr,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("刷新二维码"),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.all(Radius.circular(10)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 16,
                          color: Color(0xFFB8860B),
                        ),
                        SizedBox(width: 6),
                        Text(
                          "账号安全说明",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB8860B),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      "· 只使用哔哩哔哩官方网页版扫码登录，登录信息仅保存在本机\n"
                      "· 不会发送任何自动化、批量或异常的请求\n"
                      "· 只读取你自己的收藏夹，不做任何修改操作\n"
                      "· 随时可在设置里退出登录，清除本地凭证",
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.8,
                        color: Color(0xFF8B6D1F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQrArea(Color primaryColor) {
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.grey, size: 36),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: _refreshQr, child: const Text("重试")),
            ],
          ),
        ),
      );
    }

    final qr = _qr;
    if (qr == null) {
      return const SizedBox(height: 200);
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: QrImageView(
            data: qr.url,
            version: QrVersions.auto,
            size: 180,
            gapless: true,
            backgroundColor: Colors.white,
          ),
        ),
        if (_status == BiliQrStatus.expired ||
            _status == BiliQrStatus.scanned)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _status == BiliQrStatus.scanned
                          ? Icons.phone_iphone
                          : Icons.refresh,
                      size: 30,
                      color: primaryColor,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status == BiliQrStatus.scanned ? "请在手机上确认" : "二维码已失效",
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_status == BiliQrStatus.expired) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _refreshQr,
                        child: const Text("点击刷新"),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 退出登录确认
Future<void> confirmBiliLogout(BuildContext context) async {
  final auth = BiliAuth.instance;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("退出哔哩哔哩账号"),
      content: const Text(
        "退出后会清除本机保存的登录凭证，收藏夹导入功能将不可用。",
        style: TextStyle(fontSize: 12),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text("取消"),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text("退出", style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    ),
  );

  if (ok == true) {
    await auth.logout();
    BotToast.showText(text: "已退出登录");
  }
}
