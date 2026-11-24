import 'package:flutter/material.dart';

import '../services/dictionary_service.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../services/vocabulary_service.dart';

/// Cuadro pequeño que aparece encima (o debajo) de la palabra pulsada.
class TranslationPopup extends StatefulWidget {
  const TranslationPopup({
    super.key,
    required this.word,
    required this.anchor,
    required this.bounds,
    required this.future,
    required this.onClose,
    this.bookTitle,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  /// Zonas ocupadas por las barras del lector (el cuadro no se pone encima).
  final double topInset;
  final double bottomInset;

  final String word;

  /// Rectángulo de la palabra en coordenadas locales del Stack del lector.
  final Rect anchor;

  /// Tamaño del área disponible (Stack).
  final Size bounds;
  final Future<TranslationResult> future;
  final VoidCallback onClose;
  final String? bookTitle;

  @override
  State<TranslationPopup> createState() => _TranslationPopupState();
}

class _TranslationPopupState extends State<TranslationPopup> with SingleTickerProviderStateMixin {
  static const _width = 300.0;
  static const _arrow = 9.0;
  static const _gap = 6.0;

  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 180))..forward();
  bool _speaking = false;
  bool _showSentence = false;
  bool _showAllDict = false;
  final _contentKey = GlobalKey();
  double _height = 120;

