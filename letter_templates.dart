/// Modelos prontos para o Criar PDF (cartas de demissão e outros).
///
/// Cada modelo é uma lista de linhas; cada linha tem trechos de texto (com
/// negrito opcional) e o formato do parágrafo (alinhamento, título).
/// O texto entre [colchetes] é para o usuário trocar pelos dados dele.
/// "[assinatura]" vira a imagem da assinatura no PDF.
library;

class TplLine {
  const TplLine(this.parts, {this.align, this.header});
  final List<(String, bool)> parts; // (texto, negrito)
  final String? align; // null, 'center', 'right', 'justify'
  final int? header;

  static const blank = TplLine([]);
}

TplLine t(String s, {String? align, bool bold = false, int? header}) =>
    TplLine([(s, bold)], align: align, header: header);

TplLine j(String s) => TplLine([(s, false)], align: 'justify');

/// "ASSUNTO:" em negrito seguido do texto normal.
TplLine assunto(String s) =>
    TplLine([('ASSUNTO: ', true), (s, false)]);

class LetterTemplate {
  const LetterTemplate(this.group, this.name, this.hint, this.build);
  final String group;
  final String name;
  final String hint;
  final List<TplLine> Function(String hoje) build;

  /// Formato Delta (o que o editor usa).
  List<Map<String, dynamic>> toDelta(String hoje) {
    final ops = <Map<String, dynamic>>[];
    for (final l in build(hoje)) {
      for (final (text, bold) in l.parts) {
        if (text.isEmpty) continue;
        ops.add({
          'insert': text,
          if (bold) 'attributes': {'bold': true},
        });
      }
      final block = <String, dynamic>{
        if (l.align != null) 'align': l.align,
        if (l.header != null) 'header': l.header,
      };
      ops.add({'insert': '\n', if (block.isNotEmpty) 'attributes': block});
    }
    return ops;
  }
}

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho',
  'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

String dataPorExtenso(DateTime d) => '${d.day} de ${_meses[d.month - 1]} de ${d.year}';

// Bloco do início da carta, como nas cartas em papel: quem escreve à
// esquerda, a empresa alinhada à direita, depois local e data.
List<TplLine> _cabecalho(String hoje) => [
      t('[Seu nome completo]'),
      t('NIF: [000 000 000]'),
      t('[Sua morada]'),
      t('[Código postal e localidade]'),
      TplLine.blank,
      t('[Nome da empresa]', align: 'right'),
      t('NIF: [000 000 000]', align: 'right'),
      t('[Morada da empresa]', align: 'right'),
      t('[Código postal e localidade]', align: 'right'),
      TplLine.blank,
      t('[Localidade], $hoje'),
      TplLine.blank,
    ];

List<TplLine> _fecho() => [
      TplLine.blank,
      t('Com os melhores cumprimentos,'),
      TplLine.blank,
      t('[assinatura]'),
      t('[Seu nome completo]'),
    ];

