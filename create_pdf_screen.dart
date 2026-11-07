import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/doc_store.dart';
import 'common.dart';
import 'viewer_screen.dart';

/// Ferramenta "Criar PDF": escreve título, texto com formatação (como no
/// Word: negrito, itálico, sublinhado, tamanho, fonte, cor, alinhamento,
/// listas e recuo), junta fotos e gera o PDF no tamanho e orientação
/// escolhidos. Sem texto nem fotos = página em branco.
class CreatePdfScreen extends StatefulWidget {
  const CreatePdfScreen({super.key});
  @override
  State<CreatePdfScreen> createState() => _CreatePdfScreenState();
}

class _CreatePdfScreenState extends State<CreatePdfScreen> {
  final _name = TextEditingController(
      text: 'Documento ${DateFormat('dd-MM-yyyy HH-mm').format(DateTime.now())}');
  final _title = TextEditingController();
  final _body = q.QuillController.basic();
  bool _fullscreen = false;
  StreamSubscription<dynamic>? _bodySub;
  final _images = <Uint8List>[];
  final _picker = ImagePicker();

  // Só os tamanhos de papel (sem "Tamanho da foto").
  int _size = 0;
  bool _landscape = false;
  double _fontSize = 12;
  bool _margins = true;
  int _blankPages = 1;

  // Alinhamento do título: 0 = esquerda, 1 = centro, 2 = direita.
  int _titleAlign = 0;

  // Fotos: em páginas separadas ou junto ao texto, posição (grade 3x3,
  // 0 = topo-esquerda ... 4 = centro ... 8 = base-direita) e tamanho.
  bool _imgSeparate = true;
  int _imgPos = 4;
  double _imgScale = 1.0;

  static const _pdfAligns = [
    pw.Alignment.topLeft, pw.Alignment.topCenter, pw.Alignment.topRight,
    pw.Alignment.centerLeft, pw.Alignment.center, pw.Alignment.centerRight,
    pw.Alignment.bottomLeft, pw.Alignment.bottomCenter, pw.Alignment.bottomRight,
  ];
  static const _rowAligns = [
    pw.Alignment.centerLeft, pw.Alignment.center, pw.Alignment.centerRight,
  ];
  static const _textAligns = [
    pw.TextAlign.left, pw.TextAlign.center, pw.TextAlign.right,
  ];

  int get _paperCount => DocStore.pageSizeNames.length - 1;

