import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Operações de imagem (rodam em isolates via compute).
class ImageOps {
  static const int maxSide = 1800;

  static int _cl(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

  /// Lê um arquivo, corrige a orientação, reduz e devolve JPEG.
  static Uint8List prepare(String path) {
    return _prepareBytes(File(path).readAsBytesSync());
  }

  static Uint8List _prepareBytes(Uint8List bytes) {
    var im = img.decodeImage(bytes);
    if (im == null) throw Exception('Imagem inválida');
    im = img.bakeOrientation(im);
    final longSide = math.max(im.width, im.height);
    if (longSide > maxSide) {
      final k = maxSide / longSide;
      im = img.copyResize(im,
          width: (im.width * k).round(),
          height: (im.height * k).round(),
          interpolation: img.Interpolation.average);
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: 92));
  }

  /// Modo livro: prepara e aplica o filtro Mágico direto.
  static Uint8List quick(String path) {
    final b = _prepareBytes(File(path).readAsBytesSync());
    return filter({'bytes': b, 'mode': 'magic'});
  }

  static Uint8List toJpeg(Map a) {
    final im = img.decodeImage(a['bytes'] as Uint8List);
    if (im == null) throw Exception('Imagem inválida');
    return Uint8List.fromList(img.encodeJpg(im, quality: a['q'] as int));
  }

  static Uint8List rotate(Map a) {
    final im = img.decodeImage(a['bytes'] as Uint8List);
    if (im == null) throw Exception('Imagem inválida');
    final r = img.copyRotate(im, angle: a['angle'] as int);
    return Uint8List.fromList(img.encodeJpg(r, quality: 92));
  }

