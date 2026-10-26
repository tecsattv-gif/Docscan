import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/doc_store.dart';
import 'common.dart';
import 'doc_widgets.dart';
import 'tool_actions.dart';

class DocsTab extends StatefulWidget {
  /// true quando esta aba está na tela (para o botão Voltar e para salvar
  /// os documentos novos na pasta aberta).
  final bool active;
  const DocsTab({super.key, this.active = false});
  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  List<File> _files = [];
  List<String> _folders = [];
  String? _folder; // pasta aberta (null = início)
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
  void didUpdateWidget(covariant DocsTab old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncTarget();
  }

  @override
  void dispose() {
    DocStore.changes.removeListener(_load);
    super.dispose();
  }

  /// Documentos digitalizados com esta aba aberta vão para a pasta aberta.
  void _syncTarget() => DocStore.saveTarget = widget.active ? _folder : null;

  void _openFolder(String? name) {
    setState(() {
      _folder = name;
      _sel.clear();
    });
    _syncTarget();
  }

  Future<void> _load() async {
    final l = await DocStore.list();
    final fo = await DocStore.folders();
    final f = await DocStore.favorites();
    if (mounted) {
      setState(() {
        _files = l;
        _folders = fo;
        if (_folder != null && !fo.contains(_folder)) _folder = null;
        _favs = f;
        _sel.removeWhere((p) => !l.any((x) => x.path == p));
      });
    }
  }

  /// Pesquisa e favoritos, no início, mostram documentos de todas as pastas.
  bool get _searchAll => _folder == null && (_q.isNotEmpty || _onlyFav);

  List<File> get _view {
    var l = _files
        .where((f) => _searchAll || DocStore.folderOf(f) == _folder)
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

  int _countIn(String folder) =>
      _files.where((f) => DocStore.folderOf(f) == folder).length;

  Future<void> _newFolder() async {
    final n = await askText(context, 'Nova pasta', hint: 'ex: Trabalho, Pessoal, Contas');
    if (n == null || n.trim().isEmpty) return;
    await DocStore.createFolder(n);
  }

  Future<void> _folderMenu(String name) async {
    final i = await choose(context, '📁 $name', ['Abrir', 'Renomear', 'Excluir pasta']);
    if (i == null || !mounted) return;
    if (i == 0) {
      _openFolder(name);
    } else if (i == 1) {
      final n = await askText(context, 'Renomear pasta', initial: name);
      if (n == null || n.trim().isEmpty) return;
      final r = await DocStore.renameFolder(name, n);
      if (_folder == name) _openFolder(r);
    } else {
      final count = _countIn(name);
      var keep = true;
      if (count > 0) {
        final k = await choose(context, 'Excluir "$name" ($count documento(s))', [
          'Excluir só a pasta (documentos vão para o início)',
          'Excluir a pasta E os documentos',
        ]);
        if (k == null || !mounted) return;
        keep = k == 0;
        if (!keep &&
            !await confirm(context, 'Excluir tudo',
                'Apagar a pasta "$name" e os $count documento(s) dentro dela?',
                ok: 'Excluir')) {
          return;
        }
      }
      await DocStore.deleteFolder(name, keepDocs: keep);
      if (_folder == name) _openFolder(null);
    }
  }

  Widget _folderTile(String name) => ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: kTeal.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.folder, color: kTeal),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${_countIn(name)} documento(s)',
            style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
            icon: const Icon(Icons.more_vert), onPressed: () => _folderMenu(name)),
        onTap: () => _openFolder(name),
        onLongPress: () => _folderMenu(name),
      );

  @override
  Widget build(BuildContext context) {
    final list = _view;
    final selecting = _sel.isNotEmpty;
    final showFolders = _folder == null && _q.isEmpty && !_onlyFav;
    final empty = list.isEmpty && !showFolders;
    return PopScope(
      // No Voltar: sai da seleção / da pasta antes de sair do app.
      canPop: !widget.active || (_folder == null && !selecting),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          setState(_sel.clear);
        } else {
          _openFolder(null);
        }
      },
      child: Column(children: [
      if (selecting)
        Container(
          color: context.card,
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
                tooltip: 'Mover para pasta',
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: () async {
                  final fs = _selFiles;
                  setState(_sel.clear);
                  await ToolActions.moveToFolder(context, fs);
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
                  hintText: _folder == null ? 'Pesquisar em tudo' : 'Pesquisar na pasta',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.card,
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
      if (_folder != null && !selecting)
        Material(
          color: context.card,
          child: Row(children: [
            IconButton(
                tooltip: 'Voltar',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _openFolder(null)),
            const Icon(Icons.folder_open, color: kTeal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_folder!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => _folderMenu(_folder!)),
          ]),
        ),
      Expanded(
        child: empty
            ? Center(
                child: Text(
                    _folder != null && _q.isEmpty
                        ? 'Pasta vazia.\nToque em Digitalizar para salvar aqui,\nou mova documentos para cá.'
                        : _files.isEmpty
                            ? 'Nenhum documento ainda'
                            : 'Nada encontrado',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.muted)),
              )
            : CustomScrollView(slivers: [
                if (showFolders) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
                      child: Row(children: [
                        const Text('Pastas',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _newFolder,
                          icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                          label: const Text('Nova pasta'),
                        ),
                      ]),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: _folders.length,
                    itemBuilder: (_, i) => _folderTile(_folders[i]),
                  ),
                  if (list.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                              _folders.isEmpty
                                  ? 'Nenhum documento ainda.\nCrie pastas para organizar (Trabalho, Contas...).'
                                  : 'Nenhum documento fora das pastas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: context.muted)),
                        ),
                      ),
                    ),
                  if (list.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
                        child: Text('Documentos',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
                if (_grid)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                    sliver: SliverGrid.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.78,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10),
                      itemCount: list.length,
                      itemBuilder: (_, i) => DocCard(
                        file: list[i],
                        fav: DocStore.isFav(_favs, list[i]),
                        selected: _sel.contains(list[i].path),
                        onTap: () => _tap(list[i]),
                        onLongPress: () => _toggle(list[i]),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 90),
                    sliver: SliverList.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => DocTile(
                        file: list[i],
                        fav: DocStore.isFav(_favs, list[i]),
                        selected: _sel.contains(list[i].path),
                        selecting: selecting,
                        folder: _searchAll ? DocStore.folderOf(list[i]) : null,
                        onTap: () => _tap(list[i]),
                        onLongPress: () => _toggle(list[i]),
                        onMore: () => ToolActions.showDocMenu(context, list[i]),
                      ),
                    ),
                  ),
              ]),
      ),
    ]),
    );
  }
}
