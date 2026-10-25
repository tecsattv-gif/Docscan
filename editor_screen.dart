import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/image_ops.dart';
import 'common.dart';

/// Recorte (4 cantos), correção de perspectiva, filtros e giro.
class EditorScreen extends StatefulWidget {
  final Uint8List bytes;
  final bool startWithCrop;
  const EditorScreen({super.key, required this.bytes, this.startWithCrop = true});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late Uint8List _base;
  Uint8List? _cropped;
  Uint8List? _shown;
  bool _crop = true;
  // lembra a escolha enquanto o app estiver aberto
  static bool _curved = false;
  bool _busy = false;
  String _mode = 'magic';
  Size? _imgSize;
  List<Offset> _c = _defaultCorners();

  // lista modificável (uma lista const impedia arrastar os pontos)
  static List<Offset> _defaultCorners() => [
        const Offset(0.06, 0.06),
        const Offset(0.94, 0.06),
        const Offset(0.94, 0.94),
        const Offset(0.06, 0.94),
      ];

  static const _filters = <String, String>{
    'original': 'Original',
    'magic': 'Mágico',
    'flatten': 'Desamassar',
    'bw': 'P&B',
    'gray': 'Cinza',
    'enhance': 'Realçar',
  };

  @override
  void initState() {
    super.initState();
    _base = widget.bytes;
    _crop = widget.startWithCrop;
    _loadSize();
    if (!_crop) {
      _cropped = _base;
      _applyFilter();
    } else {
      _detect();
    }
  }

