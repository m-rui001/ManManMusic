import "dart:ui" as ui;

import "package:flutter/material.dart";

/// Search destinations share one field and retain its query/focus while switching.
enum SearchScope { bili, library }

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
            BoxConstraints.tightFor(height: _controlHeight(context, 56)),
        prefixIcon: Icon(Icons.search_rounded,
            size: 26, color: colors.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(minWidth: 54),
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(32),
        ),
        hintMaxLines: 1,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: 16, color: colors.onSurfaceVariant),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
  final SearchScope scope;
  final ValueChanged<SearchScope> onScopeChanged;
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
    required this.scope,
    required this.onScopeChanged,
    required this.onClose,
    required this.body,
    this.floatingActionButton,
  });

  /// Initial list padding that lets results scroll up and visibly pass behind
  /// the translucent header instead of starting beneath a separate app bar.
  static double contentTopInset(BuildContext context) =>
      MediaQuery.paddingOf(context).top +
      8 +
      _controlHeight(context, 56) +
      12 +
      _controlHeight(context, 52) +
      14;

  Widget _blurredSurface({
    required BuildContext context,
    required Widget child,
    required BorderRadius borderRadius,
  }) {
    final color = Theme.of(context).colorScheme.surface;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.withValues(alpha: .65),
                  color.withValues(alpha: .32)
                ]),
            border: Border.all(color: Colors.white.withValues(alpha: .18)),
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _scopeButton(BuildContext context, SearchScope value, String label) {
    final selected = scope == value;
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: "$label搜索范围",
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => onScopeChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: _controlHeight(context, 52),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? colors.onSurface.withValues(alpha: .22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _blurredSurface(
                            context: context,
                            borderRadius: BorderRadius.circular(32),
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
                            width: 56,
                            height: 56,
                            child: _blurredSurface(
                              context: context,
                              borderRadius: BorderRadius.circular(28),
                              child: IconButton(
                                tooltip: "关闭搜索",
                                onPressed: onClose,
                                color: Colors.redAccent,
                                icon: const Icon(Icons.close_rounded, size: 30),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _blurredSurface(
                      context: context,
                      borderRadius: BorderRadius.circular(30),
                      child: Row(
                        children: [
                          _scopeButton(context, SearchScope.bili, "B站"),
                          _scopeButton(context, SearchScope.library, "资料库"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}
