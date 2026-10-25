import 'package:flutter/material.dart';
import 'common.dart';
import 'create_pdf_screen.dart';
import 'tool_actions.dart';

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context;
    final sections = <String, List<_T>>{
      'Digitalizar': [
        _T(Icons.document_scanner, 'Documento', () => ToolActions.scanDocument(c)),
        _T(Icons.menu_book_outlined, 'Modo livro', () => ToolActions.scanBook(c)),
        _T(Icons.badge_outlined, 'Cartão ID', () => ToolActions.idCard(c)),
        _T(Icons.text_fields, 'Texto (OCR)', () => ToolActions.ocrImage(c)),
        _T(Icons.auto_fix_high, 'Recriar página', () => ToolActions.recreatePage(c)),
        _T(Icons.qr_code_scanner, 'Leitor QR', () => ToolActions.qr(c)),
      ],
      'Criar': [
        _T(Icons.note_add_outlined, 'Criar PDF', () => Navigator.push(c,
            MaterialPageRoute(builder: (_) => const CreatePdfScreen()))),
      ],
      'Importar': [
        _T(Icons.picture_as_pdf_outlined, 'Importar PDF', () => ToolActions.importPdf(c)),
        _T(Icons.photo_library_outlined, 'Fotos para PDF', () => ToolActions.importImages(c)),
      ],
      'Converter': [
        _T(Icons.image_outlined, 'PDF para imagens', () => ToolActions.toImages(c)),
        _T(Icons.view_day_outlined, 'Imagem longa', () => ToolActions.toLongImage(c)),
        _T(Icons.notes, 'PDF para texto', () => ToolActions.toText(c)),
        _T(Icons.description_outlined, 'PDF para Word', () => ToolActions.toWord(c)),
      ],
      'Editar': [
        _T(Icons.add_a_photo_outlined, 'Adicionar páginas', () => ToolActions.addPages(c)),
        _T(Icons.view_carousel_outlined, 'Organizar páginas', () => ToolActions.organize(c)),
        _T(Icons.rotate_right, 'Girar páginas', () => ToolActions.organize(c)),
        _T(Icons.call_split, 'Dividir PDF', () => ToolActions.split(c)),
        _T(Icons.merge_type, 'Mesclar PDFs', () => ToolActions.merge(c)),
        _T(Icons.draw_outlined, 'Assinar', () => ToolActions.sign(c)),
        _T(Icons.water_drop_outlined, 'Marca d\'água', () => ToolActions.watermark(c)),
        _T(Icons.schedule, 'Carimbo de data', () => ToolActions.dateStamp(c)),
      ],
      'Utilitários': [
        _T(Icons.compress, 'Comprimir', () => ToolActions.compress(c)),
        _T(Icons.lock_outline, 'Proteger com senha', () => ToolActions.protect(c)),
        _T(Icons.lock_open, 'Remover senha', () => ToolActions.unlock(c)),
        _T(Icons.print_outlined, 'Imprimir', () => ToolActions.printPdf(c)),
      ],
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Ferramentas',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ),
        for (final e in sections.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
            child: Text(e.key,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: kTeal)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.15,
              children: [for (final t in e.value) _ToolButton(t: t)],
            ),
          ),
        ],
      ],
    );
  }
}

class _T {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _T(this.icon, this.label, this.onTap);
}

class _ToolButton extends StatelessWidget {
  final _T t;
  const _ToolButton({required this.t});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: InkWell(
        onTap: t.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration:
              BoxDecoration(color: context.card, borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(t.icon, color: kTeal, size: 28),
            const SizedBox(height: 8),
            Text(t.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
