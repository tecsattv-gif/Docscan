import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlt;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/doc_store.dart';
import 'common.dart';
import 'viewer_screen.dart';

/// Uma linha lida pelo OCR, com a posição relativa na imagem (0..1).
class _Line {
  final TextEditingController ctl;
  final double l, t, w, h;
  _Line(String text, this.l, this.t, this.w, this.h)
      : ctl = TextEditingController(text: text);
}

/// "Recriar página": lê o texto da foto, deixa corrigir linha por linha
/// e monta um PDF novo e limpo (transcrição, não é o original).
class RecreateScreen extends StatefulWidget {
  final Uint8List image;
  const RecreateScreen({super.key, required this.image});
  @override
  State<RecreateScreen> createState() => _RecreateScreenState();
}

class _RecreateScreenState extends State<RecreateScreen> {
  List<_Line>? _lines;
  String? _error;
  double _ar = 0.707; // largura/altura da imagem

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void dispose() {
    for (final l in _lines ?? const <_Line>[]) {
      l.ctl.dispose();
    }
    super.dispose();
  }

  Future<void> _read() async {
    final dir = await Directory.systemTemp.createTemp('recriar');
    final rec = mlt.TextRecognizer(script: mlt.TextRecognitionScript.latin);
    try {
      final im = await decodeImageFromList(widget.image);
      final iw = im.width.toDouble(), ih = im.height.toDouble();
      _ar = iw / ih;
      final f = File('${dir.path}/pagina.jpg');
      await f.writeAsBytes(widget.image);
      final r = await rec.processImage(mlt.InputImage.fromFilePath(f.path));
      final lines = <_Line>[];
      for (final b in r.blocks) {
        for (final ln in b.lines) {
          final bb = ln.boundingBox;
          lines.add(_Line(ln.text, bb.left / iw, bb.top / ih, bb.width / iw,
              bb.height / ih));
        }
      }
      // ordem de leitura: de cima para baixo, da esquerda para a direita
      lines.sort((a, b) {
        if ((a.t - b.t).abs() < math.min(a.h, b.h) * 0.5) {
          return a.l.compareTo(b.l);
        }
        return a.t.compareTo(b.t);
      });
      if (mounted) setState(() => _lines = lines);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      await rec.close();
      await dir.delete(recursive: true);
    }
  }

  void _showOriginal() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.memory(widget.image),
        ),
      ),
    );
  }

  Future<void> _makePdf() async {
    final lines =
        _lines!.where((l) => l.ctl.text.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      toast(context, 'Não há texto para recriar');
      return;
    }
    final mode = await choose(context, 'Como montar a página?', [
      'Manter a posição original das linhas',
      'Texto corrido (só o conteúdo)',
    ]);
    if (mode == null || !mounted) return;
    final name = await askText(context, 'Nome do documento',
        initial: 'Página recriada');
    if (name == null || name.isEmpty || !mounted) return;

    final f = await Busy.run<File>(context, 'Criando PDF...', () async {
      pw.ThemeData? theme;
      try {
        theme = pw.ThemeData.withFont(
          base: pw.Font.ttf(
              await rootBundle.load('assets/fonts/DejaVuSans.ttf')),
          bold: pw.Font.ttf(
              await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf')),
        );
      } catch (_) {}
      final doc = pw.Document(theme: theme);
      final note = 'Transcrição recriada pelo scandoc em '
          '${DateFormat('dd/MM/yyyy').format(DateTime.now())} '
          '- não é o documento original.';
      pw.Widget footer() => pw.Text(note,
          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600));

      if (mode == 0) {
        // Cada linha no mesmo lugar da foto, numa folha A4.
        const fmt = PdfPageFormat.a4;
        const m = 28.0;
        final aw = fmt.width - m * 2, ah = fmt.height - m * 2 - 12;
        // a imagem cabe na área útil mantendo a proporção
        final pw_ = math.min(aw, ah * _ar);
        final ph = pw_ / _ar;
        final ox = m + (aw - pw_) / 2, oy = m + (ah - ph) / 2;
        doc.addPage(pw.Page(
          pageFormat: fmt,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(children: [
            for (final l in lines)
              pw.Positioned(
                left: ox + l.l * pw_,
                top: oy + l.t * ph,
                child: pw.SizedBox(
                  width: math.max(l.w * pw_ * 1.15, 20.0),
                  height: math.max(l.h * ph, 6.0),
                  child: pw.FittedBox(
                    fit: pw.BoxFit.scaleDown,
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Text(l.ctl.text.trim(),
                        style: pw.TextStyle(
                            fontSize: (l.h * ph * 0.8).clamp(5.0, 40.0).toDouble())),
                  ),
                ),
              ),
            pw.Positioned(left: m, bottom: 14, child: footer()),
          ]),
        ));
      } else {
        doc.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          footer: (_) => footer(),
          build: (_) => [
            for (final l in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(l.ctl.text.trim(),
                    style: const pw.TextStyle(fontSize: 12)),
              ),
          ],
        ));
      }
      return DocStore.saveBytes(await doc.save(), name);
    });
    if (f == null || !mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)));
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recriar página'),
        actions: [
          IconButton(
              tooltip: 'Ver a foto original',
              icon: const Icon(Icons.image_outlined),
              onPressed: _showOriginal),
          if (lines != null && lines.isNotEmpty)
            TextButton(onPressed: _makePdf, child: const Text('Gerar PDF')),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Não consegui ler a página.\n$_error',
                      textAlign: TextAlign.center)))
          : lines == null
              ? const Center(child: CircularProgressIndicator())
              : lines.isEmpty
                  ? const Center(child: Text('Nenhum texto encontrado'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: lines.length + 1,
                      itemBuilder: (_, i) {
                        if (i == 0) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Confira cada linha com a foto (ícone acima) e '
                              'corrija o que o leitor errou. Linha vazia é '
                              'removida. Letra à mão costuma sair com erros.',
                              style: TextStyle(
                                  color: context.muted, fontSize: 13),
                            ),
                          );
                        }
                        final l = lines[i - 1];
                        return TextField(
                          controller: l.ctl,
                          decoration: const InputDecoration(isDense: true),
                        );
                      },
                    ),
    );
  }
}