  bool get _bodyEmpty => _body.document.toPlainText().trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _bodySub = _body.document.changes.listen((_) {
      if (mounted) setState(() {});
    });
    DocStore.lastPageSize().then((i) {
      if (mounted && i < _paperCount) setState(() => _size = i);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _bodySub?.cancel();
    _body.dispose();
    super.dispose();
  }

  /// Fonte completa (DejaVu), em assets/fonts. Se não existir, volta à
  /// fonte padrão do PDF.
  static pw.ThemeData? _fontTheme;
  static bool _fontTried = false;
  static Future<pw.ThemeData?> _loadFont() async {
    if (_fontTried) return _fontTheme;
    _fontTried = true;
    Future<pw.Font?> f(String n) async {
      try {
        return pw.Font.ttf(await rootBundle.load('assets/fonts/$n'));
      } catch (_) {
        return null;
      }
    }

    final base = await f('DejaVuSans.ttf');
    if (base == null) return _fontTheme = null;
    final bold = await f('DejaVuSans-Bold.ttf');
    final italic = await f('DejaVuSans-Oblique.ttf');
    final boldItalic = await f('DejaVuSans-BoldOblique.ttf');
    return _fontTheme = pw.ThemeData.withFont(
        base: base, bold: bold, italic: italic, boldItalic: boldItalic);
  }

  /// Com a fonte completa só tira emojis (ela não tem); sem ela, a fonte
  /// padrão do PDF só tem caracteres latinos, então troca o resto.
  static String _clean(String s, bool fullFont) {
    if (!fullFont) return _safe(s);
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r == 9) {
        b.write('    ');
      } else if (r == 10 || (r >= 32 && r <= 0xFFFF && (r < 0xD800 || r > 0xDFFF))) {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// As fontes padrão do PDF só têm caracteres latinos; troca os símbolos
  /// mais comuns e substitui o resto para não dar erro.
  static String _safe(String s) {
    const map = {
      '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-',
      '…': '...', '•': '·', '€': 'EUR', '\t': '    ',
    };
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (map.containsKey(ch)) {
        b.write(map[ch]);
      } else if (r == 10 || (r >= 32 && r <= 126) || (r >= 160 && r <= 255)) {
        b.write(ch);
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  // ---------- Texto formatado -> PDF ----------

  /// Lê o texto do editor (formato Delta: trechos com estilos e, em cada
  /// fim de linha, o estilo do parágrafo) e monta os blocos do PDF.
  List<pw.Widget> _richBody(bool full) {
    final out = <pw.Widget>[];
    var spans = <pw.InlineSpan>[];
    final counters = <int, int>{}; // numeração das listas, por recuo

    void endLine(Map<String, dynamic>? a) {
      final align = a?['align'];
      final list = a?['list'];
      final header = a?['header'];
      final indent = (a?['indent'] as num?)?.toInt() ?? 0;
      final textAlign = switch (align) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        'justify' => pw.TextAlign.justify,
        _ => pw.TextAlign.left,
      };
      final scale = switch (header) { 1 => 1.6, 2 => 1.35, 3 => 1.15, _ => 1.0 };
      final lineStyle = pw.TextStyle(
        fontSize: _fontSize * scale,
        lineSpacing: 2,
        fontWeight: header != null ? pw.FontWeight.bold : null,
      );
      final content = spans.isEmpty ? <pw.InlineSpan>[const pw.TextSpan(text: ' ')] : spans;
      final text = pw.RichText(
        textAlign: textAlign,
        text: pw.TextSpan(style: lineStyle, children: content),
      );

      String? marker;
      if (list == 'ordered') {
        counters.removeWhere((k, _) => k > indent);
        final n = (counters[indent] ?? 0) + 1;
        counters[indent] = n;
        marker = '$n.';
      } else {
        counters.clear();
        if (list == 'bullet') marker = full ? '•' : '-';
      }

      final left = indent * 18.0;
      if (marker != null) {
        out.add(pw.Padding(
          padding: pw.EdgeInsets.only(left: left, bottom: 4),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 20, child: pw.Text(marker, style: lineStyle)),
            pw.Expanded(child: text),
          ]),
        ));
      } else if (left > 0) {
        out.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: left, bottom: 4), child: text));
      } else {
        // Sem recuo vai direto, para um parágrafo longo poder passar de página.
        out.add(text);
        out.add(pw.SizedBox(height: 4));
      }
      spans = <pw.InlineSpan>[];
    }

    for (final op in _body.document.toDelta().toList()) {
      if (!op.isInsert) continue;
      final data = op.data;
      if (data is! String) continue; // imagens embutidas não são usadas
      final attrs = op.attributes ?? const <String, dynamic>{};
      final parts = data.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) spans.add(_span(parts[i], attrs, full));
        if (i < parts.length - 1) endLine(attrs);
      }
    }
    if (spans.isNotEmpty) endLine(null);

    // O editor sempre termina com uma linha vazia: tira as do fim.
    while (out.isNotEmpty) {
      final last = out.last;
      if (last is pw.SizedBox) {
        out.removeLast();
        continue;
      }
      if (last is pw.RichText && _isBlank(last)) {
        out.removeLast();
        continue;
      }
      break;
    }
    return out;
  }

  static bool _isBlank(pw.RichText t) {
    final root = t.text;
    if (root is! pw.TextSpan) return false;
    final kids = root.children ?? const [];
    return kids.every((k) => k is pw.TextSpan && (k.text ?? '').trim().isEmpty);
  }

  /// Um trecho de texto com negrito, itálico, sublinhado, tamanho, fonte e cor.
  pw.TextSpan _span(String text, Map<String, dynamic> a, bool full) {
    final serif = a['font'] == 'serif';
    final deco = <pw.TextDecoration>[
      if (a['underline'] == true) pw.TextDecoration.underline,
      if (a['strike'] == true) pw.TextDecoration.lineThrough,
    ];
    return pw.TextSpan(
      text: serif ? _safe(text) : _clean(text, full),
      style: pw.TextStyle(
        fontWeight: a['bold'] == true ? pw.FontWeight.bold : null,
        fontStyle: a['italic'] == true ? pw.FontStyle.italic : null,
        fontSize: _sizeOf(a['size']),
        decoration: deco.isEmpty ? null : pw.TextDecoration.combine(deco),
        color: _colorOf(a['color']),
        // "Times" usa a fonte serifada própria do PDF (não aumenta o arquivo).
        font: serif ? _times : null,
        fontNormal: serif ? _times : null,
        fontBold: serif ? _timesBold : null,
        fontItalic: serif ? _timesItalic : null,
        fontBoldItalic: serif ? _timesBoldItalic : null,
      ),
    );
  }

  static final _times = pw.Font.times();
  static final _timesBold = pw.Font.timesBold();
  static final _timesItalic = pw.Font.timesItalic();
  static final _timesBoldItalic = pw.Font.timesBoldItalic();

  double? _sizeOf(dynamic v) {
    switch (v) {
      case null:
        return null;
      case 'small':
        return _fontSize * 0.8;
      case 'large':
        return _fontSize * 1.35;
      case 'huge':
        return _fontSize * 1.8;
    }
    final n = double.tryParse(v.toString());
    return (n == null || n <= 0) ? null : n;
  }

  static PdfColor? _colorOf(dynamic v) {
    if (v is! String) return null;
    var h = v.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final x = int.tryParse(h, radix: 16);
    return x == null ? null : PdfColor.fromInt(x);
  }


  Future<void> _addImages() async {
    final xs = await _picker.pickMultiImage(imageQuality: 90);
    if (xs.isEmpty) return;
    final bytes = <Uint8List>[];
    for (final x in xs) {
      bytes.add(await x.readAsBytes());
    }
    if (mounted) setState(() => _images.addAll(bytes));
  }

  Future<File> _build() async {
    final base = DocStore.pageFormatAt(_size);
    final fmt = _landscape ? base.landscape : base.portrait;
    final margin = _margins ? 2.0 * PdfPageFormat.cm : 0.5 * PdfPageFormat.cm;
    final theme = await _loadFont();
    final full = theme != null;
    final doc = pw.Document(theme: theme);
    final title = _clean(_title.text.trim(), full);
    final bodyWidgets = _bodyEmpty ? <pw.Widget>[] : _richBody(full);

    if (title.isEmpty && bodyWidgets.isEmpty && _images.isEmpty) {
      for (var i = 0; i < _blankPages; i++) {
        doc.addPage(pw.Page(pageFormat: fmt, build: (_) => pw.SizedBox()));
      }
    } else {
      // Área útil da página (sem as margens).
      final usableW = fmt.width - 2 * margin;
      final usableH = fmt.height - 2 * margin;
      final hasText = title.isNotEmpty || bodyWidgets.isNotEmpty;
      final flow = !_imgSeparate && _images.isNotEmpty;

      if (hasText || flow) {
        doc.addPage(pw.MultiPage(
          pageFormat: fmt,
          margin: pw.EdgeInsets.all(margin),
          build: (_) => [
            if (title.isNotEmpty)
              pw.Container(
                width: double.infinity,
                alignment: _rowAligns[_titleAlign],
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: pw.Text(title,
                    textAlign: _textAligns[_titleAlign],
                    style: pw.TextStyle(
                        fontSize: _fontSize * 1.7,
                        fontWeight: pw.FontWeight.bold)),
              ),
            // Texto formatado, um bloco por parágrafo.
            ...bodyWidgets,
            // Fotos junto ao texto: alinhadas à esquerda, centro ou direita.
            if (flow)
              for (final b in _images)
                pw.Container(
                  width: double.infinity,
                  alignment: _rowAligns[_imgPos % 3],
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.ConstrainedBox(
                    constraints: pw.BoxConstraints(
                        maxWidth: usableW * _imgScale,
                        maxHeight: (usableH - 20) * _imgScale),
                    child: pw.Image(pw.MemoryImage(b), fit: pw.BoxFit.contain),
                  ),
                ),
          ],
        ));
      }
      if (!flow) {
        // Uma foto por página, na posição e no tamanho escolhidos.
        final align = _pdfAligns[_imgPos];
        for (final b in _images) {
          final im = pw.MemoryImage(b);
          doc.addPage(pw.Page(
            pageFormat: fmt,
            margin: pw.EdgeInsets.all(margin),
            build: (_) => pw.Align(
              alignment: align,
              child: pw.SizedBox(
                width: usableW * _imgScale,
                height: usableH * _imgScale,
                child: pw.Image(im, fit: pw.BoxFit.contain, alignment: align),
              ),
            ),
          ));
        }
      }
    }
    final name = _name.text.trim().isEmpty ? 'Documento' : _name.text.trim();
    return DocStore.saveBytes(await doc.save(), name);
  }

  Future<void> _openFullscreen() async {
    FocusScope.of(context).unfocus();
    setState(() => _fullscreen = true);
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => _FullEditor(controller: _body)));
    if (mounted) setState(() => _fullscreen = false);
  }

  Future<void> _create() async {
    FocusScope.of(context).unfocus();
    await DocStore.setPageSize(_size);
    if (!mounted) return;
    final f = await Busy.run<File>(context, 'Criando PDF...', _build);
    if (f == null || !mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
  }

  @override
  Widget build(BuildContext context) {
    final empty = _title.text.trim().isEmpty &&
        _bodyEmpty &&
        _images.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Criar PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'Nome do arquivo', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
                labelText: 'Título (opcional)', border: OutlineInputBorder()),
          ),
          if (_title.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Text('Alinhar título'),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        icon: Icon(Icons.format_align_left),
                        tooltip: 'Esquerda'),
                    ButtonSegment(
                        value: 1,
                        icon: Icon(Icons.format_align_center),
                        tooltip: 'Centro'),
                    ButtonSegment(
                        value: 2,
                        icon: Icon(Icons.format_align_right),
                        tooltip: 'Direita'),
                  ],
                  selected: {_titleAlign},
                  onSelectionChanged: (s) =>
                      setState(() => _titleAlign = s.first),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          _fullscreen
              ? OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Editando em tela cheia...'),
                )
              : _EditorBox(
                  controller: _body,
                  onFullscreen: _openFullscreen,
                ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Adicionar fotos'),
            ),
            const SizedBox(width: 12),
            if (_images.isNotEmpty)
              Expanded(
                child: Text(
                    '${_images.length} foto(s) — '
                    '${_imgSeparate ? 'uma por página' : 'junto ao texto'}',
                    style: const TextStyle(fontSize: 13)),
              ),
          ]),
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(_images[i],
                        width: 64, height: 84, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 14, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: true,
                    label: Text('Uma por página'),
                    icon: Icon(Icons.filter_none)),
                ButtonSegment(
                    value: false,
                    label: Text('Junto ao texto'),
                    icon: Icon(Icons.wrap_text)),
              ],
              selected: {_imgSeparate},
              onSelectionChanged: (s) =>
                  setState(() => _imgSeparate = s.first),
            ),
            const SizedBox(height: 12),
            Text(
                _imgSeparate
                    ? 'Posição da foto na página'
                    : 'Alinhamento da foto',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Center(
              child: _imgSeparate
                  ? _PositionPicker(
                      selected: _imgPos,
                      landscape: _landscape,
                      onChanged: (p) => setState(() => _imgPos = p))
                  : SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                            value: 0,
                            icon: Icon(Icons.align_horizontal_left),
                            label: Text('Esquerda')),
                        ButtonSegment(
                            value: 1,
                            icon: Icon(Icons.align_horizontal_center),
                            label: Text('Centro')),
                        ButtonSegment(
                            value: 2,
                            icon: Icon(Icons.align_horizontal_right),
                            label: Text('Direita')),
                      ],
                      selected: {_imgPos % 3},
                      onSelectionChanged: (s) =>
                          setState(() => _imgPos = 3 + s.first),
                    ),
            ),
            Row(children: [
              const Text('Tamanho da foto'),
              Expanded(
                child: Slider(
                  value: _imgScale,
                  min: 0.2,
                  max: 1.0,
                  divisions: 16,
                  label: '${(_imgScale * 100).round()}%',
                  activeColor: kTeal,
                  onChanged: (v) => setState(() => _imgScale = v),
                ),
              ),
              Text('${(_imgScale * 100).round()}%'),
            ]),
          ],
          const Divider(height: 32),
          DropdownButtonFormField<int>(
            value: _size,
            decoration: const InputDecoration(
                labelText: 'Tamanho do papel', border: OutlineInputBorder()),
            items: [
              for (var i = 0; i < _paperCount; i++)
                DropdownMenuItem(value: i, child: Text(DocStore.pageSizeNames[i])),
            ],
            onChanged: (v) => setState(() => _size = v ?? 0),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('Retrato'),
                  icon: Icon(Icons.crop_portrait)),
              ButtonSegment(
                  value: true,
                  label: Text('Paisagem'),
                  icon: Icon(Icons.crop_landscape)),
            ],
            selected: {_landscape},
            onSelectionChanged: (s) => setState(() => _landscape = s.first),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Tamanho da letra'),
            Expanded(
              child: Slider(
                value: _fontSize,
                min: 8,
                max: 24,
                divisions: 16,
                label: _fontSize.round().toString(),
                activeColor: kTeal,
                onChanged: (v) => setState(() => _fontSize = v),
              ),
            ),
            Text('${_fontSize.round()}'),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Margens normais (2 cm)'),
            value: _margins,
            activeColor: kTeal,
            onChanged: (v) => setState(() => _margins = v),
          ),
          if (empty)
            Row(children: [
              const Expanded(
                  child: Text('Sem texto nem fotos: criar páginas em branco')),
              IconButton(
                  onPressed: _blankPages > 1
                      ? () => setState(() => _blankPages--)
                      : null,
                  icon: const Icon(Icons.remove)),
              Text('$_blankPages'),
              IconButton(
                  onPressed: _blankPages < 50
                      ? () => setState(() => _blankPages++)
                      : null,
                  icon: const Icon(Icons.add)),
            ]),
        ],
      ),
      // Botão fixo embaixo, acima da barra de navegação do Android.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: kTeal,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _create,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(empty ? 'Criar PDF em branco' : 'Criar PDF'),
          ),
        ),
      ),
    );
  }
}

