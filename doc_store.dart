import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
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
    _docsPath = d.path;
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

  static List<File> _pdfsIn(Directory d) => d
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.pdf'))
      .toList();

  /// Todos os documentos (do início e de dentro das pastas), mais novos primeiro.
  static Future<List<File>> list() async {
    final d = await _dir();
    final files = _pdfsIn(d);
    for (final sub in _folderDirs(d)) {
      files.addAll(_pdfsIn(sub));
    }
    files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  // ---- pastas ----
  /// Pasta onde os documentos NOVOS são salvos (a pasta aberta na aba
  /// Documentos). null = início (sem pasta).
  static String? saveTarget;
  static String? _docsPath;

  static List<Directory> _folderDirs(Directory d) {
    final l = d
        .listSync()
        .whereType<Directory>()
        .where((x) => !_base(x.path).startsWith('.'))
        .toList();
    l.sort((a, b) =>
        _base(a.path).toLowerCase().compareTo(_base(b.path).toLowerCase()));
    return l;
  }

  static String _base(String p) => p.split(Platform.pathSeparator).last;

  /// Nomes das pastas, em ordem alfabética.
  static Future<List<String>> folders() async =>
      _folderDirs(await _dir()).map((d) => _base(d.path)).toList();

  /// Nome da pasta do documento, ou null se está no início.
  static String? folderOf(File f) {
    final parent = f.parent.path;
    if (_docsPath != null ? parent == _docsPath : _base(parent) == 'docs') {
      return null;
    }
    return _base(parent);
  }

  static Future<Directory> _folderDir(String? folder) async {
    final d = await _dir();
    if (folder == null || folder.isEmpty) return d;
    final sub = Directory('${d.path}/$folder');
    if (!await sub.exists()) await sub.create(recursive: true);
    return sub;
  }

  /// Cria uma pasta e devolve o nome final (sem repetir nome existente).
  static Future<String> createFolder(String name) async {
    final d = await _dir();
    var base = _clean(name);
    if (base.isEmpty) base = 'Nova pasta';
    var n = base;
    var i = 2;
    while (await Directory('${d.path}/$n').exists()) {
      n = '$base ($i)';
      i++;
    }
    await Directory('${d.path}/$n').create();
    notify();
    return n;
  }

  static Future<String> renameFolder(String oldName, String newName) async {
    final d = await _dir();
    final clean = _clean(newName);
    if (clean.isEmpty || clean == oldName) return oldName;
    var n = clean;
    var i = 2;
    while (await Directory('${d.path}/$n').exists()) {
      n = '$clean ($i)';
      i++;
    }
    await Directory('${d.path}/$oldName').rename('${d.path}/$n');
    if (saveTarget == oldName) saveTarget = n;
    notify();
    return n;
  }

  /// Exclui a pasta. Com [keepDocs], os documentos voltam para o início.
  static Future<void> deleteFolder(String name, {bool keepDocs = true}) async {
    final d = await _dir();
    final sub = Directory('${d.path}/$name');
    if (!await sub.exists()) return;
    if (keepDocs) {
      for (final f in _pdfsIn(sub)) {
        final t = await _unique(docNameOf(f), dir: d);
        await f.rename(t.path);
      }
    }
    await sub.delete(recursive: true);
    if (saveTarget == name) saveTarget = null;
    notify();
  }

  /// Move o documento para a pasta (null = início).
  static Future<File> moveTo(File f, String? folder) async {
    final target = await _folderDir(folder);
    if (f.parent.path == target.path) return f;
    final t = await _unique(docNameOf(f), dir: target);
    final r = await f.rename(t.path);
    notify();
    return r;
  }

  static String docNameOf(File f) {
    final n = _base(f.path);
    return n.toLowerCase().endsWith('.pdf') ? n.substring(0, n.length - 4) : n;
  }

  static Future<File> _unique(String name, {Directory? dir}) async {
    final d = dir ?? await _folderDir(saveTarget);
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

  /// Copia um PDF (por ex. aberto de outro app) para os documentos do app,
  /// com o nome escolhido.
  static Future<File> saveCopy(File src, String name) async {
    final f = await _unique(name);
    final r = await src.copy(f.path);
    notify();
    return r;
  }

  /// O arquivo já está na biblioteca do app (início ou dentro de uma pasta)?
  static Future<bool> isInLibrary(File f) async {
    final d = await _dir();
    return File(f.path).absolute.path.startsWith('${d.absolute.path}/');
  }

  static Future<File> rename(File f, String newName) async {
    if (_clean(newName) == docNameOf(f)) return f;
    // continua na mesma pasta
    final target = await _unique(newName, dir: f.parent);
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


/// Backup e restauração: junta todos os PDFs (com as pastas) e os favoritos
/// num único .zip, e depois traz tudo de volta.
class DocBackup {
  static const _info = 'docscan_backup.json';

  /// Cria o arquivo .zip numa pasta temporária e devolve o arquivo.
  static Future<File> create() async {
    final d = await DocStore._dir();
    final archive = Archive();
    var count = 0;
    void addAll(Directory dir, String prefix) {
      for (final f in DocStore._pdfsIn(dir)) {
        final bytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile(
            'docs/$prefix${DocStore._base(f.path)}', bytes.length, bytes));
        count++;
      }
    }

    addAll(d, '');
    for (final sub in DocStore._folderDirs(d)) {
      addAll(sub, '${DocStore._base(sub.path)}/');
    }
    final favs = (await DocStore.favorites()).toList();
    final marcas = await _addWatermarks(archive);
    final info = utf8.encode(jsonEncode({
      'app': 'DocScan',
      'versao': 1,
      'data': DateTime.now().toIso8601String(),
      'documentos': count,
      'favoritos': favs,
      'marcas': marcas,
    }));
    archive.addFile(ArchiveFile(_info, info.length, info));

    final tmp = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'DocScan backup ${two(now.day)}-${two(now.month)}-${now.year}'
        ' ${two(now.hour)}h${two(now.minute)}.zip';
    final out = File('${tmp.path}/$name');
    await out.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return out;
  }

  static const _wmKey = 'wm_library';

  static Future<Directory> _wmDir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}watermarks');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Coloca no .zip as marcas d'água salvas (textos e imagens/logos).
  /// Devolve quantas marcas entraram.
  static Future<int> _addWatermarks(Archive archive) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_wmKey);
    if (raw == null) return 0;
    List list;
    try {
      list = jsonDecode(raw) as List;
    } catch (_) {
      return 0;
    }
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      if (m['type'] == 'image') {
        final f = File((m['file'] ?? '') as String);
        if (!f.existsSync()) continue;
        final name = f.path.split(Platform.pathSeparator).last;
        final bytes = f.readAsBytesSync();
        archive.addFile(ArchiveFile('watermarks/$name', bytes.length, bytes));
        m['file'] = name; // no backup guarda só o nome do arquivo
      }
      out.add(m);
    }
    final bytes = utf8.encode(jsonEncode(out));
    archive.addFile(ArchiveFile('watermarks.json', bytes.length, bytes));
    return out.length;
  }

  /// Traz de volta as marcas d'água do backup, sem duplicar as que já existem.
  static Future<int> _restoreWatermarks(Archive archive) async {
    final idx = archive.files.where((f) => f.name == 'watermarks.json');
    if (idx.isEmpty) return 0;
    List list;
    try {
      list = jsonDecode(utf8.decode(idx.first.readBytes() ?? [])) as List;
    } catch (_) {
      return 0;
    }
    final p = await SharedPreferences.getInstance();
    List current = [];
    try {
      current = jsonDecode(p.getString(_wmKey) ?? '[]') as List;
    } catch (_) {}
    final ids = current.map((e) => (e as Map)['id']).toSet();
    final texts = current
        .where((e) => (e as Map)['type'] != 'image')
        .map((e) => (e as Map)['text'])
        .toSet();
    final dir = await _wmDir();
    var added = 0;
    for (final e in list) {
      final m = Map<String, dynamic>.from(e as Map);
      if (ids.contains(m['id'])) continue;
      if (m['type'] == 'image') {
        final name = ((m['file'] ?? '') as String).split('/').last;
        if (name.isEmpty || name.contains('..')) continue;
        final src = archive.files.where((f) => f.name == 'watermarks/$name');
        if (src.isEmpty) continue;
        final bytes = src.first.readBytes();
        if (bytes == null) continue;
        final target = File('${dir.path}${Platform.pathSeparator}$name');
        await target.writeAsBytes(bytes);
        m['file'] = target.path;
      } else if (texts.contains(m['text'])) {
        continue;
      }
      current.add(m);
      added++;
    }
    await p.setString(_wmKey, jsonEncode(current));
    return added;
  }

  /// Pasta pública onde o backup fica salvo no celular.
  static const pasta = '/storage/emulated/0/Documents/DocScan';
  static const pastaLegivel = 'Documentos › DocScan';
  static const nomeFixo = 'DocScan backup.zip';

  /// Copia o backup para Documentos/DocScan com nome fixo, substituindo o
  /// backup anterior (e apagando os antigos com data no nome).
  /// Devolve o caminho gravado.
  static Future<String> saveToFolder(File zip) async {
    await Directory(pasta).create(recursive: true);
    var destino = File('$pasta/$nomeFixo');
    try {
      if (await destino.exists()) await destino.delete();
      await zip.copy(destino.path);
    } catch (_) {
      // Arquivo de uma instalação anterior (o Android não deixa apagar):
      // grava com a data no nome.
      final now = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      destino = File('$pasta/DocScan backup ${now.year}-${two(now.month)}-${two(now.day)}'
          ' ${two(now.hour)}h${two(now.minute)}.zip');
      await zip.copy(destino.path);
    }
    try {
      await for (final e in Directory(pasta).list()) {
        final nome = e.path.split('/').last;
        if (e is File &&
            e.path != destino.path &&
            nome.startsWith('DocScan backup') &&
            nome.endsWith('.zip')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return destino.path;
  }

  /// Se há marcas d'água salvas (para permitir backup só com elas).
  static Future<bool> hasWatermarks() async {
    final raw = (await SharedPreferences.getInstance()).getString(_wmKey);
    return raw != null && raw != '[]';
  }

  /// Quantos documentos existem (para avisar quando não há o que salvar).
  static Future<int> count() async => (await DocStore.list()).length;

  /// Restaura um backup. Documentos que já existem iguais (mesmo nome e
  /// tamanho) são pulados; com o mesmo nome e conteúdo diferente ganham
  /// " (2)" no nome. Devolve quantos foram restaurados, ou -1 se o arquivo
  /// não for um backup do DocScan.
  static Future<int> restore(String zipPath) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    } catch (_) {
      return -1;
    }
    final hasInfo = archive.any((f) => f.name == _info);
    final hasDocs = archive.any((f) => f.name.startsWith('docs/'));
    if (!hasInfo && !hasDocs) return -1;
    var restored = 0;

    // Marcas d'água (textos e logos) salvas.
    try {
      restored += await _restoreWatermarks(archive);
    } catch (_) {}

    final d = await DocStore._dir();
    for (final f in archive) {
      if (!f.isFile) continue;
      final parts = f.name.split('/');
      if (parts.first != 'docs' || parts.length < 2 || parts.length > 3) continue;
      if (parts.any((p) => p.isEmpty || p == '.' || p == '..')) continue;
      final fileName = parts.last;
      if (!fileName.toLowerCase().endsWith('.pdf')) continue;
      final bytes = f.readBytes();
      if (bytes == null) continue;

      var dir = d;
      if (parts.length == 3) {
        final folder = DocStore._clean(parts[1]);
        if (folder.isEmpty || folder.startsWith('.')) continue;
        dir = Directory('${d.path}/$folder');
        if (!await dir.exists()) await dir.create(recursive: true);
      }
      final target = File('${dir.path}/${DocStore._clean(fileName)}');
      if (await target.exists()) {
        if (await target.length() == bytes.length) continue; // já existe igual
        final unique = await DocStore._unique(
            fileName.substring(0, fileName.length - 4),
            dir: dir);
        await unique.writeAsBytes(bytes);
      } else {
        await target.writeAsBytes(bytes);
      }
      restored++;
    }

    // Junta os favoritos do backup com os atuais.
    try {
      final infoFile = archive.firstWhere((f) => f.name == _info);
      final data = jsonDecode(utf8.decode(infoFile.readBytes() ?? []));
      final favs = (data['favoritos'] as List?)?.whereType<String>() ?? [];
      if (favs.isNotEmpty) {
        final p = await SharedPreferences.getInstance();
        final s = (p.getStringList('favs') ?? <String>[]).toSet()..addAll(favs);
        await p.setStringList('favs', s.toList());
      }
    } catch (_) {}

    DocStore.notify();
    return restored;
  }
}
