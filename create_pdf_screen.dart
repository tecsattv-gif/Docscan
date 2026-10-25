import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/doc_store.dart';
import 'common.dart';
import 'viewer_screen.dart';

/// Ferramenta "Criar PDF": escreve título, texto, junta fotos e gera o PDF
/// no tamanho e orientação escolhidos. Sem texto nem fotos = página em branco.
class CreatePdfScreen extends StatefulWidget {
  const CreatePdfScreen({super.key});
  @override
  State<CreatePdfScreen> createState() => _CreatePdfScreenState();
}

class _CreatePdfScreenState extends State<CreatePdfScreen> {
  final _name = TextEditingController(
      text: 'Documento ${DateFormat('dd-MM-yyyy HH-mm').format(DateTime.now())}');
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _images = <Uint8List>[];
  final _picker = ImagePicker();

  // Só os tamanhos de papel (sem "Tamanho da foto").
  int _size = 0;
  bool _landscape = false;
  double _fontSize = 12;
  bool _margins = true;
  int _blankPages = 1;

  int get _paperCount => DocStore.pageSizeNames.length - 1;

  @override
  void initState() {
    super.initState();
    DocStore.lastPageSize().then((i) {
      if (mounted && i < _paperCount) setState(() => _size = i);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Fonte completa (DejaVu), colocada em assets/fonts pelo GitHub Actions.
  /// Se não existir, volta à fonte padrão do PDF.
  static pw.ThemeData? _fontTheme;
  static Future<pw.ThemeData?> _loadFont() async {
    if (_fontTheme != null) return _fontTheme;
    try {
      final base = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final bold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf'));
      _fontTheme = pw.ThemeData.withFont(base: base, bold: bold);
    } catch (_) {
      _fontTheme = null;
    }
    return _fontTheme;
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
    final body = _clean(_body.text, full);

    if (title.isEmpty && body.trim().isEmpty && _images.isEmpty) {
      for (var i = 0; i < _blankPages; i++) {
        doc.addPage(pw.Page(pageFormat: fmt, build: (_) => pw.SizedBox()));
      }
    } else {
      if (title.isNotEmpty || body.trim().isNotEmpty) {
        doc.addPage(pw.MultiPage(
          pageFormat: fmt,
          margin: pw.EdgeInsets.all(margin),
          build: (_) => [
            if (title.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 14),
                child: pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: _fontSize * 1.7,
                        fontWeight: pw.FontWeight.bold)),
              ),
            // Um parágrafo por linha, para o texto poder quebrar de página.
            for (final line in body.split('\n'))
              pw.Paragraph(
                text: line.isEmpty ? ' ' : line,
                margin: const pw.EdgeInsets.only(bottom: 4),
                style: pw.TextStyle(fontSize: _fontSize, lineSpacing: 2),
              ),
          ],
        ));
      }
      for (final b in _images) {
        final im = pw.MemoryImage(b);
        doc.addPage(pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.all(margin),
          build: (_) =>
              pw.Center(child: pw.Image(im, fit: pw.BoxFit.contain)),
        ));
      }
    }
    final name = _name.text.trim().isEmpty ? 'Documento' : _name.text.trim();
    return DocStore.saveBytes(await doc.save(), name);
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
        _body.text.trim().isEmpty &&
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
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            onChanged: (_) => setState(() {}),
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
                labelText: 'Texto',
                hintText: 'Escreva ou cole o texto aqui',
                alignLabelWithHint: true,
                border: OutlineInputBorder()),
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
                child: Text('${_images.length} foto(s) — uma por página',
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
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: kTeal,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _create,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(empty ? 'Criar PDF em branco' : 'Criar PDF'),
          ),
        ],
      ),
    );
  }
}
