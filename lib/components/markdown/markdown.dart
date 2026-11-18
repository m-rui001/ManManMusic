import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_markdown/flutter_markdown.dart";
import "package:url_launcher/url_launcher.dart"; // 导入 url_launcher 包

class MarkdownRenderer extends StatefulWidget {
  final String? markdownData;
  final String? markdownFilePath;
  final bool selectable;
  final MarkdownStyleSheet? styleSheet;

  const MarkdownRenderer({
    super.key,
    this.markdownData,
    this.markdownFilePath,
    this.selectable = true,
    this.styleSheet,
  });

  @override
  MarkdownRendererState createState() => MarkdownRendererState();
}

class MarkdownRendererState extends State<MarkdownRenderer> {
  String _renderData = "";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMarkdownData();
  }

  Future<void> _loadMarkdownData() async {
    if (widget.markdownData != null) {
      setState(() {
        _renderData = widget.markdownData!;
        _isLoading = false;
      });
    } else if (widget.markdownFilePath != null) {
      try {
        _renderData = await rootBundle.loadString(widget.markdownFilePath!);
        setState(() {
          _isLoading = false;
        });
      } catch (e) {
        print("加载 Markdown 文件时出错: $e");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildImage(String uri, String? title, String? alt) {
    // 处理图片URL
    if (uri.startsWith("http")) {
      return Image.network(uri, fit: BoxFit.cover);
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color.fromARGB(255, 226, 226, 226),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(uri, fit: BoxFit.cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Markdown(
      data: _renderData,
      selectable: widget.selectable,
      styleSheet: widget.styleSheet ?? MarkdownStyleSheet.fromTheme(Theme.of(context)),
      onTapLink: (String text, String? href, String title) {
        if (href != null) {
          launchUrl(Uri.parse(href));
        }
      },
      sizedImageBuilder: (image) => _buildImage(image.uri.toString(), image.title, image.alt),
    );
  }
}
