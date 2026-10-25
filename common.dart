import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/doc_store.dart';

const kTeal = Color(0xFF19B394);
const kBg = Color(0xFF232326);
const kCard = Color(0xFF323236);

// ---- Tema claro / escuro ----
/// Tema escolhido pelo usuário (Automático, Claro ou Escuro).
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.dark);
const themeNames = ['Automático (igual ao celular)', 'Claro', 'Escuro'];
const _themeModes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];

Future<void> loadTheme() async {
  final p = await SharedPreferences.getInstance();
  final i = p.getInt('theme_mode') ?? 2; // padrão: escuro (como antes)
  themeMode.value = _themeModes[i.clamp(0, 2)];
}

Future<void> setTheme(int i) async {
  themeMode.value = _themeModes[i];
  final p = await SharedPreferences.getInstance();
  await p.setInt('theme_mode', i);
}

int get themeIndex => _themeModes.indexOf(themeMode.value);

ThemeData appTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? kBg : const Color(0xFFF6F7F8);
  return ThemeData(
    brightness: b,
    colorSchemeSeed: kTeal,
    scaffoldBackgroundColor: bg,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1C1C1E) : Colors.white,
      indicatorColor: kTeal.withOpacity(0.25),
    ),
  );
}

/// Cores que mudam com o tema.
extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  /// Fundo de cartões, botões e caixa de pesquisa.
  Color get card => isDark ? kCard : const Color(0xFFE9ECEE);
  /// Fundo das barras de baixo.
  Color get bar => isDark ? kBg : Colors.white;
  /// Texto secundário (cinza).
  Color get muted => isDark ? Colors.white60 : Colors.black54;
}

void toast(BuildContext c, String m, {String? action, VoidCallback? onAction}) {
  if (!c.mounted) return;
  final sm = ScaffoldMessenger.of(c);
  sm.hideCurrentSnackBar();
  sm.showSnackBar(SnackBar(
    content: Text(m),
    action: action == null
        ? null
        : SnackBarAction(label: action, onPressed: onAction ?? () {}),
  ));
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String docName(File f) {
  final n = f.path.split(Platform.pathSeparator).last;
  return n.toLowerCase().endsWith('.pdf') ? n.substring(0, n.length - 4) : n;
}

Future<String?> askText(BuildContext c, String title,
    {String initial = '', String hint = '', bool obscure = false}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        obscureText: obscure,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            child: const Text('OK')),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext c, String title, String msg,
    {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<int?> choose(BuildContext c, String title, List<String> options) {
  return showModalBottomSheet<int>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          for (var i = 0; i < options.length; i++)
            ListTile(
                title: Text(options[i]), onTap: () => Navigator.pop(ctx, i)),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Mostra uma caixa de "aguarde" enquanto roda uma tarefa.
class Busy {
  static Future<T?> run<T>(
      BuildContext context, String msg, Future<T> Function() job) async {
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(children: [
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 18),
            Expanded(child: Text(msg)),
          ]),
        ),
      ),
    );
    try {
      return await job();
    } catch (e) {
      toast(context, 'Erro: $e');
      return null;
    } finally {
      nav.pop();
    }
  }
}

class DocThumb extends StatelessWidget {
  final File file;
  final double width;
  final double height;
  const DocThumb({super.key, required this.file, this.width = 48, this.height = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: FutureBuilder<File?>(
        future: DocStore.thumb(file),
        builder: (_, s) {
          final f = s.data;
          if (f == null) {
            return const Icon(Icons.picture_as_pdf, color: Colors.redAccent);
          }
          return Image.file(f, fit: BoxFit.cover, width: width, height: height);
        },
      ),
    );
  }
}