  /// Procura os cantos do documento automaticamente.
  Future<void> _detect({bool warn = false}) async {
    setState(() => _busy = true);
    try {
      final r = await compute(ImageOps.detectCorners, _base);
      if (!mounted) return;
      if (r.length == 8) {
        _c = [
          for (var i = 0; i < 4; i++) Offset(r[i * 2], r[i * 2 + 1]),
        ];
      } else {
        _c = _defaultCorners();
        if (warn) toast(context, 'Bordas não encontradas. Ajuste os pontos.');
      }
    } catch (_) {
      _c = _defaultCorners();
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _loadSize() async {
    final im = await decodeImageFromList(_base);
    if (!mounted) return;
    setState(() => _imgSize = Size(im.width.toDouble(), im.height.toDouble()));
  }

  Future<void> _applyCrop() async {
    setState(() => _busy = true);
    try {
      final coords = <double>[];
      for (final o in _c) {
        coords.add(o.dx);
        coords.add(o.dy);
      }
      _cropped = await compute(_curved ? ImageOps.warpCurved : ImageOps.warp,
          {'bytes': _base, 'c': coords});
      _crop = false;
      await _applyFilter();
    } catch (e) {
      if (mounted) toast(context, 'Erro ao recortar: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyFilter() async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final src = _cropped ?? _base;
      _shown = _mode == 'original'
          ? src
          : await compute(ImageOps.filter, {'bytes': src, 'mode': _mode});
    } catch (e) {
      if (mounted) toast(context, 'Erro no filtro: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _rotate() async {
    setState(() => _busy = true);
    try {
      if (_crop) {
        _base = await compute(ImageOps.rotate, {'bytes': _base, 'angle': 90});
        await _loadSize();
        await _detect();
      } else {
        _cropped = await compute(
            ImageOps.rotate, {'bytes': _cropped ?? _base, 'angle': 90});
        await _applyFilter();
      }
    } catch (e) {
      if (mounted) toast(context, 'Erro: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _cropView() {
    final size = _imgSize;
    if (size == null) return const Center(child: CircularProgressIndicator());
    return LayoutBuilder(builder: (ctx, cons) {
      // margem para os pontos dos cantos poderem ser arrastados
      const pad = 26.0;
      final aw = cons.maxWidth - 2 * pad, ah = cons.maxHeight - 2 * pad;
      final ar = size.width / size.height;
      var w = aw, h = aw / ar;
      if (h > ah) {
        h = ah;
        w = ah * ar;
      }
      final ox = (cons.maxWidth - w) / 2, oy = (cons.maxHeight - h) / 2;
      Offset px(Offset n) => Offset(ox + n.dx * w, oy + n.dy * h);
      return Stack(children: [
        Positioned(
            left: ox,
            top: oy,
            width: w,
            height: h,
            child: Image.memory(_base, fit: BoxFit.fill, gaplessPlayback: true)),
        Positioned.fill(
            child: CustomPaint(painter: _QuadPainter(_c.map(px).toList()))),
        for (var i = 0; i < 4; i++)
          Positioned(
            left: px(_c[i]).dx - 26,
            top: px(_c[i]).dy - 26,
            width: 52,
            height: 52,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) {
                setState(() {
                  _c[i] = Offset(
                    (_c[i].dx + d.delta.dx / w).clamp(0.0, 1.0).toDouble(),
                    (_c[i].dy + d.delta.dy / h).clamp(0.0, 1.0).toDouble(),
                  );
                });
              },
              child: Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: kTeal.withOpacity(0.35),
                    shape: BoxShape.circle,
                    border: Border.all(color: kTeal, width: 3),
                  ),
                ),
              ),
            ),
          ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    // O editor de imagem fica sempre escuro, como em apps de câmera.
    return Theme(
      data: appTheme(Brightness.dark),
      child: Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: kBg,
        title: Text(_crop ? 'Ajustar bordas' : 'Filtros'),
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        actions: [
          if (!_crop)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => Navigator.pop(context, _shown ?? _cropped ?? _base),
              icon: const Icon(Icons.check),
              label: const Text('Concluir'),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: _crop
                  ? _cropView()
                  : (_shown == null
                      ? const SizedBox()
                      : InteractiveViewer(
                          child: Image.memory(_shown!,
                              fit: BoxFit.contain, gaplessPlayback: true))),
            ),
            if (_busy)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
          ]),
        ),
        Container(
          color: kBg,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: SafeArea(
            top: false,
            child: _crop ? _cropBar() : _filterBar(),
          ),
        ),
      ]),
      ),
    );
  }

  Widget _cropBar() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        const Expanded(
          child: Text('Arraste os 4 pontos até os cantos do documento',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        FilterChip(
          label: const Text('Esticar folha torta'),
          tooltip: 'Segue as bordas tortas do papel e estica a folha',
          selected: _curved,
          onSelected: _busy ? null : (v) => setState(() => _curved = v),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        IconButton(
            tooltip: 'Girar',
            onPressed: _busy ? null : _rotate,
            icon: const Icon(Icons.rotate_right)),
        TextButton(
          onPressed: _busy ? null : () => _detect(warn: true),
          child: const Text('Auto'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _c = [
                    const Offset(0, 0),
                    const Offset(1, 0),
                    const Offset(1, 1),
                    const Offset(0, 1),
                  ]),
          child: const Text('Inteira'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _busy ? null : _applyCrop,
          icon: const Icon(Icons.crop),
          label: const Text('Recortar'),
        ),
      ]),
    ]);
  }

  Widget _filterBar() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final e in _filters.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.value),
                  selected: _mode == e.key,
                  onSelected: _busy
                      ? null
                      : (_) {
                          setState(() => _mode = e.key);
                          _applyFilter();
                        },
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        IconButton(
            tooltip: 'Girar',
            onPressed: _busy ? null : _rotate,
            icon: const Icon(Icons.rotate_right)),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() {
                    _crop = true;
                    _loadSize();
                  }),
          icon: const Icon(Icons.crop),
          label: const Text('Refazer recorte'),
        ),
      ]),
    ]);
  }
}

class _QuadPainter extends CustomPainter {
  final List<Offset> pts;
  _QuadPainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < 4; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = kTeal.withOpacity(0.18));
    canvas.drawPath(
        path,
        Paint()
          ..color = kTeal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) => true;
}
