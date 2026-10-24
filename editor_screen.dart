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
  bool _busy = false;
  String _mode = 'magic';
  Size? _imgSize;
  List<Offset> _c = _defaultCorners();

  static List<Offset> _defaultCorners() => const [
        Offset(0.06, 0.06),
        Offset(0.94, 0.06),
        Offset(0.94, 0.94),
        Offset(0.06, 0.94),
      ];

  static const _filters = <String, String>{
    'original': 'Original',
    'magic': 'Mágico',
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
    }
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
      _cropped = await compute(ImageOps.warp, {'bytes': _base, 'c': coords});
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
        _c = _defaultCorners();
        await _loadSize();
        if (mounted) setState(() => _busy = false);
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
    return Center(
      child: AspectRatio(
        aspectRatio: size.width / size.height,
        child: LayoutBuilder(builder: (ctx, cons) {
          final w = cons.maxWidth, h = cons.maxHeight;
          Offset px(Offset n) => Offset(n.dx * w, n.dy * h);
          return Stack(children: [
            Positioned.fill(
                child: Image.memory(_base, fit: BoxFit.fill, gaplessPlayback: true)),
            Positioned.fill(
                child: CustomPaint(painter: _QuadPainter(_c.map(px).toList()))),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: px(_c[i]).dx - 24,
                top: px(_c[i]).dy - 24,
                width: 48,
                height: 48,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) {
                    setState(() {
                      _c[i] = Offset(
                        ((_c[i].dx * w + d.delta.dx) / w).clamp(0.0, 1.0).toDouble(),
                        ((_c[i].dy * h + d.delta.dy) / h).clamp(0.0, 1.0).toDouble(),
                      );
                    });
                  },
                  child: Center(
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: kTeal,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    );
  }

  Widget _cropBar() {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Arraste os 4 pontos até os cantos do documento',
          style: TextStyle(color: Colors.white70, fontSize: 13)),
      const SizedBox(height: 10),
      Row(children: [
        IconButton(
            tooltip: 'Girar',
            onPressed: _busy ? null : _rotate,
            icon: const Icon(Icons.rotate_right)),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() => _c = const [
                    Offset(0, 0),
                    Offset(1, 0),
                    Offset(1, 1),
                    Offset(0, 1),
                  ]),
          child: const Text('Imagem inteira'),
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
