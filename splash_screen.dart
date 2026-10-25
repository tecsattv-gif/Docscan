import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';

/// Versão mostrada na abertura. Atualize junto com "version:" no pubspec.yaml.
const kAppVersion = '2.0.0';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween(begin: 0.8, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/logo.png', width: 128, height: 128),
                        const SizedBox(height: 24),
                        const Text('DocScan',
                            style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        const SizedBox(height: 8),
                        const Text('Digitalize. Organize. Compartilhe.',
                            style:
                                TextStyle(fontSize: 14, color: Colors.white60)),
                        const SizedBox(height: 12),
                        const Text('Versão $kAppVersion',
                            style:
                                TextStyle(fontSize: 13, color: Colors.white38)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            FadeTransition(
              opacity: _fade,
              child: const Padding(
                padding: EdgeInsets.only(bottom: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Criado por Luiz Alberto Cardoso',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70)),
                    SizedBox(height: 4),
                    Text('Email: tecsattv@gmail.com',
                        style: TextStyle(fontSize: 13, color: Colors.white54)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