  @override
  void didUpdateWidget(covariant TranslationPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.future != widget.future) {
      _showSentence = false;
      _anim.forward(from: 0.3);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _measure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && mounted && (box.size.height - _height).abs() > 1) {
        setState(() => _height = box.size.height);
      }
    });
  }

  Future<void> _speak(TranslationResult r, {bool sentence = false}) async {
    setState(() => _speaking = true);
    final ok = await TtsService.instance
        .speak(sentence ? r.sentence : r.word, r.source, rate: sentence ? null : 0.4);
    if (!mounted) return;
    setState(() => _speaking = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'No hay voz de ${r.source.name} instalada. Instálala en Ajustes del teléfono › Texto a voz.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    _measure();
    final theme = Theme.of(context);
    final a = widget.anchor;
    final b = widget.bounds;
    final width = _width.clamp(0.0, b.width - 16);

    // Encima de la palabra si cabe; si no, debajo.
    final minTop = widget.topInset + 8;
    final maxBottom = b.height - widget.bottomInset - 8;
    final total = _height + _arrow;
    final spaceAbove = a.top - _gap - minTop;
    final spaceBelow = maxBottom - a.bottom - _gap;
    final placeAbove = spaceAbove >= total || spaceAbove > spaceBelow;
    final left = (a.center.dx - width / 2).clamp(8.0, b.width - width - 8);
    final top = placeAbove
        ? (a.top - _gap - total).clamp(minTop, double.infinity)
        : (a.bottom + _gap).clamp(double.negativeInfinity, maxBottom - total);
    final arrowX = (a.center.dx - left).clamp(18.0, width - 18);

    final bg = theme.colorScheme.inverseSurface;
    final fg = theme.colorScheme.onInverseSurface;

    return Stack(children: [
      // Resaltado de la palabra pulsada.
      Positioned.fromRect(
        rect: a.inflate(2),
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
      Positioned(
        left: left,
        top: top,
        width: width,
        child: FadeTransition(
          opacity: _anim,
          child: ScaleTransition(
            scale: CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
            alignment: Alignment(((arrowX / width) * 2) - 1, placeAbove ? 1 : -1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!placeAbove) _Arrow(color: bg, up: true, x: arrowX, width: width),
                NotificationListener<SizeChangedLayoutNotification>(
                  onNotification: (_) {
                    _measure();
                    return true;
                  },
                  child: SizeChangedLayoutNotifier(
                    child: _body(bg, fg, theme),
                  ),
                ),
                if (placeAbove) _Arrow(color: bg, up: false, x: arrowX, width: width),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _body(Color bg, Color fg, ThemeData theme) => Material(
                  key: _contentKey,
                  color: bg,
                  elevation: 10,
                  shadowColor: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                  child: DefaultTextStyle(
                    style: TextStyle(color: fg, fontSize: 14),
                    child: IconTheme(
                      data: IconThemeData(color: fg),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 6, 10),
                        child: FutureBuilder<TranslationResult>(
                          future: widget.future,
                          builder: (context, snap) {
                            if (snap.hasError) return _error(snap.error.toString(), fg);
                            if (!snap.hasData) return _loading(fg);
                            return _content(snap.data!, fg, theme);
                          },
                        ),
                      ),
                    ),
                  ),
                );

  Widget _header(String word, Color fg, {Widget? trailing}) => Row(children: [
        Expanded(
          child: Text(word,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        ?trailing,
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Cerrar',
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: widget.onClose,
        ),
      ]);

  Widget _loading(Color fg) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(widget.word, fg),
          Padding(
            padding: const EdgeInsets.only(bottom: 6, right: 8),
            child: Row(children: [
              SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
              const SizedBox(width: 10),
              const Text('Traduciendo…'),
            ]),
          ),
        ],
      );

  Widget _error(String msg, Color fg) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(widget.word, fg),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: Text(msg, style: TextStyle(color: fg.withValues(alpha: 0.85))),
          ),
        ],
      );

  Widget _content(TranslationResult r, Color fg, ThemeData theme) {
    final muted = fg.withValues(alpha: 0.7);
    final vocab = VocabularyService.instance;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          r.word,
          fg,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Escuchar pronunciación',
              icon: _speaking
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  : const Icon(Icons.volume_up_rounded, size: 22),
              onPressed: _speaking ? null : () => _speak(r),
            ),
            ListenableBuilder(
              listenable: vocab,
              builder: (context, _) {
                final saved = vocab.contains(r.word, r.source);
                return IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: saved ? 'Quitar de mi vocabulario' : 'Guardar en mi vocabulario',
                  icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, size: 21),
                  onPressed: () => vocab.toggle(r, bookTitle: widget.bookTitle),
                );
              },
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('${r.source.flag} → ${r.target.flag}', style: TextStyle(fontSize: 12, color: muted)),
                if (r.ipa != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(r.ipa!,
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: fg)),
                  ),
                ],
                if (r.displayPos != null && r.displayPos!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(r.displayPos!,
                      style: TextStyle(fontSize: 12, color: muted, fontStyle: FontStyle.italic)),
                ],
                if (r.displayLemma != null &&
                    r.displayLemma!.isNotEmpty &&
                    r.displayLemma!.toLowerCase() != r.word.toLowerCase()) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('← ${r.displayLemma}',
                        overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: muted)),
                  ),
                ],
                if (r.fromAi) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.auto_awesome, size: 13, color: muted),
                ],
              ]),
              const SizedBox(height: 4),
              Text(r.wordTranslation,
                  style: TextStyle(
                      color: theme.colorScheme.inversePrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              if (r.phrase != null && r.phraseTranslation != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${r.phrase}  ',
                        style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: 13.5)),
                    TextSpan(text: '→ ${r.phraseTranslation}', style: TextStyle(color: fg, fontSize: 13.5)),
                  ])),
                ),
              ],
              if (r.alternatives.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('${r.fromAi ? 'También' : 'Sola'}: ${r.alternatives.take(3).join(', ')}',
                    style: TextStyle(fontSize: 12.5, color: muted)),
              ],
              if (r.dictionary.isNotEmpty || r.phraseDictionary.isNotEmpty)
                _dictSection(r, fg, muted, theme),
              if (r.explanation != null && r.explanation!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(r.explanation!, style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.9))),
              ],
              if (r.sentenceTranslation != null && r.sentenceTranslation!.isNotEmpty) ...[
                const SizedBox(height: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => setState(() => _showSentence = !_showSentence),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(_showSentence ? Icons.expand_less : Icons.expand_more, size: 18, color: muted),
                      const SizedBox(width: 4),
                      Text('Frase en contexto', style: TextStyle(fontSize: 12.5, color: muted)),
                    ]),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 160),
                  alignment: Alignment.topCenter,
                  child: !_showSentence
                      ? const SizedBox(width: double.infinity)
                      : Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 170),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: fg.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.sentence,
                                  style: TextStyle(fontSize: 12.5, color: muted, fontStyle: FontStyle.italic)),
                              const SizedBox(height: 6),
                              Text(r.sentenceTranslation!, style: const TextStyle(fontSize: 13)),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                      foregroundColor: fg, visualDensity: VisualDensity.compact),
                                  onPressed: () => _speak(r, sentence: true),
                                  icon: const Icon(Icons.record_voice_over_outlined, size: 16),
                                  label: const Text('Escuchar frase', style: TextStyle(fontSize: 12)),
                                ),
                              ),
                            ]),
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

