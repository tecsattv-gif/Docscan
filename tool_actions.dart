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
import 'id_reader.dart';
import 'page_manager.dart';
import 'place_screen.dart';
import 'recreate_screen.dart';
import 'signature_screen.dart';
import 'text_screen.dart';
import 'viewer_screen.dart';
import 'watermark_library.dart';

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
    final last = await DocStore.lastPageSize();
    if (!c.mounted) return;
    final opts = [
      for (var i = 0; i < DocStore.pageSizeNames.length; i++)
        i == last ? '${DocStore.pageSizeNames[i]}  ✓' : DocStore.pageSizeNames[i]
    ];
    final size = await choose(c, 'Tamanho da página', opts);
    if (size == null || !c.mounted) return;
    await DocStore.setPageSize(size);
    if (!c.mounted) return;
    var orient = 0;
    // "Tamanho da foto" já segue a forma da imagem; não precisa perguntar.
    if (size != DocStore.pageSizeNames.length - 1) {
      final lastO = await DocStore.lastOrientation();
      if (!c.mounted) return;
      final o = await choose(c, 'Orientação da página', [
        for (var i = 0; i < DocStore.orientationNames.length; i++)
          i == lastO
              ? '${DocStore.orientationNames[i]}  ✓'
              : DocStore.orientationNames[i]
      ]);
      if (o == null || !c.mounted) return;
      orient = o;
      await DocStore.setOrientation(o);
      if (!c.mounted) return;
    }
    final f = await Busy.run<File>(c, 'Criando PDF...',
        () => DocStore.saveImagesAsPdf(pages, name,
            pageSize: size, orientation: orient));
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
    final pages = await _scanPages(c);
    if (!c.mounted) return;
    await _finishScan(c, pages);
  }

  /// Digitaliza páginas (scanner automático, ou câmera manual se falhar).
  static Future<List<Uint8List>> _scanPages(BuildContext c) async {
    final prefs = await SharedPreferences.getInstance();
    final auto = prefs.getBool('auto_scan') ?? true;
    final pages = <Uint8List>[];
    var autoOk = false;
    if (auto) {
      try {
        final paths = await CunningDocumentScanner.getPictures(noOfPages: 30);
        if (paths == null || paths.isEmpty) return pages;
        autoOk = true;
        for (final p in paths) {
          if (!c.mounted) return pages;
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
      if (!c.mounted) return pages;
      pages.addAll(await _manualLoop(c));
    }
    return pages;
  }

  /// Digitaliza ou importa mais páginas e junta no FINAL de um PDF existente.
  /// [fromViewer]: chamado de dentro do leitor; reabre o leitor atualizado.
  static Future<void> addPages(BuildContext c,
      {File? file, bool fromViewer = false}) async {
    final f = await _pdf(c, file, title: 'Adicionar páginas em qual PDF?');
    if (f == null || !c.mounted) return;
    final src = await choose(c, 'Adicionar páginas a "${docName(f)}"',
        ['Digitalizar com a câmera', 'Escolher fotos da galeria']);
    if (src == null || !c.mounted) return;
    final pages = <Uint8List>[];
    if (src == 0) {
      pages.addAll(await _scanPages(c));
    } else {
      final xs = await _picker.pickMultiImage(imageQuality: 95);
      for (final x in xs) {
        if (!c.mounted) return;
        final b = await _editPath(c, x.path);
        if (b != null) pages.add(b);
      }
    }
    if (pages.isEmpty || !c.mounted) return;
    final size = await DocStore.lastPageSize();
    final orient = await DocStore.lastOrientation();
    if (!c.mounted) return;
    final before = await Busy.run<int>(c, 'Adicionando ${pages.length} página(s)...',
        () async {
      final old = await f.readAsBytes();
      final n = await compute(PdfTools.pageCount, old);
      final extra = await DocStore.imagesToPdfBytes(pages,
          pageSize: size, orientation: orient);
      final merged = await compute(PdfTools.merge, [old, extra]);
      await DocStore.overwrite(f, merged);
      return n;
    });
    if (before == null || !c.mounted) return;
    // Abre o leitor já na primeira página nova.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('page:${f.path}', before + 1);
    if (!c.mounted) return;
    toast(c, '${pages.length} página(s) adicionada(s)');
    if (fromViewer) {
      // Fecha o leitor antigo e só depois reabre, para o leitor não
      // reaproveitar a versão antiga do arquivo que ainda está na memória.
      final nav = Navigator.of(c);
      nav.pop();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      nav.push(MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
    } else {
      open(c, f);
    }
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

  /// Cartão ID: frente e verso numa única página A4 (como uma fotocópia).
  static Future<void> idCard(BuildContext c) async {
    var mode = await choose(c, 'Cartão ID — como capturar?', [
      'Scanner automático (recomendado)',
      'Câmera (recorte manual)',
      'Fotos da galeria',
    ]);
    if (mode == null || !c.mounted) return;

    Future<Uint8List?> side(String label) async {
      if (!c.mounted) return null;
      toast(c, 'Capture o $label do documento');
      if (mode == 0) {
        try {
          final paths = await CunningDocumentScanner.getPictures(noOfPages: 1);
          if (paths == null || paths.isEmpty || !c.mounted) return null;
          return _editPath(c, paths.first, crop: false);
        } catch (_) {
          mode = 1;
          if (c.mounted) {
            toast(c, 'Scanner automático indisponível. Usando a câmera.');
          }
        }
      }
      if (!c.mounted) return null;
      final p = await _imagePath(c,
          source: mode == 2 ? ImageSource.gallery : ImageSource.camera);
      if (p == null || !c.mounted) return null;
      return _editPath(c, p);
    }

    final front = await side('FRENTE');
    if (front == null || !c.mounted) return;
    Uint8List? back;
    final more = await choose(c, 'Frente pronta', ['Capturar o VERSO', 'Só a frente']);
    if (more == null || !c.mounted) return;
    if (more == 0) {
      back = await side('VERSO');
      if (back == null || !c.mounted) return;
    }
    final size = await choose(c, 'Tamanho no PDF', [
      'Tamanho real do cartão (para imprimir como cópia)',
      'Grande (fácil de ler na tela)',
      'Várias cópias na mesma folha (tamanho real)',
    ]);
    if (size == null || !c.mounted) return;
    var copies = 1;
    if (size == 2) {
      final n = await choose(c, 'Quantas cópias na folha?',
          ['2 cópias', '3 cópias', '4 cópias']);
      if (n == null || !c.mounted) return;
      copies = n + 2;
    }

    // Marca d'água (lembra o último texto usado).
    final prefs = await SharedPreferences.getInstance();
    if (!c.mounted) return;
    final wm = await choose(c, 'Marca d\'água na cópia?', [
      'Sem marca d\'água',
      'Adicionar marca d\'água (evita uso indevido)',
    ]);
    if (wm == null || !c.mounted) return;
    String? wmText;
    if (wm == 1) {
      wmText = await askText(c, 'Texto da marca d\'água',
          initial: prefs.getString('id_wm_text') ??
              'CÓPIA - ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
          hint: 'Ex.: Cópia para abertura de conta no banco X');
      if (wmText == null || !c.mounted) return;
      wmText = wmText.trim();
      if (wmText.isEmpty) wmText = null;
      if (wmText != null) await prefs.setString('id_wm_text', wmText);
      if (!c.mounted) return;
    }

    final name = await askText(c, 'Nome do documento',
        initial: 'Documento de identidade');
    if (name == null || name.isEmpty || !c.mounted) return;

    final f = await Busy.run<File>(c, 'Criando PDF...', () async {
      final real = size != 1;
      final boxW = real ? 85.6 * PdfPageFormat.mm : 360.0;
      final boxH = real ? 54.0 * PdfPageFormat.mm : 250.0;
      pw.Widget card(Uint8List b) {
        final im = pw.MemoryImage(b);
        final iw = (im.width ?? 1).toDouble();
        final ih = (im.height ?? 1).toDouble();
        // Cartão em pé: troca largura e altura da caixa.
        final tall = ih > iw;
        return pw.SizedBox(
          width: tall ? boxH : boxW,
          height: tall ? boxW : boxH,
          child: pw.Image(im, fit: pw.BoxFit.contain),
        );
      }

      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) {
          if (copies > 1) {
            // Cada linha: frente e verso lado a lado (linha de corte entre elas).
            pw.Widget row() => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    card(front),
                    if (back != null) ...[
                      pw.SizedBox(width: 16),
                      card(back!),
                    ],
                  ],
                );
            // Se não couber (cartão em pé), reduz tudo um pouco.
            return pw.Center(
              child: pw.FittedBox(
                fit: pw.BoxFit.scaleDown,
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    for (var i = 0; i < copies; i++) ...[
                      if (i > 0)
                        pw.Container(
                          width: 500,
                          margin: const pw.EdgeInsets.symmetric(vertical: 14),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(
                                  color: PdfColors.grey400,
                                  width: 0.5,
                                  style: pw.BorderStyle.dashed),
                            ),
                          ),
                        ),
                      row(),
                    ],
                  ],
                ),
              ),
            );
          }
          return pw.Column(
            mainAxisAlignment: real
                ? pw.MainAxisAlignment.start
                : pw.MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (real) pw.SizedBox(height: 40),
              card(front),
              if (back != null) ...[
                pw.SizedBox(height: real ? 40 : 20),
                card(back!),
              ],
            ],
          );
        },
      ));
      var bytes = await doc.save();
      if (wmText != null) {
        bytes = await compute(PdfTools.watermark,
            {'pdf': bytes, 'text': wmText, 'corner': false});
      }
      return DocStore.saveBytes(bytes, name);
    });
    if (f == null || !c.mounted) return;

    final next = await choose(c, 'PDF do cartão salvo',
        ['Abrir o PDF', 'Ler os dados do documento']);
    if (!c.mounted) return;
    if (next == 1) {
      await _readIdData(c, [front, if (back != null) back!]);
    } else {
      open(c, f);
    }
  }

  /// Faz OCR dos lados do cartão e mostra os dados (MRZ, CPF, nome, datas...).
  static Future<void> _readIdData(BuildContext c, List<Uint8List> sides) async {
    final text = await Busy.run<String>(c, 'Lendo os dados...', () async {
      final dir = await Directory.systemTemp.createTemp('idcard');
      final buf = StringBuffer();
      try {
        for (var i = 0; i < sides.length; i++) {
          final f = File('${dir.path}/lado$i.jpg');
          await f.writeAsBytes(sides[i]);
          buf.writeln(await _ocrFile(f.path));
        }
      } finally {
        await dir.delete(recursive: true);
      }
      return IdReader.report(buf.toString());
    });
    if (text == null || !c.mounted) return;
    Navigator.push(
        c,
        MaterialPageRoute(
            builder: (_) => TextScreen(title: 'Dados do documento', text: text)));
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

  /// Recriar página: foto danificada -> texto conferido -> PDF novo e limpo.
  static Future<void> recreatePage(BuildContext c) async {
    final path = await _imagePath(c);
    if (path == null || !c.mounted) return;
    final bytes = await _editPath(c, path);
    if (bytes == null || !c.mounted) return;
    Navigator.push(c,
        MaterialPageRoute(builder: (_) => RecreateScreen(image: bytes)));
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
    // Marcas d'água salvas: escolher, criar, trocar ou apagar.
    final picked = await WatermarkLibrary.pick(c);
    if (picked == null || !c.mounted) return;
    final png = picked.png;
    final kind = picked.isImage ? 1 : 0;
    final style = await choose(c, 'Estilo', [
      kind == 1 ? 'Grande e transparente no centro' : 'Diagonal grande',
      'Pequena no canto',
    ]);
    if (style == null || !c.mounted) return;
    final corner = style == 1;
    await _placeAndApply(c, f, png,
        title: 'Posicionar marca d\'água',
        busy: 'Aplicando marca d\'água...',
        suffix: 'marca',
        x: corner ? 0.82 : 0.5,
        y: corner ? 0.95 : 0.5,
        w: corner ? 0.25 : (kind == 1 ? 0.7 : 0.85),
        opacity: corner ? (kind == 1 ? 0.85 : 1.0) : (kind == 1 ? 0.22 : 0.30),
        diagonal: !corner && kind == 0);
  }

  /// Abre a tela de posicionar (arrastar, tamanho, opacidade, páginas)
  /// e aplica o PNG no PDF.
  static Future<void> _placeAndApply(BuildContext c, File f, Uint8List png,
      {required String title,
      required String busy,
      required String suffix,
      double x = 0.5,
      double y = 0.5,
      double w = 0.3,
      double opacity = 1.0,
      bool diagonal = false}) async {
    final bytes = await f.readAsBytes();
    if (!c.mounted) return;
    final n = await Busy.run<int>(
        c, 'Abrindo PDF...', () => compute(PdfTools.pageCount, bytes));
    if (n == null || !c.mounted) return;
    final pos = await Navigator.push<Map<String, dynamic>>(
        c,
        MaterialPageRoute(
            builder: (_) => PlaceScreen(
                  title: title,
                  pdf: bytes,
                  overlay: png,
                  pageCount: n,
                  x: x,
                  y: y,
                  w: w,
                  opacity: opacity,
                  diagonal: diagonal,
                )));
    if (pos == null || !c.mounted) return;
    final out = await Busy.run<File>(c, busy, () async {
      final r = await compute(
          PdfTools.overlay, <String, dynamic>{'pdf': bytes, 'png': png, ...pos});
      return DocStore.saveBytes(r, '${docName(f)} ($suffix)');
    });
    if (out == null || !c.mounted) return;
    open(c, out);
  }

  /// Lê "1-3, 5, 7-9" e devolve grupos de páginas (0-based). Null = inválido.
  static List<List<int>>? _parseRanges(String s, int n) {
    final groups = <List<int>>[];
    for (final part in s.split(RegExp(r'[,;]'))) {
      final t = part.replaceAll(' ', '');
      if (t.isEmpty) continue;
      final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(t);
      if (m == null) return null;
      final a = int.parse(m.group(1)!);
      final b = m.group(2) == null ? a : int.parse(m.group(2)!);
      if (a < 1 || b < a || b > n) return null;
      groups.add([for (var i = a - 1; i < b; i++) i]);
    }
    return groups.isEmpty ? null : groups;
  }

  static Future<void> split(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Dividir qual PDF?');
    if (f == null || !c.mounted) return;
    final bytes = await f.readAsBytes();
    final n = await Busy.run<int>(
        c, 'Abrindo PDF...', () => compute(PdfTools.pageCount, bytes));
    if (n == null || !c.mounted) return;
    if (n < 2) {
      toast(c, 'Este PDF só tem 1 página');
      return;
    }
    final mode = await choose(c, 'Dividir ($n páginas)', [
      'Uma página por arquivo',
      'Escolher intervalos (ex: 1-3, 4-$n)',
    ]);
    if (mode == null || !c.mounted) return;
    List<List<int>> groups;
    if (mode == 0) {
      groups = [for (var i = 0; i < n; i++) [i]];
    } else {
      final t = await askText(c, 'Páginas de cada arquivo',
          hint: 'ex: 1-3, 4-$n  (vírgula separa os arquivos)');
      if (t == null || t.isEmpty || !c.mounted) return;
      final g = _parseRanges(t, n);
      if (g == null) {
        toast(c, 'Intervalo inválido. Use algo como 1-3, 4-$n');
        return;
      }
      groups = g;
    }
    final base = docName(f);
    final made = await Busy.run<int>(c, 'Dividindo PDF...', () async {
      var k = 0;
      for (final g in groups) {
        final out = await compute(PdfTools.pick, {'pdf': bytes, 'pages': g});
        final label = g.length == 1
            ? 'pág ${g.first + 1}'
            : 'págs ${g.first + 1}-${g.last + 1}';
        await DocStore.saveBytes(out, '$base ($label)');
        k++;
      }
      return k;
    });
    if (made == null || !c.mounted) return;
    toast(c, '$made arquivo(s) criados na lista de documentos');
  }

  static Future<void> dateStamp(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Carimbar qual PDF?');
    if (f == null || !c.mounted) return;
    final text = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final png = await stampPng(text);
    if (!c.mounted) return;
    await _placeAndApply(c, f, png,
        title: 'Posicionar carimbo',
        busy: 'Aplicando carimbo...',
        suffix: 'carimbo',
        x: 0.80,
        y: 0.95,
        w: 0.32);
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

  /// Salva o PDF aberto: nos documentos do DocScan ou numa pasta do celular.
  static Future<void> savePdf(BuildContext c, {File? file}) async {
    final f = await _pdf(c, file, title: 'Salvar qual PDF?');
    if (f == null || !c.mounted) return;
    final where = await choose(c, 'Salvar PDF', [
      'Nos meus documentos (DocScan)',
      'No celular (escolher pasta)',
    ]);
    if (where == null || !c.mounted) return;

    // PDFs vindos de outros apps costumam ter nome de código (ex. 6361b06...).
    var suggested = docName(f);
    if (RegExp(r'^[0-9a-fA-F-]{12,}$').hasMatch(suggested)) {
      suggested = 'Documento ${DateFormat('dd-MM-yyyy HH-mm').format(DateTime.now())}';
    }

    if (where == 0) {
      if (await DocStore.isInLibrary(f)) {
        if (c.mounted) toast(c, 'Este PDF já está nos seus documentos');
        return;
      }
      if (!c.mounted) return;
      final name = await askText(c, 'Nome do documento', initial: suggested);
      if (name == null || name.trim().isEmpty || !c.mounted) return;
      final saved = await DocStore.saveCopy(f, name.trim());
      if (c.mounted) _saved(c, saved, 'PDF salvo nos seus documentos');
      return;
    }

    try {
      final out = await FilePicker.platform.saveFile(
        dialogTitle: 'Salvar PDF',
        fileName: '$suggested.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        bytes: await f.readAsBytes(),
      );
      if (out != null && c.mounted) toast(c, 'PDF salvo no celular');
    } catch (_) {
      if (c.mounted) toast(c, 'Não foi possível salvar nessa pasta. Tente outra.');
    }
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
  static Future<void> showPdfTools(BuildContext c, File f,
      {bool fromViewer = false}) async {
    final items = <MapEntry<String, Future<void> Function()>>[
      MapEntry('Salvar PDF', () => savePdf(c, file: f)),
      MapEntry('Adicionar páginas',
          () => addPages(c, file: f, fromViewer: fromViewer)),
      MapEntry('Organizar / girar páginas', () => organize(c, file: f)),
      MapEntry('Dividir PDF', () => split(c, file: f)),
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
  /// Escolhe uma pasta e move os documentos para ela.
  static Future<void> moveToFolder(BuildContext c, List<File> files) async {
    if (files.isEmpty) return;
    final names = await DocStore.folders();
    if (!c.mounted) return;
    final current = files.length == 1 ? DocStore.folderOf(files.first) : '';
    final opts = <String>[
      '＋ Nova pasta',
      current == null ? 'Início (sem pasta)  ✓' : 'Início (sem pasta)',
      for (final n in names) n == current ? '📁 $n  ✓' : '📁 $n',
    ];
    final i = await choose(c,
        files.length == 1 ? 'Mover "${docName(files.first)}" para' : 'Mover ${files.length} documentos para',
        opts);
    if (i == null || !c.mounted) return;
    String? target;
    if (i == 0) {
      final n = await askText(c, 'Nome da nova pasta', hint: 'ex: Trabalho');
      if (n == null || n.trim().isEmpty || !c.mounted) return;
      target = await DocStore.createFolder(n);
    } else if (i >= 2) {
      target = names[i - 2];
    }
    for (final f in files) {
      await DocStore.moveTo(f, target);
    }
    if (c.mounted) {
      toast(c, '${files.length} documento(s) movido(s) para ${target ?? 'o início'}');
    }
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
      'Mover para pasta',
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
        await moveToFolder(c, [f]);
        break;
      case 5:
        await showPdfTools(c, f);
        break;
      case 6:
        if (await confirm(c, 'Excluir', 'Excluir "${docName(f)}"?', ok: 'Excluir')) {
          await DocStore.delete(f);
        }
        break;
    }
  }

}
