import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'common.dart';
import 'place_screen.dart' show textPng;

/// Uma marca d'água salva: texto ou imagem (logo, foto, assinatura...).
class SavedWatermark {
  final String id;
  final bool isImage;
  String text; // texto da marca (ou nome da imagem)
  String file; // caminho da imagem (só para imagem)
  int lastUsed;

  SavedWatermark(
      {required this.id,
      required this.isImage,
      this.text = '',
      this.file = '',
      this.lastUsed = 0});

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': isImage ? 'image' : 'text',
        'text': text,
        'file': file,
        'lastUsed': lastUsed,
      };

  static SavedWatermark fromJson(Map<String, dynamic> j) => SavedWatermark(
        id: j['id'] as String,
        isImage: j['type'] == 'image',
        text: (j['text'] ?? '') as String,
        file: (j['file'] ?? '') as String,
        lastUsed: (j['lastUsed'] ?? 0) as int,
      );
}

/// O que o usuário escolheu: o PNG pronto e se é imagem ou texto.
class WatermarkPick {
  final Uint8List png;
  final bool isImage;
  WatermarkPick(this.png, this.isImage);
}

/// Biblioteca de marcas d'água salvas no celular.
class WatermarkLibrary {
  static const _key = 'wm_library';
  static final ImagePicker _picker = ImagePicker();

  static Future<List<SavedWatermark>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    var list = <SavedWatermark>[];
    if (raw != null) {
      try {
        list = (jsonDecode(raw) as List)
            .map((e) => SavedWatermark.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    } else {
      // Primeira vez: aproveita o último texto usado na versão anterior.
      final old = p.getString('wm_text');
      if (old != null && old.trim().isNotEmpty) {
        list = [SavedWatermark(id: _newId(), isImage: false, text: old.trim())];
        await save(list);
      }
    }
    // imagens apagadas por fora somem da lista
    list.removeWhere((w) => w.isImage && !File(w.file).existsSync());
    list.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    return list;
  }

  static Future<void> save(List<SavedWatermark> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((w) => w.toJson()).toList()));
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  static Future<String> _imageDir() async {
    final d = await getApplicationDocumentsDirectory();
    final dir = Directory('${d.path}${Platform.pathSeparator}watermarks');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static Future<String?> _pickImageToFile(String id) async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90, maxWidth: 1600);
    if (x == null) return null;
    final path = '${await _imageDir()}${Platform.pathSeparator}$id.img';
    await File(path).writeAsBytes(await x.readAsBytes());
    return path;
  }

  static Future<WatermarkPick> render(SavedWatermark w) async {
    if (w.isImage) return WatermarkPick(await File(w.file).readAsBytes(), true);
    return WatermarkPick(await textPng(w.text), false);
  }

  /// Abre a lista de marcas salvas. Devolve a marca escolhida (ou null).
  static Future<WatermarkPick?> pick(BuildContext c) async {
    final list = await load();
    if (!c.mounted) return null;
    final chosen = await showModalBottomSheet<SavedWatermark>(
      context: c,
      isScrollControlled: true,
      builder: (_) => _LibrarySheet(initial: list),
    );
    if (chosen == null) return null;
    // marca como a mais recente
    final all = await load();
    for (final w in all) {
      if (w.id == chosen.id) w.lastUsed = DateTime.now().millisecondsSinceEpoch;
    }
    await save(all);
    return render(chosen);
  }
}

class _LibrarySheet extends StatefulWidget {
  final List<SavedWatermark> initial;
  const _LibrarySheet({required this.initial});

  @override
  State<_LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<_LibrarySheet> {
  late List<SavedWatermark> items = [...widget.initial];

  Future<void> _persist() => WatermarkLibrary.save(items);

  Future<void> _newText() async {
    final t = await askText(context, 'Nova marca d\'água (texto)',
        hint: 'Ex.: CONFIDENCIAL ou seu nome');
    if (t == null || t.trim().isEmpty || !mounted) return;
    final w = SavedWatermark(
        id: WatermarkLibrary._newId(), isImage: false, text: t.trim());
    setState(() => items.insert(0, w));
    await _persist();
  }

  Future<void> _newImage() async {
    final id = WatermarkLibrary._newId();
    final path = await WatermarkLibrary._pickImageToFile(id);
    if (path == null || !mounted) return;
    final name = await askText(context, 'Nome da marca d\'água',
        initial: 'Logo', hint: 'Ex.: Logo da empresa');
    if (!mounted) return;
    final w = SavedWatermark(
        id: id,
        isImage: true,
        file: path,
        text: (name == null || name.trim().isEmpty) ? 'Imagem' : name.trim());
    setState(() => items.insert(0, w));
    await _persist();
  }

  Future<void> _edit(SavedWatermark w) async {
    if (!w.isImage) {
      final t = await askText(context, 'Alterar texto da marca d\'água',
          initial: w.text);
      if (t == null || t.trim().isEmpty || !mounted) return;
      setState(() => w.text = t.trim());
    } else {
      final op = await choose(context, w.text, ['Trocar a imagem', 'Renomear']);
      if (op == null || !mounted) return;
      if (op == 0) {
        final path = await WatermarkLibrary._pickImageToFile(
            '${w.id}_${DateTime.now().millisecondsSinceEpoch}');
        if (path == null || !mounted) return;
        final old = w.file;
        setState(() => w.file = path);
        try {
          File(old).deleteSync();
        } catch (_) {}
        // força recarregar a miniatura
        imageCache.clear();
      } else {
        final t = await askText(context, 'Nome da marca d\'água',
            initial: w.text);
        if (t == null || t.trim().isEmpty || !mounted) return;
        setState(() => w.text = t.trim());
      }
    }
    await _persist();
  }

  Future<void> _delete(SavedWatermark w) async {
    final ok = await confirm(context, 'Apagar marca d\'água?',
        w.isImage ? w.text : '"${w.text}"',
        ok: 'Apagar');
    if (!ok || !mounted) return;
    setState(() => items.removeWhere((x) => x.id == w.id));
    if (w.isImage) {
      try {
        File(w.file).deleteSync();
      } catch (_) {}
    }
    await _persist();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.8;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Marca d\'água',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  items.isEmpty
                      ? 'Crie uma marca d\'água. Ela fica salva para as próximas vezes.'
                      : 'Toque numa marca salva para usar. Lápis para alterar, lixeira para apagar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.muted)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final w in items)
                    ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: w.isImage
                            ? Image.file(File(w.file),
                                key: ValueKey(w.file), fit: BoxFit.contain)
                            : const Icon(Icons.text_fields,
                                color: Colors.black54),
                      ),
                      title: Text(w.text,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(w.isImage ? 'Imagem' : 'Texto'),
                      onTap: () => Navigator.pop(context, w),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              tooltip: 'Alterar',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(w)),
                          IconButton(
                              tooltip: 'Apagar',
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () => _delete(w)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _newText,
                      icon: const Icon(Icons.add),
                      label: const Text('Novo texto'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _newImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Nova imagem'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
