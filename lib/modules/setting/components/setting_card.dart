import "package:bobomusic/components/continuous_rounding.dart";
import "package:flutter/material.dart";

class SettingItem {
  final IconData? leadingIcon;
  final Widget? customLeadingIcon;
  final String? title;
  final String? subtitle;
  final Widget? customTitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  SettingItem({
    this.leadingIcon,
    this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.customTitle,
    this.customLeadingIcon,
  });
}

/// 一组设置项
///
/// 带小节标题和每项的说明文字：开关光看名字猜不出后果，
/// 一行小字讲清楚「关掉会怎样」，比弹窗确认省事。
class SettingCard extends StatelessWidget {
  final List<SettingItem> settingItems;
  final String? sectionTitle;

  const SettingCard({
    super.key,
    required this.settingItems,
    this.sectionTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = sectionTitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ),
        Material(
          color: colors.surfaceContainerLow,
          shape: const ContinuousRounding(18),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < settingItems.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    thickness: .6,
                    indent: settingItems[index].leadingIcon == null &&
                            settingItems[index].customLeadingIcon == null
                        ? 16
                        : 56,
                    endIndent: 16,
                    color: colors.outlineVariant.withValues(alpha: .45),
                  ),
                _row(context, settingItems[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, SettingItem item) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final subtitle = item.subtitle;
    return ListTile(
      minTileHeight: 58,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      leading: item.leadingIcon != null
          ? Icon(item.leadingIcon, size: 22, color: colors.primary)
          : item.customLeadingIcon,
      title: item.customTitle ??
          Text(
            item.title ?? "",
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500),
          ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.32,
                ),
              ),
            ),
      trailing: item.trailing,
      onTap: item.onTap,
    );
  }
}