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

    // recorta um pouco para dentro: evita a faixa escura do fundo na borda
    const ins = 0.01;
    final out = img.Image(width: ow, height: oh);
    for (var j = 0; j < oh; j++) {
      final v = ins + (j + 0.5) / oh * (1 - 2 * ins);
      for (var i = 0; i < ow; i++) {
        final u = ins + (i + 0.5) / ow * (1 - 2 * ins);
        final dn = g * u + hh * v + 1;
        final fx = (A * u + B * v + x0) / dn - 0.5;
        final fy = (D * u + E * v + y0) / dn - 0.5;
        _put(src, out, i, j, fx, fy);
      }
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: 92));
  }

  /// Recorte que segue as bordas TORTAS do papel (folha ondulada/curvada).
  /// Parte dos 4 cantos (c = 8 valores normalizados TL, TR, BR, BL), acha a
  /// borda real do papel ao longo de cada lado e estica a folha para um
  /// retângulo (interpolação de Coons). Se não achar a borda num ponto,
  /// usa a linha reta ali (igual ao recorte normal).
  static Uint8List warpCurved(Map a) {
    final src = img.decodeImage(a['bytes'] as Uint8List);
    if (src == null) throw Exception('Imagem inválida');
    final c = (a['c'] as List).map((e) => (e as num).toDouble()).toList();
    final sw = src.width, sh = src.height;
    final px = <double>[c[0] * sw, c[2] * sw, c[4] * sw, c[6] * sw];
    final py = <double>[c[1] * sh, c[3] * sh, c[5] * sh, c[7] * sh];

    // máscara do papel (claro x fundo) numa versão pequena, limiar de Otsu
    final kk = math.min(1.0, 500 / math.max(sw, sh));
    final sm = img.copyResize(src,
        width: math.max(8, (sw * kk).round()),
        height: math.max(8, (sh * kk).round()),
        interpolation: img.Interpolation.average);
    final mw = sm.width, mh = sm.height;
    final gray = Uint8List(mw * mh);
    final hist = List<int>.filled(256, 0);
    for (final p in sm) {
      final l = _cl(0.299 * p.r + 0.587 * p.g + 0.114 * p.b);
      gray[p.y * mw + p.x] = l;
      hist[l]++;
    }
    final total = mw * mh;
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }
    var wB = 0, sumB = 0.0, best = 0.0, thr = 128;
    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB, mF = (sumAll - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) {
        best = between;
        thr = t;
      }
    }
    bool paper(double x, double y) {
      final xi = (x * kk).floor(), yi = (y * kk).floor();
      if (xi < 0 || yi < 0 || xi >= mw || yi >= mh) return false;
      return gray[yi * mw + xi] > thr;
    }

    // Um lado: N pontos ao longo da linha reta a->b; para cada um procura a
    // borda do papel vindo de FORA para dentro, pela normal externa.
    const n = 40;
    List<List<double>> side(int ia, int ib) {
      final ax = px[ia], ay = py[ia], bx = px[ib], by = py[ib];
      final len = math.max(1.0, math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)));
      final tx = (bx - ax) / len, ty = (by - ay) / len;
      final nx = ty, ny = -tx; // normal para fora (cantos em sentido horário)
      final r = len * 0.12;
      final step = 1 / kk;
      final off = List<double>.filled(n, 0);
      for (var i = 1; i < n - 1; i++) {
        final u = i / (n - 1);
        final bxp = ax + (bx - ax) * u, byp = ay + (by - ay) * u;
        // já é papel no ponto mais externo: não dá para saber onde é a borda
        if (paper(bxp + nx * r, byp + ny * r)) continue;
        for (var o = r; o > -r; o -= step) {
          if (paper(bxp + nx * o, byp + ny * o) &&
              paper(bxp + nx * (o - step), byp + ny * (o - step))) {
            off[i] = o;
            break;
          }
        }
      }
      // suaviza só o deslocamento (a posição ao longo do lado não muda)
      final smo = List<double>.filled(n, 0);
      for (var i = 1; i < n - 1; i++) {
        var s = 0.0, k = 0;
        for (var j = i - 2; j <= i + 2; j++) {
          if (j < 0 || j >= n) continue;
          s += off[j];
          k++;
        }
        smo[i] = s / k;
      }
      return [
        for (var i = 0; i < n; i++)
          [
            ax + (bx - ax) * i / (n - 1) + nx * smo[i],
            ay + (by - ay) * i / (n - 1) + ny * smo[i],
          ]
      ];
    }

    final top = side(0, 1); // TL -> TR
    final right = side(1, 2); // TR -> BR
    final bot = side(2, 3).reversed.toList(); // BL -> BR
    final left = side(3, 0).reversed.toList(); // TL -> BL

    double lenOf(List<List<double>> e) {
      var s = 0.0;
      for (var i = 1; i < e.length; i++) {
        final dx = e[i][0] - e[i - 1][0], dy = e[i][1] - e[i - 1][1];
        s += math.sqrt(dx * dx + dy * dy);
      }
      return s;
    }

    var w = math.max(lenOf(top), lenOf(bot));
    var h = math.max(lenOf(left), lenOf(right));
    final k = math.min(1.0, maxSide / math.max(w, h));
    final ow = math.max(2, (w * k).round());
    final oh = math.max(2, (h * k).round());

    List<double> at(List<List<double>> e, double u) {
      final f = u * (e.length - 1);
      final i = f.floor().clamp(0, e.length - 2).toInt();
      final t = f - i;
      return [
        e[i][0] + (e[i + 1][0] - e[i][0]) * t,
        e[i][1] + (e[i + 1][1] - e[i][1]) * t,
      ];
    }

    const ins = 0.01;
    final us = [for (var i = 0; i < ow; i++) ins + (i + 0.5) / ow * (1 - 2 * ins)];
    final vs = [for (var j = 0; j < oh; j++) ins + (j + 0.5) / oh * (1 - 2 * ins)];
    final tp = [for (final u in us) at(top, u)];
    final bp = [for (final u in us) at(bot, u)];
    final lp = [for (final v in vs) at(left, v)];
    final rp = [for (final v in vs) at(right, v)];
    final out = img.Image(width: ow, height: oh);
    for (var j = 0; j < oh; j++) {
      final v = vs[j];
      for (var i = 0; i < ow; i++) {
        final u = us[i];
        final fx = (1 - v) * tp[i][0] + v * bp[i][0] + (1 - u) * lp[j][0] + u * rp[j][0] -
            ((1 - u) * (1 - v) * px[0] + u * (1 - v) * px[1] + u * v * px[2] + (1 - u) * v * px[3]);
        final fy = (1 - v) * tp[i][1] + v * bp[i][1] + (1 - u) * lp[j][1] + u * rp[j][1] -
            ((1 - u) * (1 - v) * py[0] + u * (1 - v) * py[1] + u * v * py[2] + (1 - u) * v * py[3]);
        _put(src, out, i, j, fx - 0.5, fy - 0.5);
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

  /// Filtros: original, magic, flatten, bw, gray, enhance
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
    } else if (mode == 'flatten') {
      // Sem desfoque: realça as bordas (nitidez) para as letras pequenas
      // impressas e os desenhos finos não sumirem depois de clarear o papel.
      final soft = img.gaussianBlur(im.clone(), radius: 2);
      for (final p in im) {
        final q = soft.getPixel(p.x, p.y);
        p.r = _cl(p.r + (p.r - q.r) * 1.2);
        p.g = _cl(p.g + (p.g - q.g) * 1.2);
        p.b = _cl(p.b + (p.b - q.b) * 1.2);
      }
      final clean = im;
      _flatten(clean);
      // só pontinhos bem isolados: letras finas impressas ficam
      _despeckle(clean, maxNb: 2);
      return Uint8List.fromList(img.encodeJpg(clean, quality: 90));
    } else {
      // tira o granulado do sensor antes de clarear o papel
      final clean = img.gaussianBlur(im, radius: 1);
      _normalize(clean, bw: mode == 'bw');
      _despeckle(clean);
      return Uint8List.fromList(img.encodeJpg(clean, quality: 90));
    }
    return Uint8List.fromList(img.encodeJpg(im, quality: 88));
  }

  /// Remove sombras/iluminação irregular estimando o fundo (papel) e
  /// dividindo a imagem por ele. Deixa o papel branco e o texto forte.
  static void _normalize(img.Image im, {required bool bw}) {
    final w = im.width, h = im.height;
    // tamanho do bloco proporcional à imagem
    final s = (math.max(w, h) / 110).round().clamp(8, 24);
    final sw = (w / s).ceil(), sh = (h / s).ceil();
    final n = sw * sh;
    final sumL = List<double>.filled(n, 0);
    final cnt = List<int>.filled(n, 0);
    for (final p in im) {
      final b = (p.y ~/ s) * sw + (p.x ~/ s);
      sumL[b] += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      cnt[b]++;
    }
    final meanL =
        List<double>.generate(n, (i) => cnt[i] == 0 ? 0 : sumL[i] / cnt[i]);
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

    // máximo/mínimo local entre blocos
    List<double> rank(List<double> a, int r, bool takeMax) {
      final o = List<double>.filled(n, 0);
      for (var by = 0; by < sh; by++) {
        for (var bx = 0; bx < sw; bx++) {
          var m = takeMax ? -1.0 : 1e9;
          for (var dy = -r; dy <= r; dy++) {
            final yy = (by + dy).clamp(0, sh - 1);
            for (var dx = -r; dx <= r; dx++) {
              final xx = (bx + dx).clamp(0, sw - 1);
              final v = a[yy * sw + xx];
              if (takeMax ? v > m : v < m) m = v;
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

    // "fechamento": máximo (apaga o texto) seguido de mínimo (devolve a
    // borda da sombra ao lugar certo, sem o halo escuro em volta).
    List<double> bgOf(List<double> a) =>
        blur(blur(rank(rank(a, 2, true), 2, false)));
    final fR = bgOf(bgR);
    final fG = bgOf(bgG);
    final fB = bgOf(bgB);

    double samp(List<double> a, double gx, double gy) {
      final x0 = gx.floor(), y0 = gy.floor();
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

    const lo = 0.30, hi = 0.86;
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
        var r = (rr - lo) / (hi - lo);
        var gg = (rg - lo) / (hi - lo);
        var b = (rb - lo) / (hi - lo);
        // reforça as cores (carimbos, logotipos, caneta azul)
        final l = 0.299 * r + 0.587 * gg + 0.114 * b;
        r = l + (r - l) * 1.4;
        gg = l + (gg - l) * 1.4;
        b = l + (b - l) * 1.4;
        p.r = _cl(r * 255);
        p.g = _cl(gg * 255);
        p.b = _cl(b * 255);
      }
    }
  }

  /// "Desamassar": remove vincos, dobras e sombras de papel amassado.
  /// Estima o fundo do papel numa escala fina (segue a sombra de cada dobra,
  /// mas ignora o texto) e divide a imagem por ele. As linhas fracas que
  /// sobram das dobras viram branco; o texto continua escuro.
  static void _flatten(img.Image im) {
    final w = im.width, h = im.height;
    final k = math.min(1.0, 600 / math.max(w, h));
    final sm = img.copyResize(im,
        width: math.max(8, (w * k).round()),
        height: math.max(8, (h * k).round()),
        interpolation: img.Interpolation.average);
    final sw = sm.width, sh = sm.height, n = sw * sh;
    final ch = [Float32List(n), Float32List(n), Float32List(n)];
    for (final p in sm) {
      final i = p.y * sw + p.x;
      ch[0][i] = p.r.toDouble();
      ch[1][i] = p.g.toDouble();
      ch[2][i] = p.b.toDouble();
    }

    // filtro de máximo/mínimo/média separável (linhas e depois colunas)
    Float32List pass(Float32List a, int r, int op, bool horiz) {
      final o = Float32List(n);
      for (var y = 0; y < sh; y++) {
        for (var x = 0; x < sw; x++) {
          var m = op == 0 ? -1.0 : (op == 1 ? 1e9 : 0.0);
          var c = 0;
          for (var d = -r; d <= r; d++) {
            final xx = horiz ? x + d : x, yy = horiz ? y : y + d;
            if (xx < 0 || yy < 0 || xx >= sw || yy >= sh) continue;
            final v = a[yy * sw + xx];
            if (op == 0) {
              if (v > m) m = v;
            } else if (op == 1) {
              if (v < m) m = v;
            } else {
              m += v;
              c++;
            }
          }
          o[y * sw + x] = op == 2 ? m / c : m;
        }
      }
      return o;
    }

    Float32List f2(Float32List a, int r, int op) =>
        pass(pass(a, r, op, true), r, op, false);

    // máximo apaga o texto; mínimo devolve as bordas das sombras ao lugar;
    // média suaviza o fundo.
    final r = (math.max(sw, sh) / 120).round().clamp(3, 9);
    final bg = [
      for (final a in ch) f2(f2(f2(f2(a, r, 0), r, 1), 3, 2), 3, 2)
    ];

    double samp(Float32List a, double gx, double gy) {
      final x0 = gx.floor(), y0 = gy.floor();
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

    // curva suave: dobras fracas somem no branco, texto fica escuro
    const lo = 0.40, hi = 0.85;
    for (final p in im) {
      final gx = p.x * k - 0.5, gy = p.y * k - 0.5;
      final v = <double>[
        p.r / math.max(samp(bg[0], gx, gy), 1.0),
        p.g / math.max(samp(bg[1], gx, gy), 1.0),
        p.b / math.max(samp(bg[2], gx, gy), 1.0),
      ];
      for (var i = 0; i < 3; i++) {
        final t = ((v[i] - lo) / (hi - lo)).clamp(0.0, 1.0).toDouble();
        v[i] = t * t * (3 - 2 * t);
      }
      // mantém as cores (carimbos, caneta azul) um pouco reforçadas
      final l = 0.299 * v[0] + 0.587 * v[1] + 0.114 * v[2];
      p.r = _cl((l + (v[0] - l) * 1.6) * 255);
      p.g = _cl((l + (v[1] - l) * 1.6) * 255);
      p.b = _cl((l + (v[2] - l) * 1.6) * 255);
    }
  }

  /// Apaga pontinhos escuros isolados (ruído) que sobram no papel branco.
  /// Um pixel escuro com poucos vizinhos escuros numa janela 5x5 não é texto.
  static void _despeckle(img.Image im, {int maxNb = 5}) {
    final w = im.width, h = im.height;
    final dark = Uint8List(w * h);
    for (final p in im) {
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      if (l < 220) dark[p.y * w + p.x] = 1;
    }
    for (var y = 2; y < h - 2; y++) {
      for (var x = 2; x < w - 2; x++) {
        if (dark[y * w + x] == 0) continue;
        var nb = 0;
        for (var dy = -2; dy <= 2 && nb <= maxNb; dy++) {
          final row = (y + dy) * w + x;
          for (var dx = -2; dx <= 2; dx++) {
            nb += dark[row + dx];
          }
        }
        if (nb <= maxNb) im.setPixelRgb(x, y, 255, 255, 255);
      }
    }
  }

  /// Detecta automaticamente os 4 cantos do documento.
  /// Devolve 8 valores normalizados (TL, TR, BR, BL) ou lista vazia.
  static List<double> detectCorners(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) return const [];
    final k = 320 / math.max(src.width, src.height);
    final w = math.max(8, (src.width * k).round());
    final h = math.max(8, (src.height * k).round());
    final sm = img.copyResize(src,
        width: w, height: h, interpolation: img.Interpolation.average);
    final n = w * h;

    // "brancura": claro e pouco colorido
    final s = Float64List(n);
    for (final p in sm) {
      final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      s[p.y * w + p.x] = 0.299 * r + 0.587 * g + 0.114 * b - 0.5 * (mx - mn);
    }

    // média e desvio em janela 5x5 (imagem integral)
    final iw = w + 1;
    final ii = Float64List(iw * (h + 1));
    final i2 = Float64List(iw * (h + 1));
    for (var y = 0; y < h; y++) {
      var rs = 0.0, rq = 0.0;
      for (var x = 0; x < w; x++) {
        final v = s[y * w + x];
        rs += v;
        rq += v * v;
        ii[(y + 1) * iw + x + 1] = ii[y * iw + x + 1] + rs;
        i2[(y + 1) * iw + x + 1] = i2[y * iw + x + 1] + rq;
      }
    }
    final v = Float64List(n);
    final sd = Float64List(n);
    for (var y = 0; y < h; y++) {
      final y0 = math.max(0, y - 2), y1 = math.min(h, y + 3);
      for (var x = 0; x < w; x++) {
        final x0 = math.max(0, x - 2), x1 = math.min(w, x + 3);
        final c = ((y1 - y0) * (x1 - x0)).toDouble();
        final a = ii[y1 * iw + x1] - ii[y0 * iw + x1] - ii[y1 * iw + x0] + ii[y0 * iw + x0];
        final q = i2[y1 * iw + x1] - i2[y0 * iw + x1] - i2[y1 * iw + x0] + i2[y0 * iw + x0];
        final m = a / c;
        v[y * w + x] = m;
        sd[y * w + x] = math.sqrt(math.max(0.0, q / c - m * m));
      }
    }

    // limiar de Otsu
    final hist = List<int>.filled(256, 0);
    for (var i = 0; i < n; i++) {
      hist[_cl(v[i])]++;
    }
    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }
    var wb = 0, t = 128;
    var sb = 0.0, best = 0.0;
    for (var i = 0; i < 256; i++) {
      wb += hist[i];
      if (wb == 0) continue;
      final wf = n - wb;
      if (wf == 0) break;
      sb += i * hist[i];
      final mb = sb / wb, mf = (sumAll - sb) / wf;
      final vb = wb.toDouble() * wf * (mb - mf) * (mb - mf);
      if (vb > best) {
        best = vb;
        t = i;
      }
    }
    var loSum = 0.0;
    var loCnt = 0;
    for (var i = 0; i <= t; i++) {
      loSum += i * hist[i];
      loCnt += hist[i];
    }
    final loMean = loCnt == 0 ? 0.0 : loSum / loCnt;
    final low = loMean + 0.15 * (t - loMean);

    // maior região clara = semente do papel
    final lab = Int32List(n);
    final queue = Int32List(n);
    var nLab = 0, bestLab = 0, bestCnt = 0;
    for (var i = 0; i < n; i++) {
      if (v[i] <= t || lab[i] != 0) continue;
      nLab++;
      var qh = 0, qt = 0;
      queue[qt++] = i;
      lab[i] = nLab;
      while (qh < qt) {
        final c = queue[qh++];
        final cx = c % w, cy = c ~/ w;
        for (var d = 0; d < 4; d++) {
          final nx = cx + (d == 0 ? 1 : d == 1 ? -1 : 0);
          final ny = cy + (d == 2 ? 1 : d == 3 ? -1 : 0);
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final ni = ny * w + nx;
          if (lab[ni] == 0 && v[ni] > t) {
            lab[ni] = nLab;
            queue[qt++] = ni;
          }
        }
      }
      if (qt > bestCnt) {
        bestCnt = qt;
        bestLab = nLab;
      }
    }
    if (bestLab == 0) return const [];

    // cresce a região para dentro das sombras (lisas, sem textura)
    final paper = Uint8List(n);
    var qh = 0, qt = 0;
    for (var i = 0; i < n; i++) {
      if (lab[i] == bestLab) {
        paper[i] = 1;
        queue[qt++] = i;
      }
    }
    while (qh < qt) {
      final c = queue[qh++];
      final cx = c % w, cy = c ~/ w;
      for (var d = 0; d < 4; d++) {
        final nx = cx + (d == 0 ? 1 : d == 1 ? -1 : 0);
        final ny = cy + (d == 2 ? 1 : d == 3 ? -1 : 0);
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (paper[ni] == 0 &&
            v[ni] > low &&
            sd[ni] < 8 &&
            (v[ni] - v[c]).abs() < 10) {
          paper[ni] = 1;
          queue[qt++] = ni;
        }
      }
    }

    // preenche buracos (fundo que não toca a borda vira papel)
    final outside = Uint8List(n);
    qh = 0;
    qt = 0;
    void seedOut(int i) {
      if (paper[i] == 0 && outside[i] == 0) {
        outside[i] = 1;
        queue[qt++] = i;
      }
    }

    for (var x = 0; x < w; x++) {
      seedOut(x);
      seedOut((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      seedOut(y * w);
      seedOut(y * w + w - 1);
    }
    while (qh < qt) {
      final c = queue[qh++];
      final cx = c % w, cy = c ~/ w;
      for (var d = 0; d < 4; d++) {
        final nx = cx + (d == 0 ? 1 : d == 1 ? -1 : 0);
        final ny = cy + (d == 2 ? 1 : d == 3 ? -1 : 0);
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        seedOut(ny * w + nx);
      }
    }

    // cantos = extremos de x+y e x-y
    var area = 0;
    var tl = -1, tr = -1, br = -1, bl = -1;
    var vtl = 1 << 30, vbr = -(1 << 30), vtr = -(1 << 30), vbl = 1 << 30;
    for (var i = 0; i < n; i++) {
      if (outside[i] == 1) continue;
      area++;
      final x = i % w, y = i ~/ w;
      final sp = x + y, df = x - y;
      if (sp < vtl) {
        vtl = sp;
        tl = i;
      }
      if (sp > vbr) {
        vbr = sp;
        br = i;
      }
      if (df > vtr) {
        vtr = df;
        tr = i;
      }
      if (df < vbl) {
        vbl = df;
        bl = i;
      }
    }
    final frac = area / n;
    if (tl < 0 || frac < 0.10 || frac > 0.985) return const [];
    final pts = <double>[];
    for (final i in [tl, tr, br, bl]) {
      pts.add(((i % w) + 0.5) / w);
      pts.add(((i ~/ w) + 0.5) / h);
    }
    // área do quadrilátero (deve ser razoável)
    var qa = 0.0;
    for (var i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      qa += pts[i * 2] * pts[j * 2 + 1] - pts[j * 2] * pts[i * 2 + 1];
    }
    if (qa.abs() / 2 < 0.08) return const [];
    return pts;
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
