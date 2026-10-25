import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tool_actions.dart';

/// Leitor de PDF (pdfrx/PDFium): respeita retrato e paisagem de cada página,
/// ajusta à largura da tela e permite zoom com pinça.
class ViewerScreen extends StatefulWidget {
  final File file;
  const ViewerScreen({super.key, required this.file});
  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _controller = PdfViewerController();
  late final PdfTextSearcher _searcher;
  late final Future<int> _lastPage;

  String get _key => 'page:${widget.file.path}';

  @override
  void initState() {
    super.initState();
    _searcher = PdfTextSearcher(_controller)..addListener(_update);
    _lastPage = SharedPreferences.getInstance()
        .then((p) => p.getInt(_key) ?? 1);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searcher.removeListener(_update);
    _searcher.dispose();
    super.dispose();
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
    _searcher.startTextSearch(q.trim(), searchImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.file.path.split(Platform.pathSeparator).last;
    final hasResult = _searcher.hasMatches;
    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          if (hasResult) ...[
            IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: () => _searcher.goToPrevMatch()),
            IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: () => _searcher.goToNextMatch()),
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
          return PdfViewer.file(
            widget.file.path,
            controller: _controller,
            initialPageNumber: snap.data!,
            params: PdfViewerParams(
              backgroundColor: const Color(0xFF3A3A3E),
              pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
              onPageChanged: (n) async {
                if (n == null) return;
                final p = await SharedPreferences.getInstance();
                await p.setInt(_key, n);
              },
            ),
          );
        },
      ),
    );
  }
}
