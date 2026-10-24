import 'dart:io';
import 'package:flutter/material.dart';
import '../services/doc_store.dart';
import 'common.dart';
import 'doc_widgets.dart';
import 'tool_actions.dart';

class HomeTab extends StatefulWidget {
  final void Function(int) goTo;
  const HomeTab({super.key, required this.goTo});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<File> _files = [];
  Set<String> _favs = {};

  @override
  void initState() {
    super.initState();
    _load();
    DocStore.changes.addListener(_load);
  }

  @override
  void dispose() {
    DocStore.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final l = await DocStore.list();
    final f = await DocStore.favorites();
    if (mounted) {
      setState(() {
        _files = l;
        _favs = f;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context;
    final shortcuts = <_Sc>[
      _Sc(Icons.document_scanner, 'Digitalizar', () => ToolActions.scanDocument(c)),
      _Sc(Icons.file_upload_outlined, 'Importar PDF', () => ToolActions.importPdf(c)),
      _Sc(Icons.photo_library_outlined, 'Importar fotos', () => ToolActions.importImages(c)),
      _Sc(Icons.text_fields, 'Texto (OCR)', () => ToolActions.ocrImage(c)),
      _Sc(Icons.badge_outlined, 'Cartão ID', () => ToolActions.idCard(c)),
      _Sc(Icons.qr_code_scanner, 'Leitor QR', () => ToolActions.qr(c)),
      _Sc(Icons.draw_outlined, 'Assinar', () => ToolActions.sign(c)),
      _Sc(Icons.merge_type, 'Mesclar', () => ToolActions.merge(c)),
    ];
    final recents = _files.take(8).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', width: 34, height: 34),
            ),
            const SizedBox(width: 10),
            const Text('DocScan',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GestureDetector(
            onTap: () => widget.goTo(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: kCard, borderRadius: BorderRadius.circular(24)),
              child: const Row(children: [
                Icon(Icons.search, color: Colors.white54),
                SizedBox(width: 10),
                Text('Pesquisar documentos', style: TextStyle(color: Colors.white54)),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.95,
            children: [for (final s in shortcuts) _ShortcutButton(sc: s)],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            const Text('Documentos recentes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: () => widget.goTo(1), child: const Text('Ver todos')),
          ]),
        ),
        if (recents.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                  'Nenhum documento ainda.\nToque em Digitalizar para começar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60)),
            ),
          ),
        for (final f in recents)
          DocTile(
            file: f,
            fav: DocStore.isFav(_favs, f),
            onTap: () => ToolActions.open(context, f),
            onLongPress: () => ToolActions.showDocMenu(context, f),
            onMore: () => ToolActions.showDocMenu(context, f),
          ),
      ],
    );
  }
}

class _Sc {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _Sc(this.icon, this.label, this.onTap);
}

class _ShortcutButton extends StatelessWidget {
  final _Sc sc;
  const _ShortcutButton({required this.sc});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: sc.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
              color: kTeal.withOpacity(0.18), borderRadius: BorderRadius.circular(14)),
          child: Icon(sc.icon, color: kTeal),
        ),
        const SizedBox(height: 6),
        Text(sc.label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(fontSize: 11.5)),
      ]),
    );
  }
}
