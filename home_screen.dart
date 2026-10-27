import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'common.dart';
import 'tab_docs.dart';
import 'tab_home.dart';
import 'tab_me.dart';
import 'tab_tools.dart';
import 'tool_actions.dart';
import 'tutorial_screen.dart';

/// Estrutura principal com as 4 abas (Início, Documentos, Ferramentas, Eu).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _i = 0;

  // PDFs abertos de fora ("Abrir com" / "Compartilhar")
  static const _open = MethodChannel('docscan/open');

  @override
  void initState() {
    super.initState();
    _open.setMethodCallHandler((call) async {
      if (call.method == 'fileOpened' && call.arguments is String) {
        _show(call.arguments as String);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      String? p;
      try {
        p = await _open.invokeMethod<String>('initialFile');
        if (p != null) _show(p);
      } catch (_) {}
      // Primeira vez no app: mostra o vídeo "Como usar" uma única vez
      // (não aparece se o app foi aberto para ver um PDF de fora).
      if (p == null) await _firstRunTutorial();
    });
  }

  Future<void> _firstRunTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('tutorial_visto') ?? false) return;
    await prefs.setBool('tutorial_visto', true);
    if (!mounted) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const TutorialScreen()));
  }

  void _show(String path) {
    if (!mounted) return;
    final f = File(path);
    if (!f.existsSync()) return;
    ToolActions.open(context, f);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      HomeTab(goTo: (i) => setState(() => _i = i)),
      DocsTab(active: _i == 1),
      const ToolsTab(),
      const MeTab(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _i, children: tabs)),
      floatingActionButton: (_i == 0 || _i == 1)
          ? FloatingActionButton.extended(
              backgroundColor: kTeal,
              foregroundColor: Colors.white,
              onPressed: () => ToolActions.scanDocument(context),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Digitalizar'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Documentos'),
          NavigationDestination(icon: Icon(Icons.apps), selectedIcon: Icon(Icons.apps), label: 'Ferramentas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Eu'),
        ],
      ),
    );
  }
}
