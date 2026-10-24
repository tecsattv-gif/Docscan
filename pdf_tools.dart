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

  static Future<Uint8List> watermark(Map a) async {
    final d = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final text = a['text'] as String;
    final corner = a['corner'] == true;
    for (var i = 0; i < d.pages.count; i++) {
      final page = d.pages[i];
      final g = page.graphics;
      final size = page.size;
      g.save();
      if (corner) {
        g.setTransparency(0.9);
        g.drawString(
          text,
          PdfStandardFont(PdfFontFamily.helvetica, 10),
          brush: PdfBrushes.darkGray,
          bounds: Rect.fromLTWH(size.width - 230, size.height - 24, 220, 14),
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
    return Uint8List.fromList(bytes);
  }

  /// Coloca uma imagem PNG (assinatura) na página. x,y = centro (0..1),
  /// w = largura relativa à página, ar = largura/altura da imagem.
  static Future<Uint8List> stamp(Map a) async {
    final d = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final page = d.pages[a['page'] as int];
    final size = page.size;
    final w = (a['w'] as double) * size.width;
    final h = w / (a['ar'] as double);
    final cx = (a['x'] as double) * size.width;
    final cy = (a['y'] as double) * size.height;
    page.graphics.drawImage(PdfBitmap(a['png'] as Uint8List),
        Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h));
    final bytes = await d.save();
    d.dispose();
    return Uint8List.fromList(bytes);
  }
}
