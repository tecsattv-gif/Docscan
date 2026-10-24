import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DocStore {
  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/docs');
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

  static Future<File> saveImagesAsPdf(List<String> images, String name) async {
    final pdf = pw.Document();
    for (final path in images) {
      final img = pw.MemoryImage(await File(path).readAsBytes());
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
      ));
    }
    final d = await _dir();
    final f = File('${d.path}/${_clean(name)}.pdf');
    await f.writeAsBytes(await pdf.save());
    return f;
  }

  static Future<File> importPdf(String sourcePath) async {
    final d = await _dir();
    final name = sourcePath.split(Platform.pathSeparator).last;
    return File(sourcePath).copy('${d.path}/$name');
  }

  static Future<File> rename(File f, String newName) async {
    final d = await _dir();
    return f.rename('${d.path}/${_clean(newName)}.pdf');
  }

  static Future<void> delete(File f) => f.delete();
}