/// Desenho de uma folha com 9 pontos (3x3): toque onde a foto deve ficar.
class _PositionPicker extends StatelessWidget {
  const _PositionPicker(
      {required this.selected, required this.landscape, required this.onChanged});
  final int selected;
  final bool landscape;
  final ValueChanged<int> onChanged;

  static const _names = [
    'Topo à esquerda', 'Topo ao centro', 'Topo à direita',
    'Meio à esquerda', 'Centro', 'Meio à direita',
    'Base à esquerda', 'Base ao centro', 'Base à direita',
  ];

  @override
  Widget build(BuildContext context) {
    final w = landscape ? 190.0 : 140.0;
    final h = landscape ? 140.0 : 190.0;
    final line = Theme.of(context).colorScheme.outline;
    return Column(children: [
      Container(
        width: w,
        height: h,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: line),
        ),
        child: GridView.count(
          crossAxisCount: 3,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: (w - 12) / (h - 12),
          children: [
            for (var i = 0; i < 9; i++)
              Semantics(
                button: true,
                selected: i == selected,
                label: _names[i],
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onChanged(i),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: i == selected
                            ? kTeal
                            : Colors.grey.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: i == selected
                          ? const Icon(Icons.image, color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(_names[selected], style: const TextStyle(fontSize: 13)),
    ]);
  }
}


/// Barra de formatação, como no Word.
q.QuillSimpleToolbarConfig _toolbarConfig(bool multiRows) =>
    q.QuillSimpleToolbarConfig(
      multiRowsDisplay: multiRows,
      showDividers: true,
      showFontFamily: true,
      showFontSize: true,
      showBoldButton: true,
      showItalicButton: true,
      showUnderLineButton: true,
      showStrikeThrough: false,
      showInlineCode: false,
      showColorButton: true,
      showBackgroundColorButton: false,
      showClearFormat: true,
      showAlignmentButtons: true,
      showLeftAlignment: true,
      showCenterAlignment: true,
      showRightAlignment: true,
      showJustifyAlignment: true,
      showHeaderStyle: false,
      showListNumbers: true,
      showListBullets: true,
      showListCheck: false,
      showCodeBlock: false,
      showQuote: false,
      showIndent: true,
      showLink: false,
      showUndo: true,
      showRedo: true,
      showSearchButton: false,
      showSubscript: false,
      showSuperscript: false,
      buttonOptions: const q.QuillSimpleToolbarButtonOptions(
        fontFamily: q.QuillToolbarFontFamilyButtonOptions(
          defaultDisplayText: 'Fonte',
          items: {'Arial': 'sans-serif', 'Times': 'serif', 'Normal': 'Clear'},
        ),
        fontSize: q.QuillToolbarFontSizeButtonOptions(
          defaultDisplayText: 'Tamanho',
          items: {
            'Pequena': 'small',
            'Normal': '0',
            'Grande': 'large',
            'Muito grande': 'huge',
          },
        ),
      ),
    );

/// Caixa do texto com a barra de formatação em cima.
class _EditorBox extends StatelessWidget {
  const _EditorBox({required this.controller, required this.onFullscreen});
  final q.QuillController controller;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          child: Row(children: [
            Expanded(
              child: q.QuillSimpleToolbar(
                controller: controller,
                config: _toolbarConfig(false),
              ),
            ),
            IconButton(
              tooltip: 'Editar em tela cheia',
              onPressed: onFullscreen,
              icon: const Icon(Icons.open_in_full, size: 20),
            ),
          ]),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        q.QuillEditor.basic(
          controller: controller,
          config: const q.QuillEditorConfig(
            scrollable: false,
            minHeight: 220,
            padding: EdgeInsets.all(12),
            placeholder: 'Escreva ou cole o texto aqui',
          ),
        ),
      ]),
    );
  }
}

/// Editor em tela cheia, com a barra completa em várias linhas.
class _FullEditor extends StatelessWidget {
  const _FullEditor({required this.controller});
  final q.QuillController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Texto'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: const Text('Pronto'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          q.QuillSimpleToolbar(
            controller: controller,
            config: _toolbarConfig(true),
          ),
          const Divider(height: 1),
          Expanded(
            child: q.QuillEditor.basic(
              controller: controller,
              config: const q.QuillEditorConfig(
                autoFocus: true,
                padding: EdgeInsets.all(16),
                placeholder: 'Escreva ou cole o texto aqui',
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
