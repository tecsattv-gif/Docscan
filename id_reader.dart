/// Leitura dos dados de um documento de identidade a partir do texto do OCR:
/// faixa MRZ (linhas com <<<, de passaporte, RG novo, Cartão de Cidadão...)
/// e campos comuns (CPF, datas, nome...). Só Dart puro, sem Flutter.
class IdReader {
  /// Monta o relatório que aparece na tela de texto.
  static String report(String ocrText) {
    final out = StringBuffer();
    final mrz = parseMrz(ocrText);
    if (mrz != null) {
      out.writeln('━━ FAIXA MRZ ━━');
      mrz.forEach((k, v) => out.writeln('$k: $v'));
      out.writeln();
    }

    final fields = parseFields(ocrText);
    if (fields.isNotEmpty) {
      out.writeln('━━ DADOS ENCONTRADOS ━━');
      fields.forEach((k, v) => out.writeln('$k: $v'));
      out.writeln();
    }

    if (mrz == null && fields.isEmpty) {
      out.writeln('Não encontrei campos conhecidos. Confira o texto abaixo.');
      out.writeln();
    }
    out.writeln('━━ TEXTO COMPLETO ━━');
    out.write(ocrText.trim());
    return out.toString();
  }

  // ------------------------------------------------------------------
  // MRZ
  // ------------------------------------------------------------------

  /// Corrige o que o OCR costuma errar numa linha MRZ.
  static String _cleanMrzLine(String s) => s
      .toUpperCase()
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll(RegExp(r'[«‹<(\[{]'), '<')
      .replaceAll(RegExp(r'[^A-Z0-9<]'), '');

  static Map<String, String>? parseMrz(String text) {
    final lines = text
        .split('\n')
        .map(_cleanMrzLine)
        .where((l) => l.length >= 26 && '<'.allMatches(l).length >= 2)
        .toList();
    if (lines.isEmpty) return null;

    String fit(String l, int n) =>
        l.length >= n ? l.substring(0, n) : l.padRight(n, '<');

    // Escolhe o formato pelo tamanho das linhas.
    final avg = lines.map((l) => l.length).reduce((a, b) => a + b) / lines.length;
    if (avg >= 40 && lines.length >= 2) {
      return _td3(fit(lines[lines.length - 2], 44), fit(lines.last, 44), 44);
    }
    if (avg >= 34 && lines.length >= 2) {
      return _td3(fit(lines[lines.length - 2], 36), fit(lines.last, 36), 36);
    }
    if (lines.length >= 3) {
      final n = lines.length;
      return _td1(fit(lines[n - 3], 30), fit(lines[n - 2], 30), fit(lines[n - 1], 30));
    }
    return null;
  }

  /// Cartões (RG novo, Cartão de Cidadão, carte d'identité): 3 linhas de 30.
  static Map<String, String> _td1(String l1, String l2, String l3) {
    final m = <String, String>{};
    m['Tipo'] = _docType(l1.substring(0, 2));
    m['País emissor'] = _txt(l1.substring(2, 5));
    m['Nº do documento'] =
        _chk(_txt(l1.substring(5, 14)), l1.substring(5, 14), l1[14]);
    final opt1 = _txt(l1.substring(15, 30));
    if (opt1.isNotEmpty) m['Dados extras'] = opt1;
    _names(l3, m);
    m['Nascimento'] = _chk(_date(l2.substring(0, 6), false), _num(l2.substring(0, 6)), l2[6]);
    m['Sexo'] = _sex(l2[7]);
    m['Validade'] = _chk(_date(l2.substring(8, 14), true), _num(l2.substring(8, 14)), l2[14]);
    m['Nacionalidade'] = _txt(l2.substring(15, 18));
    final opt2 = _txt(l2.substring(18, 29));
    if (opt2.isNotEmpty) m['Dados extras 2'] = opt2;
    return m;
  }

