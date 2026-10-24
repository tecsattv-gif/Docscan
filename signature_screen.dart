import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart' show Printing;
import 'common.dart';

/// Desenhar a assinatura com o dedo. Devolve um PNG transparente.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});
  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = [];

  Future<void> _done() async {
    final pts = _strokes.expand((s) => s).toList();
    if (pts.isEmpty) {
      toast(context, 'Desenhe sua assinatura primeiro');
      return;
    }
    var l = pts.first.dx, r = pts.first.dx, t = pts.first.dy, b = pts.first.dy;
    for (final p in pts) {
      if (p.dx < l) l = p.dx;
      if (p.dx > r) r = p.dx;
      if (p.dy < t) t = p.dy;
      if (p.dy > b) b = p.dy;
    }
    const pad = 10.0;
    final w = (r - l + pad * 2).ceil();
    final h = (b - t + pad * 2).ceil();
    const scale = 3.0;
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.scale(scale);
    canvas.translate(-l + pad, -t + pad);
    _paintStrokes(canvas, _strokes, Colors.black);
    final pic = rec.endRecording();
    final im = await pic.toImage((w * scale).ceil(), (h * scale).ceil());
    final data = await im.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || data == null) return;
    Navigator.pop(context, data.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sua assinatura'),
        actions: [
          IconButton(
              tooltip: 'Limpar',
              onPressed: () => setState(_strokes.clear),
              icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _done, child: const Text('Salvar')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('Assine com o dedo na área branca',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.white,
                child: GestureDetector(
                  onPanStart: (d) =>
                      setState(() => _strokes.add([d.localPosition])),
                  onPanUpdate: (d) =>
                      setState(() => _strokes.last.add(d.localPosition)),
                  child: CustomPaint(
                    painter: _InkPainter(_strokes),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

void _paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 3.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, 1.8, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
      continue;
    }
    final path = Path()..moveTo(s.first.dx, s.first.dy);
    for (var i = 1; i < s.length; i++) {
      path.lineTo(s[i].dx, s[i].dy);
    }
    canvas.drawPath(path, paint);
  }
}

class _InkPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _InkPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) =>
      _paintStrokes(canvas, strokes, Colors.black);
  @override
  bool shouldRepaint(covariant _InkPainter old) => true;
}

/// Escolher onde a assinatura vai na página. Devolve um mapa com
/// page, x, y, w (relativos).
class SignPlaceScreen extends StatefulWidget {
  final Uint8List pdf;
  final Uint8List signature;
  final int pageCount;
  const SignPlaceScreen(
      {super.key,
      required this.pdf,
      required this.signature,
      required this.pageCount});
  @override
  State<SignPlaceScreen> createState() => _SignPlaceScreenState();
}

class _SignPlaceScreenState extends State<SignPlaceScreen> {
  int _page = 0;
  Uint8List? _png;
  double _pw = 1, _ph = 1;
  double _x = 0.7, _y = 0.85, _w = 0.3;
  double _ar = 2;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final im = await decodeImageFromList(widget.signature);
    _ar = im.width / im.height;
    await _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() => _png = null);
    await for (final r
        in Printing.raster(widget.pdf, pages: [_page], dpi: 80)) {
      final png = await r.toPng();
      if (!mounted) return;
      setState(() {
        _png = png;
        _pw = r.width.toDouble();
        _ph = r.height.toDouble();
      });
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posicionar assinatura'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
                context, {'page': _page, 'x': _x, 'y': _y, 'w': _w, 'ar': _ar}),
            child: const Text('Aplicar'),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _png == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: AspectRatio(
                    aspectRatio: _pw / _ph,
                    child: LayoutBuilder(builder: (ctx, cons) {
                      final W = cons.maxWidth, H = cons.maxHeight;
                      final sw = _w * W;
                      final sh = sw / _ar;
                      return Stack(children: [
                        Positioned.fill(
                            child: Image.memory(_png!, fit: BoxFit.fill)),
                        Positioned(
                          left: _x * W - sw / 2,
                          top: _y * H - sh / 2,
                          width: sw,
                          height: sh,
                          child: GestureDetector(
                            onPanUpdate: (d) => setState(() {
                              _x = ((_x * W + d.delta.dx) / W).clamp(0.0, 1.0).toDouble();
                              _y = ((_y * H + d.delta.dy) / H).clamp(0.0, 1.0).toDouble();
                            }),
                            child: Container(
                              decoration: BoxDecoration(
                                  border: Border.all(color: kTeal, width: 1.5)),
                              child: Image.memory(widget.signature,
                                  fit: BoxFit.fill),
                            ),
                          ),
                        ),
                      ]);
                    }),
                  ),
                ),
        ),
        Container(
          color: kBg,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Text('Tamanho'),
                Expanded(
                  child: Slider(
                    value: _w,
                    min: 0.1,
                    max: 0.7,
                    onChanged: (v) => setState(() => _w = v),
                  ),
                ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  onPressed: _page > 0
                      ? () {
                          _page--;
                          _loadPage();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Página ${_page + 1} de ${widget.pageCount}'),
                IconButton(
                  onPressed: _page < widget.pageCount - 1
                      ? () {
                          _page++;
                          _loadPage();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ]),
              const Text('Arraste a assinatura para o lugar certo',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }
}