final letterTemplates = <LetterTemplate>[
  LetterTemplate(
    'Pedido de demissão',
    'Com aviso prévio',
    'O mais comum. Indica o último dia de trabalho, cumprindo o aviso prévio.',
    (hoje) => [
      ..._cabecalho(hoje),
      assunto('Denúncia do contrato de trabalho'),
      TplLine.blank,
      t('Exmos. Senhores,'),
      TplLine.blank,
      j('Venho, por este meio, comunicar a V. Exas. que, por motivos pessoais, '
          'pretendo denunciar o contrato de trabalho que mantenho com essa '
          'empresa desde [data de admissão], nos termos do artigo 400.º do '
          'Código do Trabalho.'),
      TplLine.blank,
      j('Cumprindo o aviso prévio de [30 / 60] dias, o meu último dia de '
          'trabalho será [dd/mm/aaaa].'),
      TplLine.blank,
      j('Agradeço a oportunidade, a consideração e a confiança que me foram '
          'proporcionadas durante todo o período em que aqui trabalhei, e '
          'espero que o meu trabalho tenha contribuído para o crescimento da '
          'empresa.'),
      TplLine.blank,
      j('Despeço-me com votos dos maiores sucessos.'),
      ..._fecho(),
    ],
  ),
  LetterTemplate(
    'Pedido de demissão',
    'Com férias por gozar',
    'Sai no fim do aviso prévio e usa as férias que faltam antes disso.',
    (hoje) => [
      ..._cabecalho(hoje),
      assunto('Rescisão do contrato de trabalho'),
      TplLine.blank,
      t('Exmos. Senhores,'),
      TplLine.blank,
      j('Venho, por este meio, informar que, por motivos pessoais, pretendo '
          'rescindir o contrato de trabalho em vigor. A rescisão produzirá '
          'efeitos a partir do dia [dd/mm/aaaa], deixando de desempenhar '
          'funções a partir do dia [dd/mm/aaaa], por motivo de gozo de férias.'),
      TplLine.blank,
      j('Agradeço a oportunidade, a consideração e a confiança que me foram '
          'proporcionadas pela empresa durante todo o período em que aqui '
          'trabalhei, e espero que o meu trabalho tenha contribuído para o '
          'crescimento da mesma.'),
      TplLine.blank,
      j('Despeço-me com votos dos maiores sucessos para a empresa.'),
      ..._fecho(),
    ],
  ),
  LetterTemplate(
    'Pedido de demissão',
    'Pedindo dispensa do aviso prévio',
    'Quando quer sair antes do fim do aviso prévio e pede à empresa que aceite.',
    (hoje) => [
      ..._cabecalho(hoje),
      assunto('Denúncia do contrato de trabalho e pedido de dispensa do aviso prévio'),
      TplLine.blank,
      t('Exmos. Senhores,'),
      TplLine.blank,
      j('Venho, por este meio, comunicar a minha decisão de denunciar o '
          'contrato de trabalho celebrado com essa empresa, por motivos '
          'pessoais.'),
      TplLine.blank,
      j('Solicito a V. Exas. a dispensa, total ou parcial, do cumprimento do '
          'aviso prévio, de modo a que o meu último dia de trabalho seja '
          '[dd/mm/aaaa]. Caso não seja possível, cumprirei o aviso prévio '
          'legal, terminando o contrato em [dd/mm/aaaa].'),
      TplLine.blank,
      j('Agradeço a compreensão e toda a confiança depositada em mim durante o '
          'tempo em que fiz parte da equipa.'),
      ..._fecho(),
    ],
  ),
  LetterTemplate(
    'Pedido de demissão',
    'Durante o período experimental',
    'Para quem sai ainda no período experimental.',
    (hoje) => [
      ..._cabecalho(hoje),
      assunto('Denúncia do contrato durante o período experimental'),
      TplLine.blank,
      t('Exmos. Senhores,'),
      TplLine.blank,
      j('Venho, por este meio, comunicar que pretendo denunciar o contrato de '
          'trabalho iniciado em [data de admissão], ao abrigo do artigo 114.º '
          'do Código do Trabalho, por me encontrar ainda no período '
          'experimental.'),
      TplLine.blank,
      j('O contrato cessa no dia [dd/mm/aaaa].'),
      TplLine.blank,
      j('Agradeço a oportunidade que me foi dada.'),
      ..._fecho(),
    ],
  ),
  LetterTemplate(
    'Outros',
    'Carta formal',
    'Estrutura de carta em branco, para qualquer assunto.',
    (hoje) => [
      ..._cabecalho(hoje),
      assunto('[Assunto da carta]'),
      TplLine.blank,
      t('Exmos. Senhores,'),
      TplLine.blank,
      j('[Escreva aqui o texto da carta.]'),
      ..._fecho(),
    ],
  ),
  LetterTemplate(
    'Outros',
    'Declaração',
    'Declaração simples com nome, NIF e assinatura.',
    (hoje) => [
      t('DECLARAÇÃO', align: 'center', bold: true, header: 2),
      TplLine.blank,
      TplLine.blank,
      j('Eu, [nome completo], titular do NIF [000 000 000], residente em '
          '[morada], declaro, para os devidos efeitos, que [texto da '
          'declaração].'),
      TplLine.blank,
      j('Por ser verdade, assino a presente declaração.'),
      TplLine.blank,
      TplLine.blank,
      t('[Localidade], $hoje', align: 'center'),
      TplLine.blank,
      t('[assinatura]', align: 'center'),
      t('[Nome completo]', align: 'center'),
    ],
  ),
  LetterTemplate(
    'Outros',
    'Recibo',
    'Recibo de um valor recebido.',
    (hoje) => [
      t('RECIBO', align: 'center', bold: true, header: 2),
      TplLine.blank,
      TplLine([('Valor: ', true), ('[0,00] €', false)], align: 'right'),
      TplLine.blank,
      j('Recebi de [nome de quem pagou], NIF [000 000 000], a quantia de '
          '[valor] € ([valor por extenso]), referente a [descrição].'),
      TplLine.blank,
      j('Para clareza, passo o presente recibo, que assino.'),
      TplLine.blank,
      TplLine.blank,
      t('[Localidade], $hoje', align: 'center'),
      TplLine.blank,
      t('[assinatura]', align: 'center'),
      t('[Nome completo] · NIF [000 000 000]', align: 'center'),
    ],
  ),
];
