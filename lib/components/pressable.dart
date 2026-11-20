import "package:bobomusic/constants/motion.dart";
import "package:flutter/material.dart";

/// 按压缩放反馈
///
/// Cirro 的按钮按下去是整块轻轻缩一下，松手弹回，没有 Material 的水波纹。
/// 两种用法：
/// - 传 onTap / onLongPress：自己接管点击（面板行这类没有 IconButton 的地方）；
/// - 只包 child：不抢点击事件，纯缩放，套在 IconButton 外面用。
class Pressable extends StatefulWidget {
  final Widget? child;
  final Widget Function(BuildContext context, bool pressed)? builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressScale;
  final bool enabled;

  const Pressable({
    super.key,
    this.child,
    this.builder,
    this.onTap,
    this.onLongPress,
    this.pressScale = .93,
    this.enabled = true,
  }) : assert(child != null || builder != null);

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _down(TapDownDetails _) {
    if (widget.enabled && !_pressed) setState(() => _pressed = true);
  }

  void _up(TapUpDetails _) {
    if (_pressed) setState(() => _pressed = false);
  }

  void _cancel() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final claimsTap = widget.onTap != null || widget.onLongPress != null;
    return AnimatedScale(
      scale: _pressed ? widget.pressScale : 1,
      duration: AppMotion.fast,
      curve: Curves.easeOut,
      child: GestureDetector(
        behavior:
            claimsTap ? HitTestBehavior.opaque : HitTestBehavior.translucent,
        onTapDown: widget.enabled ? _down : null,
        onTapUp: widget.enabled ? _up : null,
        onTapCancel: widget.enabled ? _cancel : null,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: widget.builder?.call(context, _pressed) ?? widget.child,
      ),
    );
  }
}
