import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'tool_actions.dart';

class ViewerScreen extends StatefulWidget {
  final File file;
  const ViewerScreen({super.key, required this.file});
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  PdfTextSearchResult? _result;
  late final Future<int> _lastPage;

  String get _key => 'page:${widget.file.path}';

  @override
  void initState() {
    super.initState();
    _lastPage = SharedPreferences.getInstance()
        .then((p) => p.getInt(_key) ?? 1);
  }

  Future<void> _search() async {
    final c = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Buscar no PDF'),
        content: TextField(
            controller: c,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('Buscar')),
        ],
      ),
    );
    if (q == null || q.trim().isEmpty) return;
    _result?.clear();
    final r = _controller.searchText(q.trim());
    r.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _result = r);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.file.path.split(Platform.pathSeparator).last;
    final hasResult = _result != null && _result!.hasResult;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          if (hasResult) ...[
            IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: _result!.previousInstance),
            IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _result!.nextInstance),
          ],
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
          IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => Share.shareXFiles([XFile(widget.file.path)])),
          IconButton(
              tooltip: 'Ferramentas',
              icon: const Icon(Icons.build_outlined),
              onPressed: () => ToolActions.showPdfTools(context, widget.file)),
        ],
      ),
      body: FutureBuilder<int>(
        future: _lastPage,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SfPdfViewer.file(
            widget.file,
            controller: _controller,
            initialPageNumber: snap.data!,
            onPageChanged: (d) async {
              final p = await SharedPreferences.getInstance();
              await p.setInt(_key, d.newPageNumber);
            },
          );
        },
      ),
    );
  }
}
