import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart' show Printing;
import '../services/doc_store.dart';
import '../services/pdf_tools.dart';
import 'common.dart';
import 'viewer_screen.dart';

/// Organizar páginas: reordenar (segure e arraste), girar, excluir e extrair.
class PageManagerScreen extends StatefulWidget {
  final File file;
  const PageManagerScreen({super.key, required this.file});
  @override
  State<PageManagerScreen> createState() => _PageManagerScreenState();
}

class _PageManagerScreenState extends State<PageManagerScreen> {
  Uint8List? _bytes;
  final List<Uint8List> _thumbs = [];
  List<int> _order = [];
  final Set<int> _sel = {};
  // Giro de cada página original, em graus (0, 90, 180, 270).
  final Map<int, int> _rot = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _bytes = await widget.file.readAsBytes();
      await for (final r in Printing.raster(_bytes!, dpi: 30)) {
        _thumbs.add(await r.toPng());
        if (mounted) setState(() {});
      }
      _order = List<int>.generate(_thumbs.length, (i) => i);
    } catch (e) {
      if (mounted) toast(context, 'Erro ao abrir: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(List<int> pages, String suffix) async {
    if (pages.isEmpty) {
      toast(context, 'Nenhuma página');
      return;
    }
    final name = await askText(context, 'Nome do novo documento',
        initial: '${docName(widget.file)} $suffix');
    if (name == null || name.isEmpty || !mounted) return;
    final f = await Busy.run<File>(context, 'Gerando PDF...', () async {
      final out = await compute(PdfTools.pick, {
        'pdf': _bytes!,
        'pages': pages,
        'rot': [for (final p in pages) _rot[p] ?? 0],
      });
      return DocStore.saveBytes(out, name);
    });
    if (f == null || !mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Organizar páginas'),
        actions: [
          if (_order.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (_sel.length == _order.length) {
                  _sel.clear();
                } else {
                  _sel
                    ..clear()
                    ..addAll(_order);
                }
              }),
              child: Text(_sel.length == _order.length ? 'Desmarcar' : 'Marcar todas'),
            ),
          if (_sel.isNotEmpty)
            IconButton(
              tooltip: 'Girar marcadas',
              icon: const Icon(Icons.rotate_right),
              onPressed: () => setState(() {
                for (final o in _sel) {
                  _rot[o] = ((_rot[o] ?? 0) + 90) % 360;
                }
              }),
            ),
        ],
      ),
      body: _loading && _thumbs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                    'Segure e arraste para mudar a ordem. Toque em ↻ para girar. Marque para extrair.',
                    style: TextStyle(color: context.muted, fontSize: 13)),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: _order.length,
                  onReorder: (a, b) {
                    setState(() {
                      if (b > a) b--;
                      final v = _order.removeAt(a);
                      _order.insert(b, v);
                    });
                  },
                  itemBuilder: (ctx, i) {
                    final o = _order[i];
                    return ListTile(
                      key: ValueKey(o),
                      leading: Container(
                        color: Colors.white,
                        width: 48,
                        child: RotatedBox(
                          quarterTurns: (_rot[o] ?? 0) ~/ 90,
                          child: Image.memory(_thumbs[o], fit: BoxFit.cover),
                        ),
                      ),
                      title: Text('Página ${i + 1}'),
                      subtitle: Text((_rot[o] ?? 0) == 0
                          ? 'Original: ${o + 1}'
                          : 'Original: ${o + 1} · girada ${_rot[o]}°'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Girar',
                          icon: const Icon(Icons.rotate_right),
                          onPressed: () => setState(
                              () => _rot[o] = ((_rot[o] ?? 0) + 90) % 360),
                        ),
                        Checkbox(
                          value: _sel.contains(o),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _sel.add(o);
                            } else {
                              _sel.remove(o);
                            }
                          }),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() {
                            _order.removeAt(i);
                            _sel.remove(o);
                          }),
                        ),
                      ]),
                    );
                  },
                ),
              ),
              Container(
                color: context.bar,
                padding: const EdgeInsets.all(12),
                child: SafeArea(
                  top: false,
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sel.isEmpty
                            ? null
                            : () => _save(
                                _order.where(_sel.contains).toList(), '(extraído)'),
                        child: Text('Extrair (${_sel.length})'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _save(List<int>.from(_order), '(editado)'),
                        child: const Text('Salvar como novo'),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}
