import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Operações em PDF (rodam em isolates via compute).
class PdfTools {
  static int pageCount(Uint8List pdf) {
    final d = PdfDocument(inputBytes: pdf);
    final n = d.pages.count;
    d.dispose();
    return n;
  }

  static String extractText(Uint8List pdf) {
    final d = PdfDocument(inputBytes: pdf);
    final t = PdfTextExtractor(d).extractText();
    d.dispose();
    return t;
  }

  static Future<Uint8List> merge(List pdfs) async {
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    final srcs = <PdfDocument>[];
    for (final b in pdfs) {
      final d = PdfDocument(inputBytes: b as Uint8List);
      srcs.add(d);
      for (var i = 0; i < d.pages.count; i++) {
        final p = d.pages[i];
        out.pageSettings.size = p.size;
        out.pages.add().graphics.drawPdfTemplate(
            p.createTemplate(), const Offset(0, 0));
      }
    }
    final bytes = await out.save();
    out.dispose();
    for (final d in srcs) {
      d.dispose();
    }
    return Uint8List.fromList(bytes);
  }

  /// Novo PDF só com as páginas indicadas (índices 0-based, na ordem dada).
  static Future<Uint8List> pick(Map a) async {
    final src = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final pages = (a['pages'] as List).cast<int>();
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    for (final i in pages) {
      final p = src.pages[i];
      out.pageSettings.size = p.size;
      out.pages
          .add()
          .graphics
          .drawPdfTemplate(p.createTemplate(), const Offset(0, 0));
    }
    final bytes = await out.save();
    out.dispose();
    src.dispose();
    return Uint8List.fromList(bytes);
  }

  static Future<Uint8List> protect(Map a) async {
    final d = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final pw = a['pw'] as String;
    d.security.algorithm = PdfEncryptionAlgorithm.aesx128Bit;
    d.security.userPassword = pw;
    d.security.ownerPassword = pw;
    final bytes = await d.save();
    d.dispose();
    return Uint8List.fromList(bytes);
  }

  static Future<Uint8List> unlock(Map a) async {
    final d = PdfDocument(
        inputBytes: a['pdf'] as Uint8List, password: a['pw'] as String);
    d.security.userPassword = '';
    d.security.ownerPassword = '';
    final bytes = await d.save();
    d.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Copia cada página para um documento novo (estado gráfico limpo).
  /// Desenhar direto na página carregada às vezes não aparece em PDFs
  /// gerados por outros apps/bibliotecas.
  static PdfDocument _rebuild(PdfDocument src) {
    final out = PdfDocument();
    out.pageSettings.margins.all = 0;
    for (var i = 0; i < src.pages.count; i++) {
      final p = src.pages[i];
      out.pageSettings.size = p.size;
      out.pages
          .add()
          .graphics
          .drawPdfTemplate(p.createTemplate(), const Offset(0, 0));
    }
    return out;
  }

  static Future<Uint8List> watermark(Map a) async {
    final src = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final d = _rebuild(src);
    final text = a['text'] as String;
    final corner = a['corner'] == true;
    for (var i = 0; i < d.pages.count; i++) {
      final page = d.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      g.save();
      if (corner) {
        final fs = (size.width * 0.018).clamp(8.0, 24.0).toDouble();
        g.drawString(
          text,
          PdfStandardFont(PdfFontFamily.helvetica, fs),
          brush: PdfBrushes.darkGray,
          bounds: Rect.fromLTWH(
              size.width * 0.3, size.height - fs * 2.4, size.width * 0.66, fs * 1.4),
          format: PdfStringFormat(alignment: PdfTextAlignment.right),
        );
      } else {
        g.setTransparency(0.25);
        final fs = (size.width * 1.1 / (math.max(text.length, 1) * 0.55))
            .clamp(18.0, 80.0)
            .toDouble();
        g.translateTransform(size.width / 2, size.height / 2);
        g.rotateTransform(-45);
        g.drawString(
          text,
          PdfStandardFont(PdfFontFamily.helvetica, fs, style: PdfFontStyle.bold),
          brush: PdfBrushes.gray,
          bounds: Rect.fromLTWH(-size.width / 2, -fs / 2, size.width, fs),
          format: PdfStringFormat(
              alignment: PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle),
        );
      }
      g.restore();
    }
    final bytes = await d.save();
    d.dispose();
    src.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Carimbo de data/hora: caixa vermelha bem visível no canto inferior
  /// direito de cada página.
  static Future<Uint8List> dateStamp(Map a) async {
    final src = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final d = _rebuild(src);
    final text = a['text'] as String;
    for (var i = 0; i < d.pages.count; i++) {
      final page = d.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      final fs = (size.width * 0.026).clamp(9.0, 30.0).toDouble();
      final font =
          PdfStandardFont(PdfFontFamily.helvetica, fs, style: PdfFontStyle.bold);
      final tw = font.measureString(text).width;
      final bw = tw + fs * 1.4, bh = fs * 2.0;
      final m = size.width * 0.03;
      final box = Rect.fromLTWH(
          size.width - bw - m, size.height - bh - m, bw, bh);
      final red = PdfColor(200, 30, 30);
      g.save();
      g.drawRectangle(
          pen: PdfPen(red, width: math.max(1.0, fs * 0.12)),
          brush: PdfSolidBrush(PdfColor(255, 255, 255)),
          bounds: box);
      g.drawString(text, font,
          brush: PdfSolidBrush(red),
          bounds: box,
          format: PdfStringFormat(
              alignment: PdfTextAlignment.center,
              lineAlignment: PdfVerticalAlignment.middle));
      g.restore();
    }
    final bytes = await d.save();
    d.dispose();
    src.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Coloca uma imagem PNG (assinatura) na página. x,y = centro (0..1),
  /// w = largura relativa à página, ar = largura/altura da imagem.
  static Future<Uint8List> stamp(Map a) async {
    final src = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final d = _rebuild(src);
    final page = d.pages[a['page'] as int];
    final size = page.getClientSize();
    final w = (a['w'] as double) * size.width;
    final h = w / (a['ar'] as double);
    final cx = (a['x'] as double) * size.width;
    final cy = (a['y'] as double) * size.height;
    page.graphics.drawImage(PdfBitmap(a['png'] as Uint8List),
        Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h));
    final bytes = await d.save();
    d.dispose();
    src.dispose();
    return Uint8List.fromList(bytes);
  }
}
