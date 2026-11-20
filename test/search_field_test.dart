import "package:bobomusic/components/search_field.dart";
import "package:bobomusic/constants/theme_color.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  Future<void> pumpField(WidgetTester tester, Brightness brightness) async {
    final theme = buildAppTheme(Colors.blue, brightness);
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(
            title: SearchField(
              keywordController: controller,
              focusNode: focusNode,
              hintText: "搜索",
              onSearch: () {},
              onInput: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets("深色模式下搜索框半透明、文字跟着主题走", (tester) async {
    await pumpField(tester, Brightness.dark);
    final colors = buildAppTheme(Colors.blue, Brightness.dark).colorScheme;
    final field = tester.widget<TextField>(find.byType(TextField));
    final fill = field.decoration!.fillColor!;
    expect(fill.a, lessThan(.5));
    expect(field.style!.color, colors.onSurface);
    expect(field.decoration!.hintStyle!.color, colors.onSurfaceVariant);

    await tester.enterText(find.byType(TextField), "夜曲");
    await tester.pump();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.style.color, colors.onSurface);
    expect(editable.style.color!.a, 1);
  });

  testWidgets("浅色模式下搜索框同样是半透明底", (tester) async {
    await pumpField(tester, Brightness.light);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.fillColor!.a, lessThan(.5));
    expect(field.style!.color,
        buildAppTheme(Colors.blue, Brightness.light).colorScheme.onSurface);
  });
}
