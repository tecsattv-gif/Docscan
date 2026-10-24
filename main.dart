import 'package:flutter/material.dart';
import 'screens/common.dart';
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
