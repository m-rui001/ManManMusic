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

  testWidgets("搜索 overlay 保留内容滚动层、磨砂控件和单一搜索入口", (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Colors.blue, Brightness.dark),
        home: SearchOverlayScaffold(
          keywordController: controller,
          focusNode: focusNode,
          hintText: "搜索",
          onSearch: () {},
          onInput: (_) {},
          onClose: () => closed = true,
          body: ListView(
            children: const [ListTile(title: Text("实际搜索结果背景内容"))],
          ),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNWidgets(2));
    expect(find.text("实际搜索结果背景内容"), findsOneWidget);
    expect(find.text("B站"), findsNothing);
    expect(find.text("资料库"), findsNothing);
    await tester.enterText(find.byType(TextField), "马勒");
    await tester.pump();
    expect(controller.text, "马勒");
    await tester.tap(find.byTooltip("关闭搜索"));
    expect(closed, isTrue);
  });

  testWidgets("搜索内容的初始内边距包含安全区和 overlay 控件", (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => SearchOverlayScaffold(
            keywordController: controller,
            focusNode: focusNode,
            hintText: "搜索",
            onSearch: () {},
            onInput: (_) {},
            onClose: () {},
            body: Builder(
              builder: (context) {
                expect(
                  SearchOverlayScaffold.contentTopInset(context),
                  equals(70),
                );
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
  });
  testWidgets("Scaled search controls leave room for the first result",
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: SearchOverlayScaffold(
        keywordController: controller,
        focusNode: focus,
        hintText: "Search",
        onSearch: () {},
        onInput: (_) {},
        onClose: () {},
        body: Builder(
            builder: (context) => ListView(
                  padding: EdgeInsets.only(
                      top: SearchOverlayScaffold.contentTopInset(context)),
                  children: const [Text("First result")],
                )),
      ),
    ));
    expect(tester.getSize(find.byType(TextField)).height, greaterThan(48));
    final field = find.byType(TextField);
    expect(tester.getTopLeft(find.text("First result")).dy,
        closeTo(tester.getBottomLeft(field).dy + 14, .1));
    expect(tester.takeException(), isNull);
  });
  testWidgets("Last result can be selected above the keyboard", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    int? selected;
    await tester.pumpWidget(MaterialApp(
        home: SearchOverlayScaffold(
      keywordController: controller,
      focusNode: focus,
      hintText: "Search",
      onSearch: () {},
      onInput: (_) {},
      onClose: () {},
      floatingActionButton: const Text("Mini player"),
      body: ListView.builder(
          itemCount: 30,
          itemBuilder: (_, index) => ListTile(
              title: Text("Result $index"), onTap: () => selected = index)),
    )));
    await tester.tap(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    expect(find.text("Mini player"), findsNothing);
    await tester.scrollUntilVisible(find.text("Result 29"), 180,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text("Result 29")).dy,
        lessThanOrEqualTo(380));
    await tester.tap(find.text("Result 29"));
    expect(selected, 29);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(find.text("Mini player"), findsOneWidget);
  });
}
