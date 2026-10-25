import 'dart:io';
import 'dart:typed_data';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart'
    as mlb;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlt;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/doc_store.dart';
import '../services/image_ops.dart';
import '../services/pdf_tools.dart';
import 'common.dart';
import 'doc_picker.dart';
import 'editor_screen.dart';
import 'page_manager.dart';
import 'signature_screen.dart';
import 'text_screen.dart';
import 'viewer_screen.dart';

/// Todas as ações do app (digitalizar, converter, editar, utilitários).
class ToolActions {
  static final ImagePicker _picker = ImagePicker();

  static void open(BuildContext c, File f) {
    Navigator.push(c, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
  }

  static void _saved(BuildContext c, File f, String msg) {
    toast(c, msg, action: 'Abrir', onAction: () => open(c, f));
  }

  static Future<File?> _pdf(BuildContext c, File? f,
      {String title = 'Escolher PDF'}) async {
    if (f != null) return f;
    final r = await Navigator.push<List<File>>(
        c, MaterialPageRoute(builder: (_) => DocPickerScreen(title: title)));
    if (r == null || r.isEmpty) return null;
    return r.first;
  }

  static Future<ImageSource?> _source(BuildContext c) async {
    final i = await choose(c, 'Origem da imagem', ['Câmera', 'Galeria']);
    if (i == null) return null;
    return i == 0 ? ImageSource.camera : ImageSource.gallery;
  }

  static Future<String?> _imagePath(BuildContext c, {ImageSource? source}) async {
    final s = source ?? await _source(c);
    if (s == null) return null;
    final x = await _picker.pickImage(source: s, imageQuality: 95);
    return x?.path;
  }

  static Future<Uint8List?> _editPath(BuildContext c, String path,
      {bool crop = true}) async {
    final prepared = await Busy.run<Uint8List>(
        c, 'Preparando imagem...', () => compute(ImageOps.prepare, path));
    if (prepared == null || !c.mounted) return null;
    return Navigator.push<Uint8List>(
        c,
        MaterialPageRoute(
            builder: (_) => EditorScreen(bytes: prepared, startWithCrop: crop)));
  }

  static Future<void> _finishScan(BuildContext c, List<Uint8List> pages) async {
    if (pages.isEmpty || !c.mounted) return;
    final name = await askText(c, 'Nome do documento',
        initial: 'Scan ${DateFormat('dd-MM-yyyy HH-mm').format(DateTime.now())}');
    if (name == null || name.isEmpty || !c.mounted) return;
    final f = await Busy.run<File>(
        c, 'Criando PDF...', () => DocStore.saveImagesAsPdf(pages, name));
    if (f == null || !c.mounted) return;
    open(c, f);
  }

  // ------------------------------------------------------------------
  // DIGITALIZAR
  // ------------------------------------------------------------------

  static Future<List<Uint8List>> _manualLoop(BuildContext c) async {
    final pages = <Uint8List>[];
    while (true) {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
      if (x == null || !c.mounted) break;
      final b = await _editPath(c, x.path);
      if (b != null) pages.add(b);
      if (!c.mounted) break;
      final more = await choose(c, '${pages.length} página(s) prontas',
          ['Escanear outra página', 'Concluir']);
      if (more != 0) break;
    }
    return pages;
  }

  static Future<void> scanDocument(BuildContext c) async {
    final prefs = await SharedPreferences.getInstance();
    final auto = prefs.getBool('auto_scan') ?? true;
    final pages = <Uint8List>[];
    var autoOk = false;
    if (auto) {
      try {
        final paths = await CunningDocumentScanner.getPictures(noOfPages: 30);
        if (paths == null || paths.isEmpty) return;
        autoOk = true;
        for (final p in paths) {
          if (!c.mounted) return;
          final b = await _editPath(c, p, crop: false);
          if (b != null) pages.add(b);
        }
      } catch (_) {
        // não desliga o scanner automático para sempre por uma falha só
        autoOk = false;
        pages.clear();
        if (c.mounted) {
          toast(c, 'Scanner automático indisponível. Usando o modo manual.');
        }
      }
    }
    if (!autoOk) {
      if (!c.mounted) return;
      pages.addAll(await _manualLoop(c));
    }
    await _finishScan(c, pages);
  }

  static Future<void> scanBook(BuildContext c) async {
    final pages = <Uint8List>[];
    while (true) {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
      if (x == null || !c.mounted) break;
      final b = await Busy.run<Uint8List>(c, 'Processando página ${pages.length + 1}...',
          () => compute(ImageOps.quick, x.path));
      if (b != null) pages.add(b);
      if (!c.mounted) break;
      final more = await choose(c, '${pages.length} página(s) prontas',
          ['Próxima página', 'Concluir']);
      if (more != 0) break;
    }
    await _finishScan(c, pages);
  }

  static Future<void> idCard(BuildContext c) async {
    final s = await _source(c);
    if (s == null || !c.mounted) return;
    toast(c, 'Fotografe a FRENTE do documento');
    final p1 = await _imagePath(c, source: s);
    if (p1 == null || !c.mounted) return;
    final front = await _editPath(c, p1);
    if (front == null || !c.mounted) return;
    toast(c, 'Agora o VERSO do documento');
    final p2 = await _imagePath(c, source: s);
    if (p2 == null || !c.mounted) return;
    final back = await _editPath(c, p2);
    if (back == null || !c.mounted) return;
    final name = await askText(c, 'Nome do documento', initial: 'Documento de identidade');
    if (name == null || name.isEmpty || !c.mounted) return;
    final f = await Busy.run<File>(c, 'Criando PDF...', () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(height: 20),
            pw.Image(pw.MemoryImage(front), width: 360, fit: pw.BoxFit.contain),
            pw.SizedBox(height: 40),
            pw.Image(pw.MemoryImage(back), width: 360, fit: pw.BoxFit.contain),
          ],
        ),
      ));
      return DocStore.saveBytes(await doc.save(), name);
    });
    if (f == null || !c.mounted) return;
    open(c, f);
  }

  static Future<void> importImages(BuildContext c) async {
    final xs = await _picker.pickMultiImage(imageQuality: 95);
    if (xs.isEmpty || !c.mounted) return;
    final pages = <Uint8List>[];
    for (final x in xs) {
      if (!c.mounted) return;
      final b = await _editPath(c, x.path);
      if (b != null) pages.add(b);
    }
    await _finishScan(c, pages);
  }

  static Future<void> importPdf(BuildContext c) async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
    if (r == null) return;
    var n = 0;
    File? last;
    for (final pf in r.files) {
      if (pf.path == null) continue;
      last = await DocStore.importPdf(pf.path!);
      n++;
    }
    if (!c.mounted || last == null) return;
    final l = last;
    toast(c, '$n PDF(s) importado(s)', action: 'Abrir', onAction: () => open(c, l));
  }

  // ------------------------------------------------------------------
  // OCR e QR
  // ------------------------------------------------------------------

  static Future<String> _ocrFile(String path) async {
    final rec = mlt.TextRecognizer(script: mlt.TextRecognitionScript.latin);
    try {
      final r = await rec.processImage(mlt.InputImage.fromFilePath(path));
      return r.text;
    } finally {
      await rec.close();
    }
  }

  static Future<void> ocrImage(BuildContext c) async {
    final path = await _imagePath(c);
    if (path == null || !c.mounted) return;
    final text = await Busy.run<String>(c, 'Reconhecendo texto...', () => _ocrFile(path));
    if (text == null || !c.mounted) return;
    Navigator.push(
        c,
        MaterialPageRoute(
            builder: (_) => TextScreen(title: 'Texto reconhecido', text: text)));
  }

  static Future<void> qr(BuildContext c) async {
    toast(c, 'Fotografe o código QR ou de barras');
    final path = await _imagePath(c);
    if (path == null || !c.mounted) return;
    final values = await Busy.run<List<String>>(c, 'Lendo código...', () async {
      final s = mlb.BarcodeScanner();
      try {
        final l = await s.processImage(mlb.InputImage.fromFilePath(path));
        return l
            .map((b) => b.displayValue ?? b.rawValue ?? '')
            .where((v) => v.isNotEmpty)
            .toList();
      } finally {
        await s.close();
      }
    });
    if (values == null || !c.mounted) return;
    await showDialog<void>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('Resultado'),
        content: values.isEmpty
            ? const Text('Nenhum código encontrado. Tente de mais perto e com boa luz.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Expanded(child: SelectableText(v)),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: v));
                            toast(c, 'Copiado');
                          },
                        ),
                      ]),
                    ),
                ],
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // EDITAR
  // ------------------------------------------------------------------

  static Future<void> merge(BuildContext c, {List<File>? files}) async {
    var list = files;
    list ??= await Navigator.push<List<File>>(
        c,
        MaterialPageRoute(
            builder: (_) => const DocPickerScreen(
                multi: true, title: 'Escolha os PDFs (na ordem)')));
    if (list == null || !c.mounted) return;
    if (list.length < 2) {
      toast(c, 'Escolha pelo menos 2 PDFs');
      return;
    }
    final fl = list;
    final name = await askText(c, 'Nome do documento', initial: 'Documento mesclado');
    if (name == null || name.isEmpty || !c.mounted) return;
    final f = await Busy.run<File>(c, 'Mesclando PDFs...', () async {
      final bs = <Uint8List>[];
      for (final x in fl) {
        bs.add(await x.readAsBytes());
      }
      final out = await compute(PdfTools.merge, bs);
      return DocStore.saveBytes(out, name);
    });
    if (f == null || !c.mounted) return;
    _saved(c, f, 'PDFs mesclados');
  }

  static Future<void> organize(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Organizar qual PDF?');
    if (f == null || !c.mounted) return;
    Navigator.push(c, MaterialPageRoute(builder: (_) => PageManagerScreen(file: f)));
  }

  static Future<void> sign(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Assinar qual PDF?');
    if (f == null || !c.mounted) return;
    Uint8List? sig;
    final sf = await DocStore.signatureFile();
    if (await sf.exists()) {
      final i = await choose(c, 'Assinatura', ['Usar a assinatura salva', 'Desenhar uma nova']);
      if (i == null) return;
      if (i == 0) sig = await sf.readAsBytes();
    }
    if (sig == null) {
      if (!c.mounted) return;
      sig = await Navigator.push<Uint8List>(
          c, MaterialPageRoute(builder: (_) => const SignatureScreen()));
      if (sig == null) return;
      await sf.writeAsBytes(sig);
    }
    if (!c.mounted) return;
    final bytes = await f.readAsBytes();
    final n = await Busy.run<int>(c, 'Abrindo PDF...', () => compute(PdfTools.pageCount, bytes));
    if (n == null || !c.mounted) return;
    final s = sig;
    final pos = await Navigator.push<Map<String, dynamic>>(
        c,
        MaterialPageRoute(
            builder: (_) => SignPlaceScreen(pdf: bytes, signature: s, pageCount: n)));
    if (pos == null || !c.mounted) return;
    final out = await Busy.run<File>(c, 'Aplicando assinatura...', () async {
      final r = await PdfTools.stamp({
        'pdf': bytes,
        'png': s,
        'page': pos['page'],
        'x': pos['x'],
        'y': pos['y'],
        'w': pos['w'],
        'ar': pos['ar'],
      });
      return DocStore.saveBytes(r, '${docName(f)} (assinado)');
    });
    if (out == null || !c.mounted) return;
    open(c, out);
  }

  static Future<void> watermark(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Marca d\'água em qual PDF?');
    if (f == null || !c.mounted) return;
    final kind = await choose(c, 'Tipo de marca d\'água',
        ['Texto ou nome', 'Imagem (logo, foto...)']);
    if (kind == null || !c.mounted) return;

    if (kind == 1) {
      // ---- marca com imagem ----
      final x = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 90, maxWidth: 1600);
      if (x == null || !c.mounted) return;
      final img = await x.readAsBytes();
      if (!c.mounted) return;
      final style = await choose(c, 'Estilo',
          ['Grande e transparente no centro', 'Pequena no canto']);
      if (style == null || !c.mounted) return;
      final out = await Busy.run<File>(c, 'Aplicando marca d\'água...', () async {
        final r = await compute(PdfTools.watermarkImage,
            {'pdf': await f.readAsBytes(), 'img': img, 'corner': style == 1});
        return DocStore.saveBytes(r, '${docName(f)} (marca)');
      });
      if (out == null || !c.mounted) return;
      open(c, out);
      return;
    }

    // ---- marca com texto (lembra o último texto usado) ----
    final prefs = await SharedPreferences.getInstance();
    if (!c.mounted) return;
    final text = await askText(c, 'Texto da marca d\'água',
        initial: prefs.getString('wm_text') ?? '',
        hint: 'Ex.: CONFIDENCIAL ou seu nome');
    if (text == null || text.isEmpty || !c.mounted) return;
    await prefs.setString('wm_text', text);
    if (!c.mounted) return;
    final style = await choose(c, 'Estilo', ['Diagonal grande', 'Pequena no canto']);
    if (style == null || !c.mounted) return;
    final out = await Busy.run<File>(c, 'Aplicando marca d\'água...', () async {
      final r = await compute(PdfTools.watermark,
          {'pdf': await f.readAsBytes(), 'text': text, 'corner': style == 1});
      return DocStore.saveBytes(r, '${docName(f)} (marca)');
    });
    if (out == null || !c.mounted) return;
    open(c, out);
  }

  static Future<void> dateStamp(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Carimbar qual PDF?');
    if (f == null || !c.mounted) return;
    final text = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final out = await Busy.run<File>(c, 'Aplicando carimbo...', () async {
      final r = await compute(
          PdfTools.dateStamp, {'pdf': await f.readAsBytes(), 'text': text});
      return DocStore.saveBytes(r, '${docName(f)} (carimbo)');
    });
    if (out == null || !c.mounted) return;
    open(c, out);
  }

  // ------------------------------------------------------------------
  // UTILITÁRIOS
  // ------------------------------------------------------------------

  static Future<void> compress(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Comprimir qual PDF?');
    if (f == null || !c.mounted) return;
    final q = await choose(c, 'Qualidade', [
      'Alta (menos compressão)',
      'Média (recomendado)',
      'Baixa (menor arquivo)',
    ]);
    if (q == null || !c.mounted) return;
    final dpi = [130.0, 100.0, 72.0][q];
    final jq = [82, 70, 55][q];
    final bytes = await f.readAsBytes();
    final out = await Busy.run<File>(c, 'Comprimindo... pode demorar', () async {
      final doc = pw.Document();
      await for (final r in Printing.raster(bytes, dpi: dpi)) {
        final png = await r.toPng();
        final jpg = await compute(ImageOps.toJpeg, {'bytes': png, 'q': jq});
        final w = r.width * 72.0 / dpi;
        final h = r.height * 72.0 / dpi;
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(w, h),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Image(pw.MemoryImage(jpg), fit: pw.BoxFit.fill),
        ));
      }
      final data = await doc.save();
      return DocStore.saveBytes(data, '${docName(f)} (comprimido)');
    });
    if (out == null || !c.mounted) return;
    final before = bytes.length;
    final after = out.lengthSync();
    if (after >= before) {
      toast(c, 'Este PDF já era pequeno: ficou com ${fmtSize(after)} (antes ${fmtSize(before)}).');
    } else {
      _saved(c, out, 'De ${fmtSize(before)} para ${fmtSize(after)}');
    }
  }

  static Future<void> protect(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Proteger qual PDF?');
    if (f == null || !c.mounted) return;
    final pass = await askText(c, 'Defina uma senha', obscure: true);
    if (pass == null || pass.isEmpty || !c.mounted) return;
    final out = await Busy.run<File>(c, 'Protegendo...', () async {
      final r = await compute(PdfTools.protect, {'pdf': await f.readAsBytes(), 'pw': pass});
      return DocStore.saveBytes(r, '${docName(f)} (protegido)');
    });
    if (out == null || !c.mounted) return;
    _saved(c, out, 'PDF protegido com senha');
  }

  static Future<void> unlock(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Desbloquear qual PDF?');
    if (f == null || !c.mounted) return;
    final pass = await askText(c, 'Senha do PDF', obscure: true);
    if (pass == null || !c.mounted) return;
    final out = await Busy.run<File>(c, 'Removendo senha...', () async {
      final r = await compute(PdfTools.unlock, {'pdf': await f.readAsBytes(), 'pw': pass});
      return DocStore.saveBytes(r, '${docName(f)} (sem senha)');
    });
    if (out == null || !c.mounted) return;
    _saved(c, out, 'Senha removida');
  }

  static Future<void> printPdf(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Imprimir qual PDF?');
    if (f == null) return;
    final bytes = await f.readAsBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: docName(f));
  }

  static Future<void> share(BuildContext c, File f) async {
    await Share.shareXFiles([XFile(f.path)]);
  }

  // ------------------------------------------------------------------
  // CONVERTER
  // ------------------------------------------------------------------

  static Future<void> toImages(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Converter qual PDF?');
    if (f == null || !c.mounted) return;
    final bytes = await f.readAsBytes();
    final dir = await DocStore.exportDir();
    final base = docName(f).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final files = <XFile>[];
    final n = await Busy.run<int>(c, 'Convertendo páginas...', () async {
      var i = 0;
      await for (final r in Printing.raster(bytes, dpi: 150)) {
        i++;
        final jpg = await compute(ImageOps.toJpeg, {'bytes': await r.toPng(), 'q': 90});
        final out = File('${dir.path}/${base}_$i.jpg');
        await out.writeAsBytes(jpg);
        files.add(XFile(out.path));
      }
      return i;
    });
    if (n == null || files.isEmpty) return;
    await Share.shareXFiles(files);
  }

  static Future<void> toLongImage(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Converter qual PDF?');
    if (f == null || !c.mounted) return;
    final bytes = await f.readAsBytes();
    final dir = await DocStore.exportDir();
    final base = docName(f).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final out = await Busy.run<File>(c, 'Criando imagem longa...', () async {
      final parts = <Uint8List>[];
      await for (final r in Printing.raster(bytes, dpi: 100)) {
        parts.add(await r.toPng());
      }
      final jpg = await compute(ImageOps.stitch, parts);
      final o = File('${dir.path}/${base}_longa.jpg');
      await o.writeAsBytes(jpg);
      return o;
    });
    if (out == null) return;
    await Share.shareXFiles([XFile(out.path)]);
  }

  static Future<String> _pdfText(File f) async {
    final bytes = await f.readAsBytes();
    var text = '';
    try {
      text = await compute(PdfTools.extractText, bytes);
    } catch (_) {}
    if (text.trim().length >= 20) return text;
    // PDF escaneado (imagem): usa OCR página a página
    final dir = await DocStore.exportDir();
    final sb = StringBuffer();
    var i = 0;
    await for (final r in Printing.raster(bytes, dpi: 150)) {
      i++;
      final tmp = File('${dir.path}/ocr_$i.png');
      await tmp.writeAsBytes(await r.toPng());
      sb.writeln(await _ocrFile(tmp.path));
      sb.writeln();
    }
    return sb.toString();
  }

  static Future<void> toText(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Extrair texto de qual PDF?');
    if (f == null || !c.mounted) return;
    final text = await Busy.run<String>(c, 'Extraindo texto...', () => _pdfText(f));
    if (text == null || !c.mounted) return;
    Navigator.push(
        c,
        MaterialPageRoute(
            builder: (_) => TextScreen(title: 'Texto do PDF', text: text)));
  }

  static String _rtf(String t) {
    final sb = StringBuffer(r'{\rtf1\ansi\deff0 {\fonttbl{\f0 Arial;}}\f0\fs24 ');
    for (final r in t.runes) {
      if (r == 10) {
        sb.write(r'\par ');
      } else if (r == 13) {
        continue;
      } else if (r == 92 || r == 123 || r == 125) {
        sb.write('\\${String.fromCharCode(r)}');
      } else if (r > 127) {
        if (r > 65535) {
          sb.write('?');
        } else {
          sb.write('\\u${r > 32767 ? r - 65536 : r}?');
        }
      } else {
        sb.write(String.fromCharCode(r));
      }
    }
    sb.write('}');
    return sb.toString();
  }

  static Future<void> toWord(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Converter qual PDF?');
    if (f == null || !c.mounted) return;
    final dir = await DocStore.exportDir();
    final out = await Busy.run<File>(c, 'Convertendo...', () async {
      final text = await _pdfText(f);
      final o = File('${dir.path}/${docName(f).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.rtf');
      await o.writeAsString(_rtf(text));
      return o;
    });
    if (out == null) return;
    await Share.shareXFiles([XFile(out.path)]);
  }

  // ------------------------------------------------------------------
  // MENUS
  // ------------------------------------------------------------------

  /// Ferramentas que se aplicam a um PDF já escolhido.
  static Future<void> showPdfTools(BuildContext c, File f) async {
    final items = <MapEntry<String, Future<void> Function()>>[
      MapEntry('Organizar páginas', () => organize(c, file: f)),
      MapEntry('Assinar', () => sign(c, file: f)),
      MapEntry('Marca d\'água', () => watermark(c, file: f)),
      MapEntry('Carimbo de data e hora', () => dateStamp(c, file: f)),
      MapEntry('Comprimir', () => compress(c, file: f)),
      MapEntry('Proteger com senha', () => protect(c, file: f)),
      MapEntry('Remover senha', () => unlock(c, file: f)),
      MapEntry('PDF para imagens', () => toImages(c, file: f)),
      MapEntry('PDF para imagem longa', () => toLongImage(c, file: f)),
      MapEntry('PDF para texto (OCR)', () => toText(c, file: f)),
      MapEntry('PDF para Word (texto)', () => toWord(c, file: f)),
      MapEntry('Imprimir', () => printPdf(c, file: f)),
    ];
    await showModalBottomSheet<void>(
      context: c,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Ferramentas do PDF',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
              for (final e in items)
                ListTile(
                  title: Text(e.key),
                  onTap: () {
                    Navigator.pop(ctx);
                    e.value();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Menu de um documento da biblioteca.
  static Future<void> showDocMenu(BuildContext c, File f) async {
    final favs = await DocStore.favorites();
    if (!c.mounted) return;
    final isFav = DocStore.isFav(favs, f);
    final i = await choose(c, docName(f), [
      'Abrir',
      'Renomear',
      isFav ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
      'Compartilhar',
      'Ferramentas do PDF',
      'Excluir',
    ]);
    if (i == null || !c.mounted) return;
    switch (i) {
      case 0:
        open(c, f);
        break;
      case 1:
        final n = await askText(c, 'Renomear', initial: docName(f));
        if (n != null && n.isNotEmpty) await DocStore.rename(f, n);
        break;
      case 2:
        await DocStore.toggleFav(f);
        break;
      case 3:
        await share(c, f);
        break;
      case 4:
        await showPdfTools(c, f);
        break;
      case 5:
        if (await confirm(c, 'Excluir', 'Excluir "${docName(f)}"?', ok: 'Excluir')) {
          await DocStore.delete(f);
        }
        break;
    }
  }
}
