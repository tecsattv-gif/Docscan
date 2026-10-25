import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' show Printing;
import 'package:shared_preferences/shared_preferences.dart';

class DocStore {
  /// Avisa as telas quando a lista de documentos muda.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void notify() => changes.value++;

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/docs');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> _sub(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _clean(String n) =>
      n.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();

  static Future<List<File>> list() async {
    final d = await _dir();
    final files = d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList();
    files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  static Future<File> _unique(String name) async {
    final d = await _dir();
    var base = _clean(name);
    if (base.isEmpty) base = 'Documento';
    var f = File('${d.path}/$base.pdf');
    var i = 2;
    while (await f.exists()) {
      f = File('${d.path}/$base ($i).pdf');
      i++;
    }
    return f;
  }

  static Future<File> saveBytes(Uint8List bytes, String name) async {
    final f = await _unique(name);
    await f.writeAsBytes(bytes);
    notify();
    return f;
  }

  // ---- tamanhos de página ----
  /// Nomes mostrados ao usuário (mesma ordem de [_pageSizes]).
  static const pageSizeNames = [
    'A4 (21 × 29,7 cm)',
    'Carta (21,6 × 27,9 cm)',
    'Ofício (21,6 × 33 cm)',
    'Legal (21,6 × 35,6 cm)',
    'A5 (14,8 × 21 cm)',
    'A3 (29,7 × 42 cm)',
    'Tamanho da foto (sem bordas)',
  ];

  /// null = página do tamanho exato da imagem.
  static final List<PdfPageFormat?> _pageSizes = [
    PdfPageFormat.a4,
    PdfPageFormat.letter,
    const PdfPageFormat(21.6 * PdfPageFormat.cm, 33 * PdfPageFormat.cm),
    PdfPageFormat.legal,
    PdfPageFormat.a5,
    PdfPageFormat.a3,
    null,
  ];

  /// Formato de papel pelo índice (o item "Tamanho da foto" vira A4).
  static PdfPageFormat pageFormatAt(int i) =>
      _pageSizes[i.clamp(0, _pageSizes.length - 1)] ?? PdfPageFormat.a4;

  static Future<int> lastPageSize() async {
    final p = await SharedPreferences.getInstance();
    final i = p.getInt('page_size') ?? 0;
    return (i >= 0 && i < pageSizeNames.length) ? i : 0;
  }

  static Future<void> setPageSize(int i) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('page_size', i);
  }

  static const orientationNames = ['Automático (conforme a foto)', 'Retrato', 'Paisagem'];

  static Future<int> lastOrientation() async {
    final p = await SharedPreferences.getInstance();
    final i = p.getInt('page_orient') ?? 0;
    return (i >= 0 && i < orientationNames.length) ? i : 0;
  }

  static Future<void> setOrientation(int i) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('page_orient', i);
  }

  /// orientation: 0 = automático, 1 = retrato, 2 = paisagem.
  static Future<File> saveImagesAsPdf(List<Uint8List> images, String name,
      {int pageSize = 0, int orientation = 0, bool margin = false}) async {
    final bytes = await imagesToPdfBytes(images,
        pageSize: pageSize, orientation: orientation, margin: margin);
    return saveBytes(bytes, name);
  }

  /// Monta o PDF das imagens sem salvar na lista (usado em "Adicionar páginas").
  static Future<Uint8List> imagesToPdfBytes(List<Uint8List> images,
      {int pageSize = 0, int orientation = 0, bool margin = false}) async {
    final pdf = pw.Document();
    final base = _pageSizes[pageSize.clamp(0, _pageSizes.length - 1)];
    for (final b in images) {
      final im = pw.MemoryImage(b);
      final iw = (im.width ?? 1).toDouble();
      final ih = (im.height ?? 1).toDouble();
      final land = orientation == 0 ? iw > ih : orientation == 2;
      PdfPageFormat fmt;
      if (base == null) {
        // página com a proporção da foto, lado maior = 29,7 cm
        const big = 29.7 * PdfPageFormat.cm;
        fmt = iw > ih
            ? PdfPageFormat(big, big * ih / iw)
            : PdfPageFormat(big * iw / ih, big);
      } else {
        fmt = land ? base.landscape : base.portrait;
      }
      final m = (margin && base != null) ? 1.0 * PdfPageFormat.cm : 0.0;
      pdf.addPage(pw.Page(
        pageFormat: fmt,
        margin: pw.EdgeInsets.all(m),
        build: (_) => pw.Center(
            child: pw.Image(im,
                fit: base == null ? pw.BoxFit.fill : pw.BoxFit.contain)),
      ));
    }
    return pdf.save();
  }

  /// Substitui o conteúdo de um documento existente (mantém o mesmo nome).
  static Future<void> overwrite(File f, Uint8List bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(f.path);
    notify();
  }

  static Future<File> importPdf(String sourcePath) async {
    var name = sourcePath.split(Platform.pathSeparator).last;
    if (name.toLowerCase().endsWith('.pdf')) {
      name = name.substring(0, name.length - 4);
    }
    final f = await _unique(name);
    final r = await File(sourcePath).copy(f.path);
    notify();
    return r;
  }

  static Future<File> rename(File f, String newName) async {
    final target = await _unique(newName);
    final r = await f.rename(target.path);
    notify();
    return r;
  }

  static Future<void> delete(File f) async {
    await f.delete();
    notify();
  }

  // ---- favoritos ----
  static Future<Set<String>> favorites() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList('favs') ?? <String>[]).toSet();
  }

  static String _fname(File f) => f.path.split(Platform.pathSeparator).last;

  static Future<bool> toggleFav(File f) async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList('favs') ?? <String>[]).toSet();
    final n = _fname(f);
    final added = s.add(n);
    if (!added) s.remove(n);
    await p.setStringList('favs', s.toList());
    notify();
    return added;
  }

  static bool isFav(Set<String> favs, File f) => favs.contains(_fname(f));

  // ---- miniaturas ----
  static Future<void> _chain = Future<void>.value();
  static final Map<String, File> _thumbCache = {};

  static Future<File?> thumb(File f) {
    final c = Completer<File?>();
    _chain = _chain.then((_) async {
      c.complete(await _thumb(f));
    });
    return c.future;
  }

  static Future<File?> _thumb(File f) async {
    try {
      final key =
          '${f.path.hashCode}_${f.lastModifiedSync().millisecondsSinceEpoch}';
      final cached = _thumbCache[key];
      if (cached != null && cached.existsSync()) return cached;
      final dir = await _sub('thumbs');
      final t = File('${dir.path}/$key.png');
      if (!await t.exists()) {
        final bytes = await f.readAsBytes();
        await for (final r in Printing.raster(bytes, pages: [0], dpi: 40)) {
          await t.writeAsBytes(await r.toPng());
          break;
        }
      }
      if (await t.exists()) {
        _thumbCache[key] = t;
        return t;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> clearThumbs() async {
    final dir = await _sub('thumbs');
    for (final e in dir.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {}
    }
    _thumbCache.clear();
  }

  static Future<int> totalSize() async {
    var t = 0;
    for (final f in await list()) {
      t += f.lengthSync();
    }
    return t;
  }

  // ---- assinatura salva ----
  static Future<File> signatureFile() async {
    final d = await _sub('misc');
    return File('${d.path}/assinatura.png');
  }

  static Future<Directory> exportDir() async {
    final t = await getTemporaryDirectory();
    final d = Directory('${t.path}/export');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }
}
