import "package:bobomusic/components/glass_pill.dart";
import "package:flutter/material.dart";

// Keep the default geometry while reserving a full scaled text line.
double _controlHeight(BuildContext context, double base) =>
    base +
    (MediaQuery.textScalerOf(context).scale(16) - 16)
            .clamp(0, double.infinity) *
        1.5;

/// A pill-shaped search input used by the search overlays.
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
      onChanged: onInput,
      textInputAction: TextInputAction.search,
      cursorColor: colors.primary,
      style: TextStyle(fontSize: 16, color: colors.onSurface),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.transparent,
        constraints:
            BoxConstraints.tightFor(height: _controlHeight(context, 48)),
        prefixIcon: Icon(Icons.search_rounded,
            size: 24, color: colors.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(minWidth: 48),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(32),
        ),
        hintMaxLines: 1,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 16, color: colors.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

/// Full-screen search shell: scrollable content remains underneath the blurred
/// safe-area controls, with room for the controls in its initial scroll offset.
class SearchOverlayScaffold extends StatelessWidget {
  final TextEditingController keywordController;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onSearch;
  final ValueChanged<String> onInput;
  final VoidCallback onClose;
  final Widget body;
  final Widget? floatingActionButton;

  const SearchOverlayScaffold({
    super.key,
    required this.keywordController,
    required this.focusNode,
    required this.hintText,
    required this.onSearch,
    required this.onInput,
    required this.onClose,
    required this.body,
    this.floatingActionButton,
  });

  /// Initial list padding that lets results scroll up and visibly pass behind
  /// the translucent header instead of starting beneath a separate app bar.
  static double contentTopInset(BuildContext context) =>
      MediaQuery.paddingOf(context).top + 8 + _controlHeight(context, 48) + 14;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          body,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: GlassPill(
                        child: SearchField(
                          keywordController: keywordController,
                          focusNode: focusNode,
                          hintText: hintText,
                          onSearch: onSearch,
                          onInput: onInput,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      button: true,
                      label: "关闭搜索",
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: GlassPill(
                          child: IconButton(
                            tooltip: "关闭搜索",
                            onPressed: onClose,
                            color: Colors.redAccent,
                            icon: const Icon(Icons.close_rounded, size: 26),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: MediaQuery.viewInsetsOf(context).bottom > 0
          ? null
          : floatingActionButton,
    );
  }
}