  /// Passaporte (2 linhas de 44) e TD2 (2 linhas de 36).
  static Map<String, String> _td3(String l1, String l2, int n) {
    final m = <String, String>{};
    m['Tipo'] = _docType(l1.substring(0, 2));
    m['País emissor'] = _txt(l1.substring(2, 5));
    _names(l1.substring(5), m);
    m['Nº do documento'] =
        _chk(_txt(l2.substring(0, 9)), l2.substring(0, 9), l2[9]);
    m['Nacionalidade'] = _txt(l2.substring(10, 13));
    m['Nascimento'] = _chk(_date(l2.substring(13, 19), false), _num(l2.substring(13, 19)), l2[19]);
    m['Sexo'] = _sex(l2[20]);
    m['Validade'] = _chk(_date(l2.substring(21, 27), true), _num(l2.substring(21, 27)), l2[27]);
    if (n == 44) {
      final pn = _txt(l2.substring(28, 42));
      if (pn.isNotEmpty) m['Nº pessoal'] = pn;
    }
    return m;
  }

  static void _names(String s, Map<String, String> m) {
    // OCR às vezes lê "<" como "K"; nomes reais quase nunca têm "KK".
    final fixed = s.replaceAll(RegExp(r'K{2,}'), '<<');
    final parts = fixed.split('<<');
    final sur = parts.first.replaceAll('<', ' ').trim();
    final given = parts.skip(1).join(' ').replaceAll('<', ' ').trim();
    if (sur.isNotEmpty) m['Sobrenome'] = _title(sur);
    if (given.isNotEmpty) m['Nome'] = _title(given.replaceAll(RegExp(r'\s+'), ' '));
  }

  static String _docType(String t) {
    final c = t.replaceAll('<', '');
    if (c.startsWith('P')) return 'Passaporte ($c)';
    if (c.startsWith('I') || c.startsWith('A') || c.startsWith('C')) {
      return 'Documento de identidade ($c)';
    }
    return c;
  }

  static String _sex(String s) => s == 'M'
      ? 'Masculino'
      : s == 'F'
          ? 'Feminino'
          : 'Não informado';

  static String _txt(String s) => s.replaceAll('<', ' ').trim();

