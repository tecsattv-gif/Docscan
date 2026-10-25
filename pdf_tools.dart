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
    final rot = (a['rot'] as List?)?.cast<int>();
    if (rot == null || rot.every((r) => r % 360 == 0)) {
      return Uint8List.fromList(bytes);
    }
    // Giro: reabre o PDF pronto e define a rotação de cada página.
    final d = PdfDocument(inputBytes: Uint8List.fromList(bytes));
    for (var i = 0; i < d.pages.count && i < rot.length; i++) {
      final r = ((rot[i] % 360) + 360) % 360;
      if (r == 0) continue;
      d.pages[i].rotation = r == 90
          ? PdfPageRotateAngle.rotateAngle90
          : r == 180
              ? PdfPageRotateAngle.rotateAngle180
              : PdfPageRotateAngle.rotateAngle270;
    }
    final rotated = await d.save();
    d.dispose();
    return Uint8List.fromList(rotated);
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
    final text = (a['text'] as String).trim();
    final corner = a['corner'] == true;
    for (var i = 0; i < d.pages.count; i++) {
      final page = d.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      g.save();
      if (corner) {
        final fs = (size.width * 0.022).clamp(8.0, 24.0).toDouble();
        final font = PdfStandardFont(PdfFontFamily.helvetica, fs);
        final ts = font.measureString(text);
        final m = size.width * 0.03;
        // caixa do tamanho exato do texto: assim ele nunca é cortado
        g.drawString(text, font,
            brush: PdfSolidBrush(PdfColor(90, 90, 90)),
            bounds: Rect.fromLTWH(size.width - ts.width - m - 2,
                size.height - ts.height - m - 2, ts.width + 4, ts.height + 4));
      } else {
        // tamanho da letra calculado pela largura REAL do texto,
        // para caber na diagonal da página
        final diag = math.sqrt(size.width * size.width + size.height * size.height);
        final probe = PdfStandardFont(PdfFontFamily.helvetica, 40,
            style: PdfFontStyle.bold);
        final w40 = math.max(probe.measureString(text).width, 1.0);
        final fs = (40 * diag * 0.65 / w40).clamp(14.0, 140.0).toDouble();
        final font = PdfStandardFont(PdfFontFamily.helvetica, fs,
            style: PdfFontStyle.bold);
        final ts = font.measureString(text);
        final angle = -math.atan2(size.height, size.width) * 180 / math.pi;
        g.setTransparency(0.30);
        g.translateTransform(size.width / 2, size.height / 2);
        g.rotateTransform(angle);
        // caixa maior que o texto: antes ela tinha a altura exata da letra
        // e o PDF descartava a linha (por isso a marca não aparecia)
        g.drawString(text, font,
            brush: PdfSolidBrush(PdfColor(120, 120, 120)),
            bounds: Rect.fromLTWH(-ts.width / 2 - 4, -ts.height / 2 - 4,
                ts.width + 8, ts.height + 8),
            format: PdfStringFormat(
                alignment: PdfTextAlignment.center,
                lineAlignment: PdfVerticalAlignment.middle));
      }
      g.restore();
    }
    final bytes = await d.save();
    d.dispose();
    src.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Marca d'água com imagem (logo, foto, assinatura...).
  /// corner=false: grande e transparente no centro da página.
  /// corner=true: pequena no canto inferior direito.
  static Future<Uint8List> watermarkImage(Map a) async {
    final src = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final d = _rebuild(src);
    final bmp = PdfBitmap(a['img'] as Uint8List);
    final ar = bmp.width / math.max(bmp.height, 1);
    final corner = a['corner'] == true;
    for (var i = 0; i < d.pages.count; i++) {
      final page = d.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      // cabe dentro de uma caixa (maxW x maxH) mantendo a proporção
      final maxW = size.width * (corner ? 0.20 : 0.70);
      final maxH = size.height * (corner ? 0.12 : 0.60);
      var w = maxW, h = maxW / ar;
      if (h > maxH) {
        h = maxH;
        w = maxH * ar;
      }
      g.save();
      if (corner) {
        final m = size.width * 0.03;
        g.setTransparency(0.85);
        g.drawImage(bmp,
            Rect.fromLTWH(size.width - w - m, size.height - h - m, w, h));
      } else {
        g.setTransparency(0.22);
        g.drawImage(bmp, Rect.fromLTWH(
            (size.width - w) / 2, (size.height - h) / 2, w, h));
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

  /// Coloca uma imagem PNG (carimbo / marca d'água) numa página ou em todas,
  /// com transparência e rotação. x,y = centro (0..1), w = largura relativa,
  /// ar = largura/altura da imagem, angle em graus, opacity 0..1.
  static Future<Uint8List> overlay(Map a) async {
    final src = PdfDocument(inputBytes: a['pdf'] as Uint8List);
    final d = _rebuild(src);
    final bmp = PdfBitmap(a['png'] as Uint8List);
    final all = a['all'] == true;
    final only = a['page'] as int;
    final x = (a['x'] as num).toDouble(), y = (a['y'] as num).toDouble();
    final wr = (a['w'] as num).toDouble(), ar = (a['ar'] as num).toDouble();
    final op = (a['opacity'] as num).toDouble().clamp(0.05, 1.0).toDouble();
    final angle = (a['angle'] as num).toDouble();
    for (var i = 0; i < d.pages.count; i++) {
      if (!all && i != only) continue;
      final page = d.pages[i];
      final g = page.graphics;
      final size = page.getClientSize();
      final w = wr * size.width, h = w / ar;
      g.save();
      if (op < 0.999) g.setTransparency(op);
      g.translateTransform(x * size.width, y * size.height);
      if (angle.abs() > 0.01) g.rotateTransform(angle);
      g.drawImage(bmp, Rect.fromLTWH(-w / 2, -h / 2, w, h));
      g.restore();
    }
    final bytes = await d.save();
    d.dispose();
    src.dispose();
    return Uint8List.fromList(bytes);
  }
}
