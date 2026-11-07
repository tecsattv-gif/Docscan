import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show PdfPreview;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/doc_store.dart';
import 'common.dart';
import 'letter_templates.dart';
import 'signature_screen.dart';
import 'viewer_screen.dart';

/// Ferramenta "Criar PDF": um editor de documentos parecido com o Word.
///
/// - folha branca com o texto e barra de formatação em abas (Texto,
///   Parágrafo, Inserir) logo acima do teclado;
/// - modelos prontos (cartas de demissão, carta formal, declaração, recibo);
/// - inserir data, linha, quebra de página, foto e assinatura no meio do texto;
/// - "Juntar linhas" conserta texto colado com quebras no meio das frases;
/// - pré-visualização antes de salvar e rascunho guardado automaticamente.
///
/// Marcadores no texto (aparecem no editor e viram outra coisa no PDF):
/// "[assinatura]", "[foto N]", "[nova página]" e uma linha só com "———".
class CreatePdfScreen extends StatefulWidget {
  const CreatePdfScreen({super.key});
  @override
  State<CreatePdfScreen> createState() => _CreatePdfScreenState();
}

class _CreatePdfScreenState extends State<CreatePdfScreen> {
  static const _draftKey = 'criar_pdf_rascunho_v1';
  static const kSignature = '[assinatura]';
  static const kPageBreak = '[nova página]';
  static const kLine = '————————';

  final _name = TextEditingController(
      text: 'Documento ${DateFormat('dd-MM-yyyy HH-mm').format(DateTime.now())}');
  final _doc = q.QuillController.basic();
  final _editorFocus = FocusNode();
  StreamSubscription<dynamic>? _docSub;
  Timer? _saveTimer;

  final _images = <Uint8List>[];
  final _picker = ImagePicker();
  Uint8List? _signature;

  // Página
  int _size = 0;
  bool _landscape = false;
  double _fontSize = 12;
  bool _margins = true;
  bool _pageNumbers = false;
  int _blankPages = 1;

  // Fotos que não estão no meio do texto: em páginas separadas ou no fim do
  // texto; posição (grade 3x3) e tamanho. O tamanho vale também para as
  // fotos do meio do texto.
  bool _imgSeparate = true;
  int _imgPos = 4;
  double _imgScale = 1.0;
  double _sigScale = 0.35;

  int _tab = 0; // barra: 0 Texto, 1 Parágrafo, 2 Inserir

  static const _pdfAligns = [
    pw.Alignment.topLeft, pw.Alignment.topCenter, pw.Alignment.topRight,
    pw.Alignment.centerLeft, pw.Alignment.center, pw.Alignment.centerRight,
    pw.Alignment.bottomLeft, pw.Alignment.bottomCenter, pw.Alignment.bottomRight,
  ];
  static const _rowAligns = [
    pw.Alignment.centerLeft, pw.Alignment.center, pw.Alignment.centerRight,
  ];

  int get _paperCount => DocStore.pageSizeNames.length - 1;
  bool get _docEmpty => _doc.document.toPlainText().trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _listenDoc();
    DocStore.lastPageSize().then((i) {
      if (mounted && i < _paperCount) setState(() => _size = i);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());
  }

  void _listenDoc() {
    _docSub?.cancel();
    _docSub = _doc.document.changes.listen((_) {
      _scheduleSave();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveDraft();
    _docSub?.cancel();
    _name.dispose();
    _doc.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  // ---------- Rascunho ----------

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final empty = _docEmpty;
      final delta = empty ? null : _doc.document.toDelta().toJson();
      final name = _name.text;
      final p = await SharedPreferences.getInstance();
      if (empty) {
        await p.remove(_draftKey);
        return;
      }
      await p.setString(_draftKey, jsonEncode({'delta': delta, 'name': name}));
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_draftKey);
    } catch (_) {}
  }

