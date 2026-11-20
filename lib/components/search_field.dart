import "package:flutter/material.dart";

/// 搜索输入框
///
/// 半透明底 + 主题色文字，深浅主题都读得清；
/// 之前写死浅灰底，深色模式下白字落在白底上，打了什么都看不见。
class SearchField extends StatelessWidget {
  final TextEditingController keywordController;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onSearch;
  final ValueChanged<String> onInput;

  const SearchField({
    super.key,
    required this.keywordController,
    required this.focusNode,
    required this.hintText,
    required this.onSearch,
    required this.onInput,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TextField(
      controller: keywordController,
      focusNode: focusNode,
      onSubmitted: (_) => onSearch(),
      cursorColor: colors.primary,
      style: TextStyle(fontSize: 13, color: colors.onSurface),
      decoration: InputDecoration(
        filled: true,
        fillColor: colors.onSurface.withValues(alpha: .06),
        constraints: const BoxConstraints(maxHeight: 40),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(14),
        ),
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      onChanged: (value) {
        if (value.isEmpty) {
          onSearch();
          return;
        }
        onInput(value);
      },
    );
  }
}
