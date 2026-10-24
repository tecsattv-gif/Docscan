import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() => runApp(const DocScanApp());

class DocScanApp extends StatelessWidget {
  const DocScanApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'DocScan',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF19B394),
          scaffoldBackgroundColor: const Color(0xFF2A2A2E),
          useMaterial3: true,
        ),
        home: const SplashScreen(),
      );
}
