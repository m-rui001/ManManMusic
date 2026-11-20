import "package:bobomusic/components/continuous_rounding.dart";
import "package:bobomusic/components/pressable.dart";
import "package:bobomusic/modules/player/artwork.dart";
import "package:bobomusic/origin_sdk/origin_types.dart";
import "package:bobomusic/utils/haptics.dart";
import "package:flutter/material.dart";

/// 面板顶部：封面 + 曲名 + 作者
///
/// 操作面板要先告诉用户「这是对哪首歌操作」，
/// 之前只有一行加粗标题，长曲名截断后根本认不出来。
class SheetHeader {
  final String title;
  final String? subtitle;
  final MusicItem? track;

  const SheetHeader({required this.title, this.subtitle, this.track});
}

class SheetItem {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;

  /// 删除 / 移出这类不可逆操作，用错误色并单独分隔
  final bool destructive;

  SheetItem({
    required this.title,
    this.subtitle,
    this.icon,
    this.onPressed,
    this.destructive = false,
  });
}

void openBottomSheet(
  BuildContext context,
  List<SheetItem> items, {
  SheetHeader? header,
}) {
  if (items.isEmpty) return;
  AppHaptics.open();
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => _ActionSheet(items: items, header: header),
  );
}

class _ActionSheet extends StatelessWidget {
  final List<SheetItem> items;
  final SheetHeader? header;

  const _ActionSheet({required this.items, this.header});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxHeight = MediaQuery.of(context).size.height * .72;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView(
        shrinkWrap: true,
        padding:
            EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 8),
        children: [
          if (header != null) _header(context, header!),
          for (final item in items) _row(context, item, colors, theme),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, SheetHeader header) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final track = header.track;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Row(
        children: [
          if (track != null) ...[
            TrackArtwork(music: track, size: 52, radius: 13),
            const SizedBox(width: 13),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  header.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                if (header.subtitle != null && header.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    header.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    SheetItem item,
    ColorScheme colors,
    ThemeData theme,
  ) {
    final enabled = item.onPressed != null;
    final ink = item.destructive ? colors.error : colors.onSurface;
    const shape = ContinuousRounding(16);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          if (item.icon != null) ...[
            Icon(item.icon,
                size: 24,
                color:
                    item.destructive ? colors.error : colors.onSurfaceVariant),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    item.subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.destructive)
            Divider(
              height: 9,
              thickness: .6,
              indent: 12,
              endIndent: 12,
              color: colors.outlineVariant.withValues(alpha: .6),
            ),
          Material(
            color: Colors.transparent,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: Pressable(
              pressScale: .98,
              onTap: enabled
                  ? () {
                      Navigator.of(context).pop();
                      item.onPressed!();
                    }
                  : null,
              builder: (context, pressed) => AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                color: pressed
                    ? colors.onSurface.withValues(alpha: .07)
                    : Colors.transparent,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child:
                      enabled ? content : Opacity(opacity: .38, child: content),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