  /// Em campos numéricos o OCR troca letras parecidas por números.
  static String _num(String s) => s
      .replaceAll('O', '0')
      .replaceAll('Q', '0')
      .replaceAll('D', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1')
      .replaceAll('Z', '2')
      .replaceAll('S', '5')
      .replaceAll('B', '8')
      .replaceAll('G', '6');

  static String _date(String s, bool future) {
    final d = _num(s);
    if (!RegExp(r'^\d{6}$').hasMatch(d)) return s;
    final yy = int.parse(d.substring(0, 2));
    final now = DateTime.now().year % 100;
    final century = future ? 2000 : (yy > now ? 1900 : 2000);
    return '${d.substring(4, 6)}/${d.substring(2, 4)}/${century + yy}';
  }

  /// Dígito verificador ICAO 9303 (pesos 7-3-1).
  static int _digit(String s) {
    const w = [7, 3, 1];
    var sum = 0;
    for (var i = 0; i < s.length; i++) {
      final ch = s.codeUnitAt(i);
      int v;
      if (ch >= 48 && ch <= 57) {
        v = ch - 48;
      } else if (ch >= 65 && ch <= 90) {
        v = ch - 55;
      } else {
        v = 0;
      }
      sum += v * w[i % 3];
    }
    return sum % 10;
  }

  static String _chk(String shown, String raw, String check) {
    final c = _num(check);
    if (!RegExp(r'^\d$').hasMatch(c)) return '$shown  ⚠ conferir';
    return _digit(raw) == int.parse(c) ? '$shown  ✓' : '$shown  ⚠ conferir';
  }

  static String _title(String s) => s
      .toLowerCase()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  // ------------------------------------------------------------------
  // Campos comuns (RG, CNH, Cartão de Cidadão, carte d'identité)
  // ------------------------------------------------------------------

  /// Rótulo impresso no documento → nome do campo no relatório.
  static const _labels = <String, String>{
    'NOME SOCIAL': 'Nome social',
    'NOME': 'Nome',
    'APELIDO': 'Apelido(s)',
    'NOM': 'Nom',
    'PRÉNOM': 'Prénom(s)',
    'PRENOM': 'Prénom(s)',
    'FILIAÇÃO': 'Filiação',
    'FILIACAO': 'Filiação',
    'NATURALIDADE': 'Naturalidade',
    'NACIONALIDADE': 'Nacionalidade',
    'REGISTRO GERAL': 'RG',
    'Nº REGISTRO': 'Nº registro',
    'N° REGISTRO': 'Nº registro',
    'DOC. IDENTIDADE': 'Doc. identidade',
    'N.º DOCUMENTO': 'Nº do documento',
    'Nº DOCUMENTO': 'Nº do documento',
    'NÚMERO DE IDENTIFICAÇÃO CIVIL': 'Nº identificação civil',
    'NIF': 'NIF',
    'DATA DE NASCIMENTO': 'Nascimento',
    'DATA NASCIMENTO': 'Nascimento',
    'DATA DE EXPEDIÇÃO': 'Expedição',
    'DATA EXPEDIÇÃO': 'Expedição',
    'DATA DE EMISSÃO': 'Emissão',
    'VALIDADE': 'Validade',
    'DATA DE VALIDADE': 'Validade',
    'CATEGORIA': 'Categoria (CNH)',
  };

  static Map<String, String> parseFields(String text) {
    final m = <String, String>{};
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // CPF
    final cpf = RegExp(r'\b(\d{3})[.\s]?(\d{3})[.\s]?(\d{3})[-\s/]?(\d{2})\b');
    for (final c in cpf.allMatches(text)) {
      final d = '${c[1]}${c[2]}${c[3]}${c[4]}';
      if (_cpfOk(d)) {
        m['CPF'] = '${c[1]}.${c[2]}.${c[3]}-${c[4]}  ✓';
        break;
      }
    }

    // Rótulo numa linha, valor na mesma linha ou na seguinte.
    // Os rótulos mais longos são testados primeiro ("NOME SOCIAL" antes de "NOME").
    final keys = _labels.keys.toList()..sort((a, b) => b.length - a.length);
    for (var i = 0; i < lines.length; i++) {
      final up = lines[i].toUpperCase();
      for (final k in keys) {
        if (!up.startsWith(k)) continue;
        final field = _labels[k]!;
        if (m.containsKey(field)) break;
        var rest = lines[i].substring(k.length).replaceFirst(RegExp(r'^(\([Ss]\))?[\s:/.]*'), '').trim();
        if (rest.length < 2 && i + 1 < lines.length && !_isLabel(lines[i + 1], keys)) {
          rest = lines[i + 1];
        }
        if (rest.length >= 2) m[field] = rest;
        break;
      }
    }

    // Datas soltas (quando não vieram pelos rótulos).
    final dates = RegExp(r'\b\d{2}[/.\-]\d{2}[/.\-]\d{4}\b')
        .allMatches(text)
        .map((d) => d[0]!.replaceAll(RegExp(r'[.\-]'), '/'))
        .toSet()
        .toList();
    if (dates.isNotEmpty) m['Datas no documento'] = dates.join(', ');
    return m;
  }

  static bool _isLabel(String line, List<String> keys) {
    final up = line.toUpperCase();
    return keys.any(up.startsWith);
  }

  static bool _cpfOk(String d) {
    if (d.length != 11 || RegExp(r'^(\d)\1{10}$').hasMatch(d)) return false;
    int dv(int len) {
      var s = 0;
      for (var i = 0; i < len; i++) {
        s += int.parse(d[i]) * (len + 1 - i);
      }
      final r = (s * 10) % 11;
      return r == 10 ? 0 : r;
    }

    return dv(9) == int.parse(d[9]) && dv(10) == int.parse(d[10]);
  }
}
