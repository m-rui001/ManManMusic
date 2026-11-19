// ignore_for_file: use_super_parameters
import "package:flutter/material.dart";
import "package:path/path.dart" as path;

class CustomDialog extends StatelessWidget {
  final String? title;
  final Widget body;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const CustomDialog({
    Key? key,
    this.title,
    required this.body,
    required this.onConfirm,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20, left: 20, right: 20, bottom: 12),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(16)), // 设置足够大的圆角半径
              child: Image.asset(path.join("assets", "images", "gif_cat_dog.gif"))
            ),
          ),
          // 标题区域
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 6, right: 24),
              child: Center(
                child: Text(
                  title!,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              )
            ),
          // 内容区域
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 4),
            child: Center(
              child: body,
            ),
          ),
          // 底部按钮区域
          Container(
            padding: const EdgeInsets.only(top: 12, left: 20, right: 20, bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: onCancel,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.surfaceContainerHighest,
                    foregroundColor: colors.onSurface,
                  ),
                  child: const Text("取消"),
                ),
                const SizedBox(width: 20),
                FilledButton(
                  onPressed: onConfirm,
                  child: const Text("确认"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
