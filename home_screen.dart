import 'dart:io';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../services/doc_store.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _docs = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await DocStore.list();
    if (mounted) setState(() => _docs = d);
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<String?> _askName(String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome do documento'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Salvar')),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    try {
      final pics = await CunningDocumentScanner.getPictures(noOfPages: 30);
      if (pics == null || pics.isEmpty) return;
      final name = await _askName(
          'Scan ${DateFormat('dd-MM-yyyy HH-mm').format(DateTime.now())}');
      if (name == null || name.isEmpty) return;
      final f = await DocStore.saveImagesAsPdf(pics, name);
      await _load();
      if (mounted) _open(f);
    } catch (e) {
      _msg('Erro ao escanear: $e');
    }
  }

  Future<void> _import() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = r?.files.single.path;
    if (path == null) return;
    final f = await DocStore.importPdf(path);
    await _load();
    if (mounted) _open(f);
  }

  void _open(File f) => Navigator.push(
          context, MaterialPageRoute(builder: (_) => ViewerScreen(file: f)))
      .then((_) => _load());

  Future<void> _menu(String action, File f) async {
    if (action == 'share') {
      await Share.shareXFiles([XFile(f.path)]);
    } else if (action == 'rename') {
      final n = await _askName(_title(f));
      if (n != null && n.isNotEmpty) {
        await DocStore.rename(f, n);
        _load();
      }
    } else if (action == 'delete') {
      await DocStore.delete(f);
      _load();
    }
  }

  String _title(File f) =>
      f.path.split(Platform.pathSeparator).last.replaceAll('.pdf', '');

  @override
  Widget build(BuildContext context) {
    final shown = _docs
        .where((f) => _title(f).toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus documentos'),
        actions: [
          IconButton(
              icon: const Icon(Icons.file_open),
              tooltip: 'Abrir PDF',
              onPressed: _import),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      body: shown.isEmpty
          ? const Center(child: Text('Nenhum documento ainda'))
          : ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final f = shown[i];
                final date =
                    DateFormat('dd/MM/yyyy HH:mm').format(f.statSync().modified);
                return ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(_title(f)),
                  subtitle: Text(date),
                  onTap: () => _open(f),
                  trailing: PopupMenuButton<String>(
                    onSelected: (a) => _menu(a, f),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'share', child: Text('Compartilhar')),
                      PopupMenuItem(value: 'rename', child: Text('Renomear')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.document_scanner),
        label: const Text('Escanear'),
      ),
    );
  }
}
