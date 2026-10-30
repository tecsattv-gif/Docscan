import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/doc_store.dart';
import 'common.dart';
import 'tutorial_screen.dart';

class MeTab extends StatefulWidget {
  const MeTab({super.key});
  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  int _count = 0;
  int _size = 0;
  bool _auto = true;

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
    final s = await DocStore.totalSize();
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _count = l.length;
        _size = s;
        _auto = p.getBool('auto_scan') ?? true;
      });
    }
  }

  Future<void> _backup() async {
    if (await DocBackup.count() == 0 && !await DocBackup.hasWatermarks()) {
      if (mounted) toast(context, 'Ainda não há documentos para salvar');
      return;
    }
    if (!mounted) return;
    final where = await choose(context, 'Onde salvar o backup?', [
      'Google Drive, e-mail ou outro app',
      'Salvar no celular (${DocBackup.pastaLegivel}, substitui o anterior)',
    ]);
    if (where == null || !mounted) return;
    final f = await Busy.run<File>(context, 'Preparando backup...', DocBackup.create);
    if (f == null || !mounted) return;
    final name = f.path.split(Platform.pathSeparator).last;
    final conteudo = '${DocBackup.ultimoDocs} documento(s) e '
        '${DocBackup.ultimasMarcas} marca(s) d\'água';
    if (where == 0) {
      toast(context, 'Backup com $conteudo');
      await Share.shareXFiles([XFile(f.path, mimeType: 'application/zip')],
          subject: name,
          text: 'Backup dos documentos do DocScan. Para restaurar, abra o '
              'DocScan > Eu > Restaurar backup e escolha este arquivo.');
    } else {
      try {
        await DocBackup.saveToFolder(f);
        if (mounted) {
          toast(context,
              'Backup salvo em ${DocBackup.pastaLegivel} com $conteudo (o anterior foi substituído)');
        }
      } catch (_) {
        if (mounted) toast(context, 'Não foi possível salvar. Tente pelo Google Drive.');
      }
    }
  }

  Future<void> _restore() async {
    final r = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip']);
    final path = r?.files.single.path;
    if (path == null || !mounted) return;
    final n = await Busy.run<int>(
        context, 'Restaurando...', () => DocBackup.restore(path));
    if (n == null || !mounted) return;
    if (n < 0) {
      toast(context, 'Este arquivo não é um backup do DocScan');
    } else if (n == 0) {
      toast(context, 'Tudo já estava no app; nada novo para restaurar');
    } else {
      toast(context, '$n item(ns) restaurado(s) (documentos e marcas d\'água)');
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/logo.png', width: 64, height: 64),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DocScan',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Digitalize. Organize. Compartilhe.',
                  style: TextStyle(color: context.muted)),
            ]),
          ),
        ]),
      ),
      ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('Meus documentos'),
        subtitle: Text('$_count arquivo(s)  ·  ${fmtSize(_size)}'),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.play_circle_outline),
        title: const Text('Como usar'),
        subtitle: const Text('Vídeo de 30 segundos com o passo a passo'),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TutorialScreen())),
      ),
      ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Tema'),
        subtitle: Text(themeNames[themeIndex]),
        onTap: () async {
          final i = await choose(context, 'Tema', themeNames);
          if (i == null) return;
          await setTheme(i);
          if (mounted) setState(() {});
        },
      ),
      SwitchListTile(
        secondary: const Icon(Icons.auto_fix_high),
        title: const Text('Scanner automático'),
        subtitle: const Text(
            'Usa o scanner do Google (detecta bordas sozinho). Se falhar no seu aparelho, o app usa o modo manual.'),
        value: _auto,
        onChanged: (v) async {
          final p = await SharedPreferences.getInstance();
          await p.setBool('auto_scan', v);
          setState(() => _auto = v);
        },
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Fazer backup'),
        subtitle: const Text('Salva todos os documentos no Google Drive, e-mail ou no celular'),
        onTap: _backup,
      ),
      ListTile(
        leading: const Icon(Icons.settings_backup_restore),
        title: const Text('Restaurar backup'),
        subtitle: const Text('Traz de volta os documentos de um arquivo de backup (.zip)'),
        onTap: _restore,
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.cleaning_services_outlined),
        title: const Text('Limpar miniaturas'),
        subtitle: const Text('Libera espaço; são recriadas quando necessário'),
        onTap: () async {
          await DocStore.clearThumbs();
          if (context.mounted) toast(context, 'Miniaturas limpas');
        },
      ),
      const Divider(),
      const ListTile(
        leading: Icon(Icons.lock_outline),
        title: Text('Privacidade'),
        subtitle: Text(
            'Seus documentos ficam só neste celular. O app não envia nada para a internet.'),
      ),
      const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Versão'),
        subtitle: Text('DocScan 2.0'),
      ),
    ]);
  }
}
