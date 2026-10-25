import 'package:flutter/material.dart';
import 'screens/common.dart';
import 'screens/splash_screen.dart';

void main() {
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
  Widget build(BuildContext context) => MaterialApp(
        title: 'DocScan',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: kTeal,
          scaffoldBackgroundColor: kBg,
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: kBg,
            surfaceTintColor: Colors.transparent,
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: const Color(0xFF1C1C1E),
            indicatorColor: kTeal.withOpacity(0.25),
          ),
        ),
        home: const SplashScreen(),
      );
}
