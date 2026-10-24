import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'common.dart';

/// Linha de documento (miniatura, nome, data, tamanho).
class DocTile extends StatelessWidget {
  final File file;
  final bool fav;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  const DocTile({
    super.key,
    required this.file,
    required this.fav,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.selected = false,
    this.selecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final st = file.statSync();
    return ListTile(
      selected: selected,
      selectedTileColor: kTeal.withOpacity(0.18),
      leading: Thumb(file: file),
      title: Row(children: [
        Flexible(
            child: Text(docName(file), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (fav)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.star, size: 16, color: Colors.amber),
          ),
      ]),
      subtitle: Text(
          '${DateFormat('dd/MM/yyyy HH:mm').format(st.modified)}  ·  ${fmtSize(st.size)}',
          style: const TextStyle(fontSize: 12)),
      trailing: selecting
          ? Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? kTeal : Colors.white54)
          : IconButton(icon: const Icon(Icons.more_vert), onPressed: onMore),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// Cartão de documento para a grade.
class DocCard extends StatelessWidget {
  final File file;
  final bool fav;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const DocCard({
    super.key,
    required this.file,
    required this.fav,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? kTeal.withOpacity(0.2) : kCard,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: kTeal, width: 2) : null,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (_, c) => Thumb(file: file, width: c.maxWidth, height: c.maxHeight),
                ),
              ),
              if (fav)
                const Positioned(
                    top: 4, right: 4, child: Icon(Icons.star, color: Colors.amber, size: 20)),
            ]),
          ),
          const SizedBox(height: 6),
          Text(docName(file),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          Text(fmtSize(file.lengthSync()),
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      ),
    );
  }
}