extension _DictUi on _TranslationPopupState {
  /// Significados del diccionario: primero la expresión (phrasal verb) y luego
  /// la palabra. El significado que encaja con la frase va resaltado.
  Widget _dictSection(TranslationResult r, Color fg, Color muted, ThemeData theme) {
    final accent = theme.colorScheme.inversePrimary;
    final rows = <Widget>[];
    var total = 0;
    const collapsedMax = 3;

    void addEntry(DictEntry e, {required bool isPhrase}) {
      final senses = [...e.senses]..sort((a, b) => (b.inContext ? 1 : 0) - (a.inContext ? 1 : 0));
      final header = [
        e.word,
        if (e.pos != null) e.pos!,
        if (e.formInfo != null && formInfoEs(e.formInfo!) != null) formInfoEs(e.formInfo!)!,
      ].join(' · ');
      final headerIndex = rows.length;
      var shown = 0;
      for (final s in senses) {
        total++;
        if (!_showAllDict && total > collapsedMax) continue;
        shown++;
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: Icon(s.inContext ? Icons.check_circle : Icons.circle,
                  size: s.inContext ? 13 : 5, color: s.inContext ? accent : muted),
            ),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(
                  text: s.es.join(', '),
                  style: TextStyle(
                      fontSize: 13.5,
                      color: s.inContext ? accent : fg,
                      fontWeight: s.inContext ? FontWeight.w700 : FontWeight.w500),
                ),
                if (s.gloss != null)
                  TextSpan(
                      text: '  ${s.gloss}',
                      style: TextStyle(fontSize: 11.5, color: muted, fontStyle: FontStyle.italic)),
              ])),
            ),
          ]),
        ));
      }
      // Cabecera solo si alguno de sus significados está visible.
      if (shown > 0) {
        rows.insert(
          headerIndex,
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(header,
                style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
          ),
        );
      }
    }

    for (final e in r.phraseDictionary) {
      addEntry(e, isPhrase: true);
    }
    for (final e in r.dictionary) {
      addEntry(e, isPhrase: false);
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: _showAllDict ? 260 : 400),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
          ),
        ),
        if (total > collapsedMax)
          InkWell(
            onTap: () => setState(() => _showAllDict = !_showAllDict),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _showAllDict ? 'Ver menos' : 'Ver los $total significados',
                style: TextStyle(fontSize: 12.5, color: accent, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ]),
    );
  }
}

/// "participle, present" / "simple past of go" -> texto en español.
String? formInfoEs(String info) {
  final i = info.toLowerCase();
  if (i.contains('participle') && i.contains('present')) return 'gerundio';
  if (i.contains('participle') && i.contains('past')) return 'participio';
  if (i.contains('past')) return 'pasado';
  if (i.contains('third-person')) return '3ª persona';
  if (i.contains('plural')) return 'plural';
  if (i.contains('comparative')) return 'comparativo';
  if (i.contains('superlative')) return 'superlativo';
  if (i.startsWith('forma de')) return null;
  return null;
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.color, required this.up, required this.x, required this.width});
  final Color color;
  final bool up;
  final double x;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: _TranslationPopupState._arrow,
        child: CustomPaint(painter: _ArrowPainter(color, up, x)),
      );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color, this.up, this.x);
  final Color color;
  final bool up;
  final double x;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final path = Path();
    if (up) {
      path
        ..moveTo(x - h, h)
        ..lineTo(x, 0)
        ..lineTo(x + h, h);
    } else {
      path
        ..moveTo(x - h, 0)
        ..lineTo(x, h)
        ..lineTo(x + h, 0);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.color != color || old.up != up || old.x != x;
}
