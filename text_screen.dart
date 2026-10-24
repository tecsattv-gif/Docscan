import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import '../services/doc_store.dart';
import 'common.dart';
import 'viewer_screen.dart';

/// Mostra um texto (OCR / extração) com copiar, compartilhar e salvar em PDF.
class TextScreen extends StatelessWidget {
  final String title;
  final String text;
  const TextScreen({super.key, required this.title, required this.text});

  Future<void> _share(BuildContext c) async {
    final d = await DocStore.exportDir();
    final f = File('${d.path}/texto.txt');
    await f.writeAsString(text);
    await Share.shareXFiles([XFile(f.path)]);
  }

  Future<void> _toPdf(BuildContext c) async {
    final name = await askText(c, 'Nome do PDF', initial: 'Texto extraído');
    if (name == null || name.isEmpty || !c.mounted) return;
    final f = await Busy.run<File>(c, 'Gerando PDF...', () async {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        build: (_) => [pw.Text(text, style: const pw.TextStyle(fontSize: 12))],
      ));
      return DocStore.saveBytes(await doc.save(), name);
    });
    if (f == null || !c.mounted) return;
    Navigator.push(c, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              toast(context, 'Texto copiado');
            },
          ),
          IconButton(
              tooltip: 'Compartilhar',
              icon: const Icon(Icons.share),
              onPressed: () => _share(context)),
          IconButton(
              tooltip: 'Salvar como PDF',
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: () => _toPdf(context)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text.trim().isEmpty ? '(Nenhum texto encontrado)' : text,
          style: const TextStyle(fontSize: 16, height: 1.4),
        ),
      ),
    );
  }
}
