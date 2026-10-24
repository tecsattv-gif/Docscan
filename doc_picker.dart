import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/doc_store.dart';
import 'common.dart';

/// Escolher um ou vários PDFs (da biblioteca ou do celular).
/// Devolve a lista na ordem em que foram marcados.
class DocPickerScreen extends StatefulWidget {
  final bool multi;
  final String title;
  const DocPickerScreen({super.key, this.multi = false, this.title = 'Escolher PDF'});
  @override
  State<DocPickerScreen> createState() => _DocPickerScreenState();
}

class _DocPickerScreenState extends State<DocPickerScreen> {
  List<File> _files = [];
  final List<File> _picked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    DocStore.list().then((l) {
      if (mounted) {
        setState(() {
          _files = l;
          _loading = false;
        });
      }
    });
  }

  Future<void> _fromPhone() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: widget.multi);
    if (r == null) return;
    final fs = r.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    if (fs.isEmpty) return;
    if (!widget.multi) {
      if (mounted) Navigator.pop(context, [fs.first]);
      return;
    }
    setState(() {
      for (final f in fs) {
        if (!_files.any((x) => x.path == f.path)) _files.insert(0, f);
        _picked.add(f);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
              tooltip: 'Do celular',
              icon: const Icon(Icons.folder_open),
              onPressed: _fromPhone),
        ],
      ),
      floatingActionButton: widget.multi && _picked.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, List<File>.from(_picked)),
              icon: const Icon(Icons.check),
              label: Text('Concluir (${_picked.length})'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? Center(
                  child: TextButton.icon(
                    onPressed: _fromPhone,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Nenhum documento. Escolher do celular'),
                  ),
                )
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (ctx, i) {
                    final f = _files[i];
                    final idx = _picked.indexWhere((x) => x.path == f.path);
                    return ListTile(
                      leading: Thumb(file: f),
                      title: Text(docName(f), maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(fmtSize(f.lengthSync())),
                      trailing: widget.multi
                          ? (idx >= 0
                              ? CircleAvatar(
                                  radius: 14,
                                  backgroundColor: kTeal,
                                  child: Text('${idx + 1}',
                                      style: const TextStyle(color: Colors.white)))
                              : const Icon(Icons.radio_button_unchecked))
                          : null,
                      onTap: () {
                        if (!widget.multi) {
                          Navigator.pop(context, [f]);
                          return;
                        }
                        setState(() {
                          if (idx >= 0) {
                            _picked.removeAt(idx);
                          } else {
                            _picked.add(f);
                          }
                        });
                      },
                    );
                  },
                ),
    );
  }
}