  /// Corrige a perspectiva. c = 8 valores normalizados (TL, TR, BR, BL).
  static Uint8List warp(Map a) {
    final src = img.decodeImage(a['bytes'] as Uint8List);
    if (src == null) throw Exception('Imagem inválida');
    final c = (a['c'] as List).map((e) => (e as num).toDouble()).toList();
    final sw = src.width.toDouble();
    final sh = src.height.toDouble();
    final x = <double>[c[0] * sw, c[2] * sw, c[4] * sw, c[6] * sw];
    final y = <double>[c[1] * sh, c[3] * sh, c[5] * sh, c[7] * sh];
    double dist(int i, int j) {
      final dx = x[i] - x[j];
      final dy = y[i] - y[j];
      return math.sqrt(dx * dx + dy * dy);
    }

    var w = math.max(dist(0, 1), dist(3, 2));
    var h = math.max(dist(0, 3), dist(1, 2));
    final k = math.min(1.0, maxSide / math.max(w, h));
    w = w * k;
    h = h * k;
    final ow = math.max(2, w.round());
    final oh = math.max(2, h.round());

    final x0 = x[0], x1 = x[1], x2 = x[2], x3 = x[3];
    final y0 = y[0], y1 = y[1], y2 = y[2], y3 = y[3];
    final sx = x0 - x1 + x2 - x3;
    final sy = y0 - y1 + y2 - y3;
    double g = 0, hh = 0, A, B, D, E;
    final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
    final det = dx1 * dy2 - dx2 * dy1;
    if ((sx.abs() < 1e-9 && sy.abs() < 1e-9) || det.abs() < 1e-9) {
      A = x1 - x0;
      B = x3 - x0;
      D = y1 - y0;
      E = y3 - y0;
    } else {
      g = (sx * dy2 - dx2 * sy) / det;
      hh = (dx1 * sy - sx * dy1) / det;
      A = x1 - x0 + g * x1;
      B = x3 - x0 + hh * x3;
      D = y1 - y0 + g * y1;
      E = y3 - y0 + hh * y3;
    }

    final out = img.Image(width: ow, height: oh);
    for (var j = 0; j < oh; j++) {
      final v = (j + 0.5) / oh;
      for (var i = 0; i < ow; i++) {
        final u = (i + 0.5) / ow;
        final dn = g * u + hh * v + 1;
        final fx = (A * u + B * v + x0) / dn - 0.5;
        final fy = (D * u + E * v + y0) / dn - 0.5;
        _put(src, out, i, j, fx, fy);
      }
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: 92));
  }

  static void _put(
      img.Image src, img.Image out, int ox, int oy, double fx, double fy) {
    final w = src.width, h = src.height;
    final xi = fx.floor(), yi = fy.floor();
    final tx = fx - xi, ty = fy - yi;
    int cx(int v) => v < 0 ? 0 : (v >= w ? w - 1 : v);
    int cy(int v) => v < 0 ? 0 : (v >= h ? h - 1 : v);
    final p00 = src.getPixel(cx(xi), cy(yi));
    final r00 = p00.r, g00 = p00.g, b00 = p00.b;
    final p10 = src.getPixel(cx(xi + 1), cy(yi));
    final r10 = p10.r, g10 = p10.g, b10 = p10.b;
    final p01 = src.getPixel(cx(xi), cy(yi + 1));
    final r01 = p01.r, g01 = p01.g, b01 = p01.b;
    final p11 = src.getPixel(cx(xi + 1), cy(yi + 1));
    final r11 = p11.r, g11 = p11.g, b11 = p11.b;
    double mix(num a, num b, num c, num d) =>
        (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
    out.setPixelRgb(ox, oy, _cl(mix(r00, r10, r01, r11)),
        _cl(mix(g00, g10, g01, g11)), _cl(mix(b00, b10, b01, b11)));
  }

  /// Filtros: original, magic, bw, gray, enhance
  static Uint8List filter(Map a) {
    final bytes = a['bytes'] as Uint8List;
    final mode = a['mode'] as String;
    if (mode == 'original') return bytes;
    final im = img.decodeImage(bytes);
    if (im == null) throw Exception('Imagem inválida');
    if (mode == 'gray') {
      for (final p in im) {
        final l = _cl(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
        p.r = l;
        p.g = l;
        p.b = l;
      }
    } else if (mode == 'enhance') {
      for (final p in im) {
        p.r = _cl((p.r - 128) * 1.25 + 140);
        p.g = _cl((p.g - 128) * 1.25 + 140);
        p.b = _cl((p.b - 128) * 1.25 + 140);
      }
    } else {
      _normalize(im, bw: mode == 'bw');
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: 88));
  }

  /// Remove sombras/iluminação irregular estimando o fundo (papel) e
  /// normalizando. Deixa o papel branco e o texto mais forte.
  static void _normalize(img.Image im, {required bool bw}) {
    final w = im.width, h = im.height;
    const s = 16;
    final sw = (w / s).ceil(), sh = (h / s).ceil();
    final n = sw * sh;
    final sumL = List<double>.filled(n, 0);
    final cnt = List<int>.filled(n, 0);
    for (final p in im) {
      final b = (p.y ~/ s) * sw + (p.x ~/ s);
      sumL[b] += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      cnt[b]++;
    }
    final meanL = List<double>.generate(n, (i) => cnt[i] == 0 ? 0 : sumL[i] / cnt[i]);
    final bgR = List<double>.filled(n, 0);
    final bgG = List<double>.filled(n, 0);
    final bgB = List<double>.filled(n, 0);
    final c2 = List<int>.filled(n, 0);
    for (final p in im) {
      final b = (p.y ~/ s) * sw + (p.x ~/ s);
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (l >= meanL[b]) {
        bgR[b] += p.r;
        bgG[b] += p.g;
        bgB[b] += p.b;
        c2[b]++;
      }
    }
    for (var i = 0; i < n; i++) {
      if (c2[i] > 0) {
        bgR[i] /= c2[i];
        bgG[i] /= c2[i];
        bgB[i] /= c2[i];
      } else {
        bgR[i] = bgG[i] = bgB[i] = 255;
      }
    }
    // máximo local (ignora texto grosso) e suavização
    List<double> maxf(List<double> a) {
      final o = List<double>.filled(n, 0);
      for (var by = 0; by < sh; by++) {
        for (var bx = 0; bx < sw; bx++) {
          var m = 0.0;
          for (var dy = -2; dy <= 2; dy++) {
            for (var dx = -2; dx <= 2; dx++) {
              final yy = by + dy, xx = bx + dx;
              if (yy < 0 || xx < 0 || yy >= sh || xx >= sw) continue;
              final v = a[yy * sw + xx];
              if (v > m) m = v;
            }
          }
          o[by * sw + bx] = m;
        }
      }
      return o;
    }

    List<double> blur(List<double> a) {
      final o = List<double>.filled(n, 0);
      for (var by = 0; by < sh; by++) {
        for (var bx = 0; bx < sw; bx++) {
          var t = 0.0;
          var c = 0;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final yy = by + dy, xx = bx + dx;
              if (yy < 0 || xx < 0 || yy >= sh || xx >= sw) continue;
              t += a[yy * sw + xx];
              c++;
            }
          }
          o[by * sw + bx] = t / c;
        }
      }
      return o;
    }

    final fR = blur(maxf(bgR));
    final fG = blur(maxf(bgG));
    final fB = blur(maxf(bgB));

    double samp(List<double> a, double gx, double gy) {
      var x0 = gx.floor(), y0 = gy.floor();
      final tx = gx - x0, ty = gy - y0;
      int cx(int v) => v < 0 ? 0 : (v >= sw ? sw - 1 : v);
      int cy(int v) => v < 0 ? 0 : (v >= sh ? sh - 1 : v);
      final a00 = a[cy(y0) * sw + cx(x0)];
      final a10 = a[cy(y0) * sw + cx(x0 + 1)];
      final a01 = a[cy(y0 + 1) * sw + cx(x0)];
      final a11 = a[cy(y0 + 1) * sw + cx(x0 + 1)];
      return (a00 * (1 - tx) + a10 * tx) * (1 - ty) +
          (a01 * (1 - tx) + a11 * tx) * ty;
    }

    const lo = 0.42, hi = 0.93;
    for (final p in im) {
      final gx = p.x / s - 0.5, gy = p.y / s - 0.5;
      final br = math.max(samp(fR, gx, gy), 1.0);
      final bg = math.max(samp(fG, gx, gy), 1.0);
      final bb = math.max(samp(fB, gx, gy), 1.0);
      final rr = (p.r / br).clamp(0.0, 1.2).toDouble();
      final rg = (p.g / bg).clamp(0.0, 1.2).toDouble();
      final rb = (p.b / bb).clamp(0.0, 1.2).toDouble();
      if (bw) {
        final l = 0.299 * rr + 0.587 * rg + 0.114 * rb;
        final t = ((l - 0.55) / 0.22).clamp(0.0, 1.0).toDouble();
        final v = _cl(t * t * (3 - 2 * t) * 255);
        p.r = v;
        p.g = v;
        p.b = v;
      } else {
        p.r = _cl((rr - lo) / (hi - lo) * 255);
        p.g = _cl((rg - lo) / (hi - lo) * 255);
        p.b = _cl((rb - lo) / (hi - lo) * 255);
      }
    }
  }

  /// Junta várias imagens (PNG/JPEG) numa imagem longa vertical.
  static Uint8List stitch(List parts) {
    final ims = <img.Image>[];
    for (final b in parts) {
      final d = img.decodeImage(b as Uint8List);
      if (d != null) ims.add(d);
    }
    if (ims.isEmpty) throw Exception('Sem páginas');
    var w = 0, h = 0;
    for (final i in ims) {
      w = math.max(w, i.width);
      h += i.height;
    }
    final canvas = img.Image(width: w, height: h);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    var y = 0;
    for (final i in ims) {
      img.compositeImage(canvas, i, dstX: 0, dstY: y);
      y += i.height;
    }
    return Uint8List.fromList(img.encodeJpg(canvas, quality: 88));
  }
}