  Future<void> _loadDraft() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_draftKey);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final doc = q.Document.fromJson(m['delta'] as List);
      if (doc.toPlainText().trim().isEmpty) return;
      _setDocument(doc);
      if (m['name'] is String && (m['name'] as String).isNotEmpty) {
        _name.text = m['name'] as String;
      }
      if (!mounted) return;
      toast(context, 'Rascunho anterior recuperado',
          action: 'Começar do zero', onAction: () => _setDocument(q.Document()));
    } catch (_) {}
  }

  void _setDocument(q.Document doc) {
    _doc.document = doc;
    _listenDoc();
    _scheduleSave();
    if (mounted) setState(() {});
  }

  // ---------- Inserir ----------

  int get _cursor {
    final s = _doc.selection;
    final max = _doc.document.length - 1;
    if (!s.isValid || s.start < 0) return max;
    return s.start.clamp(0, max);
  }

  /// Insere o texto na posição do cursor (trocando o que estiver selecionado).
  void _insert(String text) {
    final s = _doc.selection;
    final index = _cursor;
    final maxLen = _doc.document.length - 1 - index;
    final len = s.isValid ? (s.end - s.start).clamp(0, maxLen) : 0;
    _doc.replaceText(
        index, len, text, TextSelection.collapsed(offset: index + text.length));
  }

  /// Insere um marcador sozinho numa linha.
  void _insertBlock(String marker) {
    final plain = _doc.document.toPlainText();
    final i = _cursor;
    final atLineStart = i == 0 || plain[i - 1] == '\n';
    _insert('${atLineStart ? '' : '\n'}$marker\n');
  }

  Future<void> _insertDate() async {
    final now = DateTime.now();
    final opts = [dataPorExtenso(now), DateFormat('dd/MM/yyyy').format(now)];
    final i = await choose(context, 'Inserir data', opts);
    if (i == null) return;
    _insert(opts[i]);
  }

  Future<bool> _getSignature({bool askReuse = true}) async {
    final sf = await DocStore.signatureFile();
    if (askReuse && await sf.exists()) {
      if (!mounted) return false;
      final i = await choose(
          context, 'Assinatura', ['Usar a assinatura salva', 'Desenhar uma nova']);
      if (i == null) return false;
      if (i == 0) {
        _signature = await sf.readAsBytes();
        return true;
      }
    }
    if (!mounted) return false;
    final sig = await Navigator.push<Uint8List>(
        context, MaterialPageRoute(builder: (_) => const SignatureScreen()));
    if (sig == null) return false;
    await sf.writeAsBytes(sig);
    _signature = sig;
    return true;
  }

  Future<void> _insertSignature() async {
    if (await _getSignature()) {
      _insertBlock(kSignature);
      if (mounted) {
        toast(context,
            'Assinatura inserida. Para centralizar, use o alinhamento em Parágrafo.');
      }
    }
  }

  Future<void> _insertPhoto() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    final b = await x.readAsBytes();
    setState(() => _images.add(b));
    _insertBlock('[foto ${_images.length}]');
  }

  Future<void> _addPagePhotos() async {
    final xs = await _picker.pickMultiImage(imageQuality: 90);
    if (xs.isEmpty) return;
    final bytes = <Uint8List>[];
    for (final x in xs) {
      bytes.add(await x.readAsBytes());
    }
    if (mounted) setState(() => _images.addAll(bytes));
  }

  // ---------- Modelos ----------

  Future<void> _openTemplates() async {
    FocusScope.of(context).unfocus();
    final tpl = await showModalBottomSheet<LetterTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, sc) {
          final groups = <String>[];
          for (final t in letterTemplates) {
            if (!groups.contains(t.group)) groups.add(t.group);
          }
          return ListView(controller: sc, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Modelos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(g.toUpperCase(),
                    style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(ctx).colorScheme.primary)),
              ),
              for (final t in letterTemplates.where((t) => t.group == g))
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(t.name),
                  subtitle: Text(t.hint),
                  onTap: () => Navigator.pop(ctx, t),
                ),
            ],
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Troque o que está entre [colchetes] pelos seus dados. '
                  'Os modelos são uma ajuda e não substituem aconselhamento jurídico.',
                  style: TextStyle(fontSize: 12)),
            ),
          ]);
        },
      ),
    );
    if (tpl == null || !mounted) return;
    if (!_docEmpty) {
      final ok = await confirm(context, 'Usar o modelo?',
          'O texto atual será substituído pelo modelo "${tpl.name}".',
          ok: 'Substituir');
      if (!ok) return;
    }
    _setDocument(q.Document.fromJson(tpl.toDelta(dataPorExtenso(DateTime.now()))));
    if (_name.text.startsWith('Documento ')) _name.text = tpl.name;
    if (mounted) {
      toast(context, 'Modelo aplicado. Troque o texto entre [colchetes] pelos seus dados.');
    }
  }

  // ---------- Juntar linhas ----------

  /// Texto colado (por exemplo do OCR) vem com uma quebra no fim de cada
  /// linha do papel. Junta a linha com a seguinte quando a frase continua:
  /// a linha não termina em . : ; ! ? e a seguinte começa com minúscula.
  /// Vale para o texto selecionado, ou para tudo se nada estiver selecionado.
  void _joinLines() {
    final plain = _doc.document.toPlainText();
    final s = _doc.selection;
    var start = 0, end = plain.length - 1;
    if (s.isValid && s.end > s.start) {
      start = s.start;
      end = s.end;
    }
    final cuts = <int>[];
    for (var i = start; i < end && i < plain.length - 1; i++) {
      if (plain[i] != '\n') continue;
      final prev = i > 0 ? plain[i - 1] : '\n';
      final next = plain[i + 1];
      if (prev == '\n' || '.:;!?'.contains(prev)) continue;
      final lower = next.toLowerCase() == next && next.toUpperCase() != next;
      if (lower) cuts.add(i);
    }
    if (cuts.isEmpty) {
      toast(context, 'Nenhuma frase partida encontrada');
      return;
    }
    // Do fim para o começo, para os índices não mudarem.
    for (final i in cuts.reversed) {
      final hasSpace = plain[i - 1] == ' ';
      _doc.replaceText(i, 1, hasSpace ? '' : ' ', null);
    }
    toast(context, '${cuts.length} linha(s) juntada(s)');
  }

  // ---------- PDF ----------

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
    return _fontTheme = pw.ThemeData.withFont(
      base: base,
      bold: await f('DejaVuSans-Bold.ttf'),
      italic: await f('DejaVuSans-Oblique.ttf'),
      boldItalic: await f('DejaVuSans-BoldOblique.ttf'),
    );
  }

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

  static final _times = pw.Font.times();
  static final _timesBold = pw.Font.timesBold();
  static final _timesItalic = pw.Font.timesItalic();
  static final _timesBoldItalic = pw.Font.timesBoldItalic();

  /// Lê o texto do editor (trechos com estilos e, no fim de cada linha, o
  /// estilo do parágrafo) e monta os blocos do PDF.
  List<pw.Widget> _richBody(
      bool full, double usableW, double usableH, Set<int> usedImages) {
    final out = <pw.Widget>[];
    var spans = <pw.InlineSpan>[];
    final lineText = StringBuffer();
    final counters = <int, int>{};
    final photoRe = RegExp(r'^\[foto (\d+)\]$');
    final lineRe = RegExp(r'^[-—_–]{3,}$');

    void endLine(Map<String, dynamic>? a) {
      final plain = lineText.toString().trim();
      final align = a?['align'];
      final list = a?['list'];
      final header = a?['header'];
      final indent = (a?['indent'] as num?)?.toInt() ?? 0;
      final lh = (a?['line-height'] as num?)?.toDouble() ?? 1.15;
      final rowAlign = switch (align) {
        'center' => pw.Alignment.center,
        'right' => pw.Alignment.centerRight,
        _ => pw.Alignment.centerLeft,
      };
      final textAlign = switch (align) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        'justify' => pw.TextAlign.justify,
        _ => pw.TextAlign.left,
      };
      final photo = photoRe.firstMatch(plain);
      final photoN = photo == null ? -1 : int.parse(photo.group(1)!) - 1;

      if (plain == kPageBreak) {
        out.add(pw.NewPage());
      } else if (lineRe.hasMatch(plain)) {
        out.add(pw.Divider(thickness: 0.7, height: 14));
      } else if (plain == kSignature) {
        out.add(pw.Container(
          alignment: rowAlign,
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: _signature != null
              ? pw.Image(pw.MemoryImage(_signature!),
                  width: usableW * _sigScale, fit: pw.BoxFit.contain)
              : pw.Text('______________________________',
                  style: pw.TextStyle(fontSize: _fontSize)),
        ));
      } else if (photoN >= 0 && photoN < _images.length) {
        usedImages.add(photoN);
        out.add(pw.Container(
          alignment: rowAlign,
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          child: pw.ConstrainedBox(
            constraints: pw.BoxConstraints(
                maxWidth: usableW * _imgScale,
                maxHeight: usableH * 0.8 * _imgScale),
            child: pw.Image(pw.MemoryImage(_images[photoN]), fit: pw.BoxFit.contain),
          ),
        ));
      } else {
        // Parágrafo normal
        final scale = switch (header) { 1 => 1.6, 2 => 1.35, 3 => 1.15, _ => 1.0 };
        final size = _fontSize * scale;
        final lineStyle = pw.TextStyle(
          fontSize: size,
          lineSpacing: size * (lh - 1.0) + 1.5,
          fontWeight: header != null ? pw.FontWeight.bold : null,
        );
        final content =
            spans.isEmpty ? <pw.InlineSpan>[const pw.TextSpan(text: ' ')] : spans;
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
        final gap = header != null ? 6.0 : 2.0;
        if (marker != null) {
          out.add(pw.Padding(
            padding: pw.EdgeInsets.only(left: left, bottom: gap),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.SizedBox(width: 20, child: pw.Text(marker, style: lineStyle)),
              pw.Expanded(child: text),
            ]),
          ));
        } else if (left > 0) {
          out.add(pw.Padding(
              padding: pw.EdgeInsets.only(left: left, bottom: gap), child: text));
        } else {
          // Sem recuo vai direto, para um parágrafo longo poder passar de página.
          out.add(text);
          out.add(pw.SizedBox(height: gap));
        }
      }
      spans = <pw.InlineSpan>[];
      lineText.clear();
    }

    for (final op in _doc.document.toDelta().toList()) {
      if (!op.isInsert) continue;
      final data = op.data;
      if (data is! String) continue;
      final attrs = op.attributes ?? const <String, dynamic>{};
      final parts = data.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          spans.add(_span(parts[i], attrs, full));
          lineText.write(parts[i]);
        }
        if (i < parts.length - 1) endLine(attrs);
      }
    }
    if (spans.isNotEmpty) endLine(null);

    // O editor termina com uma linha vazia: tira as do fim.
    while (out.isNotEmpty) {
      final last = out.last;
      if (last is pw.SizedBox || (last is pw.RichText && _isBlank(last))) {
        out.removeLast();
      } else {
        break;
      }
    }
    return out;
  }

  static bool _isBlank(pw.RichText t) {
    final root = t.text;
    if (root is! pw.TextSpan) return false;
    final kids = root.children ?? const <pw.InlineSpan>[];
    return kids.every((k) => k is pw.TextSpan && (k.text ?? '').trim().isEmpty);
  }

  pw.TextSpan _span(String text, Map<String, dynamic> a, bool full) {
    final serif = a['font'] == 'serif';
    final deco = <pw.TextDecoration>[
      if (a['underline'] == true) pw.TextDecoration.underline,
      if (a['strike'] == true) pw.TextDecoration.lineThrough,
    ];
    final bg = _colorOf(a['background']);
    return pw.TextSpan(
      text: serif ? _safe(text) : _clean(text, full),
      style: pw.TextStyle(
        fontWeight: a['bold'] == true ? pw.FontWeight.bold : null,
        fontStyle: a['italic'] == true ? pw.FontStyle.italic : null,
        fontSize: _sizeOf(a['size']),
        decoration: deco.isEmpty ? null : pw.TextDecoration.combine(deco),
        color: _colorOf(a['color']),
        background: bg == null ? null : pw.BoxDecoration(color: bg),
        font: serif ? _times : null,
        fontNormal: serif ? _times : null,
        fontBold: serif ? _timesBold : null,
        fontItalic: serif ? _timesItalic : null,
        fontBoldItalic: serif ? _timesBoldItalic : null,
      ),
    );
  }

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

  Future<Uint8List> _buildBytes() async {
    final base = DocStore.pageFormatAt(_size);
    final fmt = _landscape ? base.landscape : base.portrait;
    final margin = _margins ? 2.0 * PdfPageFormat.cm : 0.5 * PdfPageFormat.cm;
    final theme = await _loadFont();
    final full = theme != null;
    final doc = pw.Document(theme: theme);
    final usableW = fmt.width - 2 * margin;
    final usableH = fmt.height - 2 * margin;

    if (_signature == null && _doc.document.toPlainText().contains(kSignature)) {
      final sf = await DocStore.signatureFile();
      if (await sf.exists()) _signature = await sf.readAsBytes();
    }

    final used = <int>{};
    final body =
        _docEmpty ? <pw.Widget>[] : _richBody(full, usableW, usableH, used);
    final rest = <Uint8List>[
      for (var i = 0; i < _images.length; i++)
        if (!used.contains(i)) _images[i]
    ];

    if (body.isEmpty && rest.isEmpty) {
      for (var i = 0; i < _blankPages; i++) {
        doc.addPage(pw.Page(pageFormat: fmt, build: (_) => pw.SizedBox()));
      }
      return doc.save();
    }

    final flow = !_imgSeparate && rest.isNotEmpty;
    if (body.isNotEmpty || flow) {
      doc.addPage(pw.MultiPage(
        pageFormat: fmt,
        margin: pw.EdgeInsets.all(margin),
        footer: _pageNumbers
            ? (ctx) => pw.Container(
                  alignment: pw.Alignment.centerRight,
                  margin: const pw.EdgeInsets.only(top: 8),
                  child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                )
            : null,
        build: (_) => [
          ...body,
          if (flow)
            for (final b in rest)
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
      final align = _pdfAligns[_imgPos];
      for (final b in rest) {
        doc.addPage(pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.all(margin),
          build: (_) => pw.Align(
            alignment: align,
            child: pw.SizedBox(
              width: usableW * _imgScale,
              height: usableH * _imgScale,
              child: pw.Image(pw.MemoryImage(b),
                  fit: pw.BoxFit.contain, alignment: align),
            ),
          ),
        ));
      }
    }
    return doc.save();
  }

  Future<void> _preview() async {
    FocusScope.of(context).unfocus();
    final bytes = await Busy.run<Uint8List>(context, 'Montando...', _buildBytes);
    if (bytes == null || !mounted) return;
    final save = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => _PreviewScreen(bytes: bytes)));
    if (save == true && mounted) await _create(bytes: bytes);
  }

  Future<void> _create({Uint8List? bytes}) async {
    FocusScope.of(context).unfocus();
    await DocStore.setPageSize(_size);
    if (!mounted) return;
    final f = await Busy.run<File>(context, 'Criando PDF...', () async {
      final b = bytes ?? await _buildBytes();
      final name = _name.text.trim().isEmpty ? 'Documento' : _name.text.trim();
      return DocStore.saveBytes(b, name);
    });
    if (f == null || !mounted) return;
    _saveTimer?.cancel();
    await _clearDraft();
    _docSub?.cancel();
    _doc.document = q.Document(); // não guarda de novo o rascunho ao sair
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
  }

  // ---------- Tela ----------

  Future<void> _openPageSettings() async {
    FocusScope.of(context).unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        void up(VoidCallback f) {
          setState(f);
          setSheet(() {});
        }

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (ctx, sc) => ListView(
            controller: sc,
            padding: EdgeInsets.fromLTRB(
                16, 0, 16, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            children: [
              const Text('Página e arquivo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                onChanged: (_) => _scheduleSave(),
                decoration: const InputDecoration(
                    labelText: 'Nome do arquivo', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _size,
                decoration: const InputDecoration(
                    labelText: 'Tamanho do papel', border: OutlineInputBorder()),
                items: [
                  for (var i = 0; i < _paperCount; i++)
                    DropdownMenuItem(
                        value: i, child: Text(DocStore.pageSizeNames[i])),
                ],
                onChanged: (v) => up(() => _size = v ?? 0),
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
                onSelectionChanged: (s) => up(() => _landscape = s.first),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Letra do texto'),
                Expanded(
                  child: Slider(
                    value: _fontSize,
                    min: 8,
                    max: 24,
                    divisions: 16,
                    label: _fontSize.round().toString(),
                    activeColor: kTeal,
                    onChanged: (v) => up(() => _fontSize = v),
                  ),
                ),
                Text('${_fontSize.round()}'),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Margens normais (2 cm)'),
                value: _margins,
                activeColor: kTeal,
                onChanged: (v) => up(() => _margins = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Numerar as páginas'),
                subtitle: const Text('Ex.: 1 / 2 no canto de baixo'),
                value: _pageNumbers,
                activeColor: kTeal,
                onChanged: (v) => up(() => _pageNumbers = v),
              ),
              if (_doc.document.toPlainText().contains(kSignature)) ...[
                Row(children: [
                  const Text('Tamanho da assinatura'),
                  Expanded(
                    child: Slider(
                      value: _sigScale,
                      min: 0.15,
                      max: 0.7,
                      divisions: 11,
                      activeColor: kTeal,
                      onChanged: (v) => up(() => _sigScale = v),
                    ),
                  ),
                ]),
                TextButton.icon(
                  onPressed: () async {
                    await _getSignature(askReuse: false);
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('Desenhar a assinatura de novo'),
                ),
              ],
              const Divider(height: 32),
              Row(children: [
                const Expanded(
                  child: Text('Fotos em páginas próprias',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await _addPagePhotos();
                    setSheet(() {});
                  },
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Adicionar'),
                ),
              ]),
              const Text(
                  'Para pôr uma foto no meio do texto, use Inserir → Foto na barra do editor.',
                  style: TextStyle(fontSize: 12)),
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
                        left: 4,
                        bottom: 4,
                        child: CircleAvatar(
                            radius: 10,
                            backgroundColor: Colors.black54,
                            child: Text('${i + 1}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white))),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: true,
                        label: Text('Uma por página'),
                        icon: Icon(Icons.filter_none)),
                    ButtonSegment(
                        value: false,
                        label: Text('Depois do texto'),
                        icon: Icon(Icons.wrap_text)),
                  ],
                  selected: {_imgSeparate},
                  onSelectionChanged: (s) => up(() => _imgSeparate = s.first),
                ),
                const SizedBox(height: 12),
                if (_imgSeparate)
                  Center(
                    child: _PositionPicker(
                        selected: _imgPos,
                        landscape: _landscape,
                        onChanged: (p) => up(() => _imgPos = p)),
                  ),
                Row(children: [
                  const Text('Tamanho das fotos'),
                  Expanded(
                    child: Slider(
                      value: _imgScale,
                      min: 0.2,
                      max: 1.0,
                      divisions: 16,
                      label: '${(_imgScale * 100).round()}%',
                      activeColor: kTeal,
                      onChanged: (v) => up(() => _imgScale = v),
                    ),
                  ),
                  Text('${(_imgScale * 100).round()}%'),
                ]),
                TextButton.icon(
                  onPressed: () => up(() => _images.clear()),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remover todas as fotos'),
                ),
              ],
              if (_docEmpty && _images.isEmpty) ...[
                const Divider(height: 32),
                Row(children: [
                  const Expanded(child: Text('Sem texto: criar páginas em branco')),
                  IconButton(
                      onPressed:
                          _blankPages > 1 ? () => up(() => _blankPages--) : null,
                      icon: const Icon(Icons.remove)),
                  Text('$_blankPages'),
                  IconButton(
                      onPressed:
                          _blankPages < 50 ? () => up(() => _blankPages++) : null,
                      icon: const Icon(Icons.add)),
                ]),
              ],
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final empty = _docEmpty && _images.isEmpty;
    // Folha sempre branca com letra escura, como no papel.
    final paperTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: kTeal,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Criar PDF'),
        actions: [
          IconButton(
            tooltip: 'Modelos',
            onPressed: _openTemplates,
            icon: const Icon(Icons.library_books_outlined),
          ),
          IconButton(
            tooltip: 'Página, fotos e nome do arquivo',
            onPressed: _openPageSettings,
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: 'Pré-visualizar',
            onPressed: _preview,
            icon: const Icon(Icons.visibility_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: kTeal,
                  padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: () => _create(),
              child: Text(empty ? 'Em branco' : 'Criar'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: Container(
              color: cs.surfaceContainerHighest,
              alignment: Alignment.topCenter,
              child: Theme(
                data: paperTheme,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black26, blurRadius: 6, offset: Offset(0, 1)),
                    ],
                  ),
                  child: q.QuillEditor.basic(
                    controller: _doc,
                    focusNode: _editorFocus,
                    config: const q.QuillEditorConfig(
                      expands: true,
                      padding: EdgeInsets.fromLTRB(20, 20, 20, 40),
                      placeholder: 'Escreva aqui, ou toque em Modelos (ícone de livros '
                          'no topo) para começar com uma carta pronta.',
                    ),
                  ),
                ),
              ),
            ),
          ),
          _FormatBar(
            controller: _doc,
            tab: _tab,
            onTab: (t) => setState(() => _tab = t),
            onDate: _insertDate,
            onLine: () => _insertBlock(kLine),
            onPageBreak: () => _insertBlock(kPageBreak),
            onSignature: _insertSignature,
            onPhoto: _insertPhoto,
            onJoinLines: _joinLines,
            onTemplates: _openTemplates,
          ),
        ]),
      ),
    );
  }
}

