import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:printing/printing.dart' show Printing;
import 'common.dart';

/// Gera um PNG transparente com um texto (para marca d'água).
Future<Uint8List> textPng(String text,
    {Color color = const Color(0xFF787878), bool bold = true}) async {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: 120,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
    textDirection: TextDirection.ltr,
  )..layout();
  const pad = 16.0;
  final w = tp.width + pad * 2, h = tp.height + pad * 2;
  final rec = ui.PictureRecorder();
  tp.paint(Canvas(rec), const Offset(pad, pad));
  final im = await rec.endRecording().toImage(w.ceil(), h.ceil());
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// Gera o PNG do carimbo: texto vermelho numa caixa branca com borda vermelha.
Future<Uint8List> stampPng(String text) async {
  const red = Color(0xFFC81E1E);
  const fs = 90.0;
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: const TextStyle(
            color: red, fontSize: fs, fontWeight: FontWeight.w700)),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = tp.width + fs * 1.4, h = tp.height + fs * 0.9;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final box = Rect.fromLTWH(6, 6, w - 12, h - 12);
  c.drawRect(box, Paint()..color = Colors.white);
  c.drawRect(
      box,
      Paint()
        ..color = red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10);
  tp.paint(c, Offset((w - tp.width) / 2, (h - tp.height) / 2));
  final im = await rec.endRecording().toImage(w.ceil(), h.ceil());
  final bd = await im.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// Tela para posicionar carimbo / marca d'água na página:
/// arrastar, tamanho, transparência e "todas as páginas".
/// Devolve {page, all, x, y, w, ar, opacity, angle}
/// (x, y = centro relativo; w = largura relativa; angle em graus).
class PlaceScreen extends StatefulWidget {
  final String title;
  final Uint8List pdf;
  final Uint8List overlay;
  final int pageCount;
  final double x, y, w, opacity;
  final bool diagonal;
  const PlaceScreen({
    super.key,
    required this.title,
    required this.pdf,
    required this.overlay,
    required this.pageCount,
    this.x = 0.5,
    this.y = 0.5,
    this.w = 0.3,
    this.opacity = 1.0,
    this.diagonal = false,
  });
  @override
  State<PlaceScreen> createState() => _PlaceScreenState();
}

class _PlaceScreenState extends State<PlaceScreen> {
  int _page = 0;
  Uint8List? _png;
  double _pw = 1, _ph = 1, _ar = 2;
  late double _x = widget.x, _y = widget.y, _w = widget.w;
  late double _op = widget.opacity;
  late bool _diag = widget.diagonal;
  bool _all = true;

  /// Ângulo da diagonal da página (de baixo-esquerda para cima-direita).
  double get _angleRad => _diag ? -math.atan2(_ph, _pw) : 0.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final im = await decodeImageFromList(widget.overlay);
    _ar = im.width / math.max(im.height, 1);
    await _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() => _png = null);
    await for (final r in Printing.raster(widget.pdf, pages: [_page], dpi: 80)) {
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

  void _apply() {
    Navigator.pop(context, {
      'page': _page,
      'all': _all,
      'x': _x,
      'y': _y,
      'w': _w,
      'ar': _ar,
      'opacity': _op,
      'angle': _angleRad * 180 / math.pi,
    });
  }

  /// Atalhos para os cantos e o centro.
  void _snap(double x, double y) => setState(() {
        final m = _w / 2 + 0.03;
        _x = x < 0.5 ? m : (x > 0.5 ? 1 - m : 0.5);
        final hh = _w * (_pw / _ph) / _ar / 2 + 0.03;
        _y = y < 0.5 ? hh : (y > 0.5 ? 1 - hh : 0.5);
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(onPressed: _apply, child: const Text('Aplicar')),
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
                      return Stack(clipBehavior: Clip.hardEdge, children: [
                        Positioned.fill(
                            child: Image.memory(_png!, fit: BoxFit.fill)),
                        Positioned(
                          left: _x * W - sw / 2,
                          top: _y * H - sh / 2,
                          width: sw,
                          height: sh,
                          child: GestureDetector(
                            onPanUpdate: (d) => setState(() {
                              _x = ((_x * W + d.delta.dx) / W)
                                  .clamp(0.0, 1.0)
                                  .toDouble();
                              _y = ((_y * H + d.delta.dy) / H)
                                  .clamp(0.0, 1.0)
                                  .toDouble();
                            }),
                            child: Transform.rotate(
                              angle: _angleRad,
                              child: Container(
                                decoration: BoxDecoration(
                                    border:
                                        Border.all(color: kTeal, width: 1.5)),
                                child: Opacity(
                                  opacity: _op,
                                  child: Image.memory(widget.overlay,
                                      fit: BoxFit.fill),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]);
                    }),
                  ),
                ),
        ),
        Container(
          color: context.bar,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const SizedBox(width: 100, child: Text('Tamanho')),
                Expanded(
                  child: Slider(
                    value: _w,
                    min: 0.05,
                    max: 1.0,
                    onChanged: (v) => setState(() => _w = v),
                  ),
                ),
              ]),
              Row(children: [
                SizedBox(
                    width: 100,
                    child: Text('Opacidade ${(_op * 100).round()}%')),
                Expanded(
                  child: Slider(
                    value: _op,
                    min: 0.1,
                    max: 1.0,
                    divisions: 18,
                    onChanged: (v) => setState(() => _op = v),
                  ),
                ),
              ]),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  _chip('↖', () => _snap(0, 0)),
                  _chip('↗', () => _snap(1, 0)),
                  _chip('Centro', () => _snap(0.5, 0.5)),
                  _chip('↙', () => _snap(0, 1)),
                  _chip('↘', () => _snap(1, 1)),
                  FilterChip(
                    label: const Text('Diagonal'),
                    selected: _diag,
                    onSelected: (v) => setState(() => _diag = v),
                  ),
                ],
              ),
              Row(children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Todas as páginas'),
                    value: _all,
                    onChanged: widget.pageCount > 1
                        ? (v) => setState(() => _all = v)
                        : null,
                  ),
                ),
                IconButton(
                  onPressed: _page > 0
                      ? () {
                          _page--;
                          _loadPage();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_page + 1}/${widget.pageCount}'),
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
              Text('Arraste para o lugar certo',
                  style: TextStyle(color: context.muted, fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _chip(String label, VoidCallback onTap) =>
      ActionChip(label: Text(label), onPressed: onTap);
}
