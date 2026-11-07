import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'screens/common.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadTheme();
  // Em vez da tela cinza, mostra o erro real na tela (para descobrir a causa).
  ErrorWidget.builder = (details) => Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
          color: const Color(0xFF232326),
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
          child: SingleChildScrollView(
            child: Text(
              'ERRO (tire um print e mande):\n\n'
              '${details.exceptionAsString()}\n\n'
              '${details.stack.toString().split('\n').take(12).join('\n')}',
              style: const TextStyle(
                  color: Color(0xFFFF6B6B), fontSize: 13, height: 1.3,
                  decoration: TextDecoration.none),
            ),
          ),
        ),
      );
  runApp(const DocScanApp());
}

class DocScanApp extends StatelessWidget {
  const DocScanApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (_, mode, __) => MaterialApp(
          title: 'DocScan',
          debugShowCheckedModeBanner: false,
          theme: appTheme(Brightness.light),
          darkTheme: appTheme(Brightness.dark),
          themeMode: mode,
          // Português (menus, calendário, copiar/colar) e textos do editor.
          locale: const Locale('pt', 'PT'),
          supportedLocales: const [Locale('pt', 'PT'), Locale('pt', 'BR'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          // Ícones da barra de status escuros no tema claro e claros no escuro.
          builder: (ctx, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(ctx).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child!,
          ),
          home: const SplashScreen(),
        ),
      );
}
