import "package:flutter/material.dart";

class SettingItem {
  final IconData? leadingIcon;
  final Widget? customLeadingIcon;
  final String? title;
  final Widget? customTitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  SettingItem({
    this.leadingIcon,
    this.title,
    this.onTap,
    this.trailing,
    this.customTitle,
    this.customLeadingIcon,
  });
}

class SettingCard extends StatelessWidget {
  final List<SettingItem> settingItems;

  const SettingCard({super.key, required this.settingItems});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            for (final item in settingItems)
              ListTile(
                minTileHeight: 55,
                leading: item.leadingIcon != null
                    ? Icon(item.leadingIcon, color: colors.primary)
                    : item.customLeadingIcon,
                title: item.customTitle ??
                    Text(item.title ?? "",
                        style: const TextStyle(fontSize: 16)),
                trailing: item.trailing,
                onTap: item.onTap,
              ),
          ],
        ),
      ),
    );
  }
}
