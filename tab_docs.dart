import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/doc_store.dart';
import 'common.dart';
import 'doc_widgets.dart';
import 'tool_actions.dart';

class DocsTab extends StatefulWidget {
  const DocsTab({super.key});
  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  List<File> _files = [];
  Set<String> _favs = {};
  String _q = '';
  String _sort = 'date';
  bool _grid = false;
  bool _onlyFav = false;
  final Set<String> _sel = {};

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
        _sel.removeWhere((p) => !l.any((x) => x.path == p));
      });
    }
  }

  List<File> get _view {
    var l = _files
        .where((f) => docName(f).toLowerCase().contains(_q.toLowerCase()))
        .where((f) => !_onlyFav || DocStore.isFav(_favs, f))
        .toList();
    if (_sort == 'name') {
      l.sort((a, b) => docName(a).toLowerCase().compareTo(docName(b).toLowerCase()));
    } else if (_sort == 'size') {
      l.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
    }
    return l;
  }

  void _tap(File f) {
    if (_sel.isNotEmpty) {
      _toggle(f);
    } else {
      ToolActions.open(context, f);
    }
  }

  void _toggle(File f) {
    setState(() {
      if (!_sel.add(f.path)) _sel.remove(f.path);
    });
  }

  List<File> get _selFiles =>
      _files.where((f) => _sel.contains(f.path)).toList();

  Future<void> _deleteSel() async {
    final n = _sel.length;
    if (!await confirm(context, 'Excluir', 'Excluir $n documento(s)?', ok: 'Excluir')) {
      return;
    }
    for (final f in _selFiles) {
      await DocStore.delete(f);
    }
    setState(_sel.clear);
  }

  @override
  Widget build(BuildContext context) {
    final list = _view;
    final selecting = _sel.isNotEmpty;
    return Column(children: [
      if (selecting)
        Container(
          color: kCard,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.close), onPressed: () => setState(_sel.clear)),
            Text('${_sel.length} selecionado(s)'),
            const Spacer(),
            if (_sel.length >= 2)
              IconButton(
                  tooltip: 'Mesclar',
                  icon: const Icon(Icons.merge_type),
                  onPressed: () async {
                    final fs = _selFiles;
                    setState(_sel.clear);
                    await ToolActions.merge(context, files: fs);
                  }),
            IconButton(
                tooltip: 'Compartilhar',
                icon: const Icon(Icons.share),
                onPressed: () async {
                  await Share.shareXFiles(
                      _selFiles.map((f) => XFile(f.path)).toList());
                }),
            IconButton(
                tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _deleteSel),
          ]),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'Pesquisar',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: kCard,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Favoritos',
              icon: Icon(_onlyFav ? Icons.star : Icons.star_border,
                  color: _onlyFav ? Colors.amber : null),
              onPressed: () => setState(() => _onlyFav = !_onlyFav),
            ),
            IconButton(
              tooltip: 'Grade/Lista',
              icon: Icon(_grid ? Icons.view_list : Icons.grid_view),
              onPressed: () => setState(() => _grid = !_grid),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              onSelected: (v) => setState(() => _sort = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'date', child: Text('Mais recentes')),
                PopupMenuItem(value: 'name', child: Text('Nome (A-Z)')),
                PopupMenuItem(value: 'size', child: Text('Maiores primeiro')),
              ],
            ),
          ]),
        ),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text(
                    _files.isEmpty
                        ? 'Nenhum documento ainda'
                        : 'Nada encontrado',
                    style: const TextStyle(color: Colors.white60)),
              )
            : _grid
                ? GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: 0.78, crossAxisSpacing: 10, mainAxisSpacing: 10),
                    itemCount: list.length,
                    itemBuilder: (_, i) => DocCard(
                      file: list[i],
                      fav: DocStore.isFav(_favs, list[i]),
                      selected: _sel.contains(list[i].path),
                      onTap: () => _tap(list[i]),
                      onLongPress: () => _toggle(list[i]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: list.length,
                    itemBuilder: (_, i) => DocTile(
                      file: list[i],
                      fav: DocStore.isFav(_favs, list[i]),
                      selected: _sel.contains(list[i].path),
                      selecting: selecting,
                      onTap: () => _tap(list[i]),
                      onLongPress: () => _toggle(list[i]),
                      onMore: () => ToolActions.showDocMenu(context, list[i]),
                    ),
                  ),
      ),
    ]);
  }
}
