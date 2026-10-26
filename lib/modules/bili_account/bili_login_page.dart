import "dart:async";

import "package:bobomusic/origin_sdk/bili/auth.dart";
import "package:flutter/material.dart";
import "package:flutter_inappwebview/flutter_inappwebview.dart";
import "package:qr_flutter/qr_flutter.dart";

/// 哔哩哔哩登录
///
/// 主路径是**内嵌官方网页登录**（手机号 / 验证码 / 密码），
/// 因为绝大多数人手上只有手机，没有第二块屏幕去扫自己的二维码。
///
/// 扫码作为备选保留（有第二台设备时更快）。
///
/// 安全说明：页面就是哔哩哔哩官方登录页，账号密码只输给官方，
/// App 不接触密码，只在登录成功后从官方回调里取 Cookie 存到本机。
class BiliLoginPage extends StatefulWidget {
  const BiliLoginPage({super.key});

  @override
  State<BiliLoginPage> createState() => _BiliLoginPageState();
}

class _BiliLoginPageState extends State<BiliLoginPage> {
  /// 0 = 网页登录，1 = 扫码登录
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text("哔哩哔哩账号", style: TextStyle(fontSize: 17)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                _modeButton("手机登录", 0, primaryColor),
                const SizedBox(width: 8),
                _modeButton("扫码登录", 1, primaryColor),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _mode == 0
            ? _WebLoginView(onSuccess: _onLoginSuccess)
            : _QrLoginView(onSuccess: _onLoginSuccess),
      ),
    );
  }

  Widget _modeButton(String label, int mode, Color primaryColor) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : Colors.grey[700],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onLoginSuccess() {
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }
}

/// 内嵌官方网页登录
class _WebLoginView extends StatefulWidget {
  final VoidCallback onSuccess;

  const _WebLoginView({required this.onSuccess});

  @override
  State<_WebLoginView> createState() => _WebLoginViewState();
}

class _WebLoginViewState extends State<_WebLoginView> {
  InAppWebViewController? _controller;
  double _progress = 0;
  bool _done = false;
  bool _saving = false;

  /// 登录成功后 B 站会跳到这些域名，回调 URL 的 query 里带 Cookie
  static const List<String> _callbackHosts = [
    "www.bilibili.com",
    "bilibili.com",
    "m.bilibili.com",
    "passport.bilibili.com",
  ];

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Stack(
      children: [
        Column(
          children: [
            if (_progress < 1)
              LinearProgressIndicator(
                value: _progress,
                minHeight: 2,
                backgroundColor: Colors.transparent,
                color: primaryColor,
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(
                    "https://passport.bilibili.com/login",
                  ),
                ),
                initialSettings: InAppWebViewSettings(
                  userAgent: biliMobileUserAgent,
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  sharedCookiesEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  supportZoom: false,
                  useHybridComposition: true,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                },
                onProgressChanged: (controller, progress) {
                  if (mounted) setState(() => _progress = progress / 100);
                },
                // 每次页面跳转都检查是否已经登录成功
                onLoadStop: (controller, url) async {
                  if (_done || _saving || url == null) return;
                  await _tryHarvestCookies(controller, url.toString());
                },
                onUpdateVisitedHistory: (controller, url, isReload) async {
                  if (_done || _saving || url == null) return;
                  await _tryHarvestCookies(controller, url.toString());
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              color: const Color.fromARGB(255, 250, 250, 250),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 13, color: Colors.grey[500]),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      "这是哔哩哔哩官方登录页，密码只交给 B 站，App 不保存密码",
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ),
                  if (_saving)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_progress < 1 && _controller == null)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  /// 尝试从 WebView 里取 Cookie 判断是否登录成功
  Future<void> _tryHarvestCookies(
    InAppWebViewController controller,
    String url,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    // 还没离开登录页就继续等
    final onCallbackHost = _callbackHosts.contains(uri.host);
    if (!onCallbackHost) return;

    // 回调 URL 的 query 里直接带 Cookie（B 站登录成功后的跳转格式）
    final fromQuery = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      if (_cookieKeys.contains(k) && v.isNotEmpty) fromQuery[k] = v;
    });

    Map<String, String> cookies = fromQuery;

    // query 里没有就从 WebView 的 CookieManager 里取（更通用）
    if (cookies["SESSDATA"] == null) {
      final all = await CookieManager.instance().getCookies(
        url: WebUri("https://www.bilibili.com"),
      );
      final map = <String, String>{};
      for (final c in all) {
        if (_cookieKeys.contains(c.name) && (c.value ?? "").isNotEmpty) {
          map[c.name] = c.value!;
        }
      }
      if (map["SESSDATA"] != null) cookies = map;
    }

    if (cookies["SESSDATA"] == null) return;

    _saving = true;
    if (mounted) setState(() {});

    final ok = await BiliAuth.instance.applyLogin(cookies);

    if (!mounted) return;
    _saving = false;

    if (ok) {
      _done = true;
      widget.onSuccess();
    } else {
      setState(() {});
    }
  }

  /// 登录相关的 Cookie 字段
  static const Set<String> _cookieKeys = {
    "SESSDATA",
    "bili_jct",
    "DedeUserID",
    "DedeUserID__ckMd5",
    "sid",
  };
}

/// 扫码登录（备选，需要另一台设备）
class _QrLoginView extends StatefulWidget {
  final VoidCallback onSuccess;

  const _QrLoginView({required this.onSuccess});

  @override
  State<_QrLoginView> createState() => _QrLoginViewState();
}

class _QrLoginViewState extends State<_QrLoginView> {
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
      _done = false;
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
            widget.onSuccess();
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
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
                  textAlign: TextAlign.center,
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
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 255, 247, 230),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 15,
                  color: Color(0xFFB8860B),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "扫码要用另一台设备。只有一个手机的话，"
                    "请用上面的「手机登录」，直接输手机号和验证码更快。",
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFB8860B),
                      height: 1.6,
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

  Widget _buildQrArea(Color primaryColor) {
    if (_loading) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return SizedBox(
        width: 200,
        height: 200,
        child: Center(
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }

    if (_qr == null) return const SizedBox(width: 200, height: 200);

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: QrImageView(
            data: _qr!.url,
            version: QrVersions.auto,
            size: 190,
            backgroundColor: Colors.white,
          ),
        ),
        if (_status == BiliQrStatus.expired ||
            _status == BiliQrStatus.failed)
          Container(
            width: 190,
            height: 190,
            color: Colors.white.withValues(alpha: 0.92),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh, size: 30, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  _status == BiliQrStatus.expired ? "二维码已过期" : "登录失败",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _refreshQr,
                  child: Text(
                    "点击刷新",
                    style: TextStyle(fontSize: 12, color: primaryColor),
                  ),
                ),
              ],
            ),
          ),
        if (_status == BiliQrStatus.scanned)
          Container(
            width: 190,
            height: 190,
            color: Colors.white.withValues(alpha: 0.92),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 30, color: primaryColor),
                const SizedBox(height: 8),
                const Text(
                  "已扫码，请在手机上确认",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