/// Barra de formatação em abas, como no Word do celular.
class _FormatBar extends StatelessWidget {
  const _FormatBar({
    required this.controller,
    required this.tab,
    required this.onTab,
    required this.onDate,
    required this.onLine,
    required this.onPageBreak,
    required this.onSignature,
    required this.onPhoto,
    required this.onJoinLines,
    required this.onTemplates,
  });
  final q.QuillController controller;
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onDate;
  final VoidCallback onLine;
  final VoidCallback onPageBreak;
  final VoidCallback onSignature;
  final VoidCallback onPhoto;
  final VoidCallback onJoinLines;
  final VoidCallback onTemplates;

  static const _tabs = ['Texto', 'Parágrafo', 'Inserir'];

  Widget _tool(IconData icon, String label, VoidCallback onTap) => Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = controller;
    final List<Widget> tools = switch (tab) {
      0 => <Widget>[
          q.QuillToolbarFontFamilyButton(
            controller: c,
            options: const q.QuillToolbarFontFamilyButtonOptions(
              defaultDisplayText: 'Fonte',
              items: {'Arial': 'sans-serif', 'Times': 'serif', 'Normal': 'Clear'},
            ),
          ),
          q.QuillToolbarFontSizeButton(
            controller: c,
            options: const q.QuillToolbarFontSizeButtonOptions(
              defaultDisplayText: 'Tamanho',
              items: {
                'Pequena': 'small',
                'Normal': '0',
                'Grande': 'large',
                'Muito grande': 'huge',
              },
            ),
          ),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.bold),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.italic),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.underline),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.strikeThrough),
          q.QuillToolbarColorButton(controller: c, isBackground: false),
          q.QuillToolbarColorButton(controller: c, isBackground: true),
          q.QuillToolbarClearFormatButton(controller: c),
        ],
      1 => <Widget>[
          q.QuillToolbarSelectHeaderStyleDropdownButton(
            controller: c,
            options: const q.QuillToolbarSelectHeaderStyleDropdownButtonOptions(
              attributes: [
                q.Attribute.header,
                q.Attribute.h1,
                q.Attribute.h2,
                q.Attribute.h3,
              ],
            ),
          ),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.leftAlignment),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.centerAlignment),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.rightAlignment),
          q.QuillToolbarToggleStyleButton(
              controller: c, attribute: q.Attribute.justifyAlignment),
          q.QuillToolbarToggleStyleButton(controller: c, attribute: q.Attribute.ul),
          q.QuillToolbarToggleStyleButton(controller: c, attribute: q.Attribute.ol),
          q.QuillToolbarIndentButton(controller: c, isIncrease: false),
          q.QuillToolbarIndentButton(controller: c, isIncrease: true),
          q.QuillToolbarSelectLineHeightStyleDropdownButton(controller: c),
          _tool(Icons.merge_type, 'Juntar linhas', onJoinLines),
        ],
      _ => <Widget>[
          _tool(Icons.library_books_outlined, 'Modelo', onTemplates),
          _tool(Icons.draw_outlined, 'Assinatura', onSignature),
          _tool(Icons.today_outlined, 'Data', onDate),
          _tool(Icons.image_outlined, 'Foto', onPhoto),
          _tool(Icons.horizontal_rule, 'Linha', onLine),
          _tool(Icons.insert_page_break_outlined, 'Nova página', onPageBreak),
          q.QuillToolbarSearchButton(controller: c),
        ],
    };

    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          q.QuillToolbarHistoryButton(controller: c, isUndo: true),
          q.QuillToolbarHistoryButton(controller: c, isUndo: false),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_tabs[i]),
                      selected: tab == i,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => onTab(i),
                    ),
                  ),
              ]),
            ),
          ),
        ]),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (final w in tools) Center(child: w),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Pré-visualização do PDF antes de salvar.
class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pré-visualizar'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kTeal),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.save_alt),
              label: const Text('Salvar PDF'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: PdfPreview(
          build: (_) async => bytes,
          useActions: false,
          allowPrinting: false,
          allowSharing: false,
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
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
                        color: i == selected ? kTeal : Colors.grey.withOpacity(0.18),
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
