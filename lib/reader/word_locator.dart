import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

/// Palabra encontrada bajo el dedo.
class WordHit {
  WordHit({
    required this.word,
    required this.sentence,
    required this.pageNumber,
    required this.documentRect,
    this.wordOffset = -1,
  });

  final String word;

  /// Índice de la palabra dentro de [sentence] (-1 si no se sabe).
  final int wordOffset;

  /// Frase completa que contiene la palabra (contexto para traducir).
  final String sentence;
  final int pageNumber;

  /// Rectángulo de la palabra en coordenadas de documento del visor.
  final Rect documentRect;
}

/// Convierte una posición del visor en la palabra + frase que hay debajo.
class WordLocator {
  WordLocator(this.controller);

  final PdfViewerController controller;
  final Map<int, Future<PdfPageText>> _textCache = {};

  static final _wordChar = RegExp(r"[\p{L}\p{M}\p{N}'’\-]", unicode: true);
  static final _letter = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static const _sentenceEnd = {'.', '!', '?', '…', ';', '。', '！', '？'};

  Future<PdfPageText> _text(PdfPage page) =>
      _textCache.putIfAbsent(page.pageNumber, () => page.loadStructuredText(ensureLoaded: true));

  Future<WordHit?> locate(Offset documentPosition) async {
    if (!controller.isReady) return null;
    final layouts = controller.layout.pageLayouts;
    for (var i = 0; i < layouts.length; i++) {
      final pageRect = layouts[i];
      if (!pageRect.contains(documentPosition)) continue;
      final page = controller.pages[i];
      final point = (documentPosition - pageRect.topLeft)
          .toPdfPoint(page: page, scaledPageSize: pageRect.size);
      final text = await _text(page);
      return _findWord(text, page, pageRect, point);
    }
    return null;
  }

  WordHit? _findWord(PdfPageText text, PdfPage page, Rect pageRect, PdfPoint point) {
    final full = text.fullText;
    final rects = text.charRects;
    if (full.isEmpty || rects.isEmpty) return null;
    final n = full.length < rects.length ? full.length : rects.length;

    // 1. Carácter exactamente bajo el dedo; si no, el más cercano (dedos ≠ ratón).
    int? hit;
    var best = double.infinity;
    for (var i = 0; i < n; i++) {
      if (!_letter.hasMatch(full[i])) continue;
      final r = rects[i];
      if (r.containsPoint(point, margin: 0.5)) {
        hit = i;
        break;
      }
      final d = r.distanceSquaredTo(point);
      if (d < best) {
        best = d;
        hit = i;
      }
    }
    // Tolerancia ~ media línea de texto (en puntos PDF).
    if (hit == null || (best != double.infinity && best > 14 * 14)) return null;

    // 2. Expandir hasta los límites de la palabra.
    var start = hit;
    var end = hit + 1;
    while (start > 0 && _wordChar.hasMatch(full[start - 1])) {
      start--;
    }
    while (end < n && _wordChar.hasMatch(full[end])) {
      end++;
    }
    // Quitar apóstrofes / guiones sueltos de los extremos.
    while (start < end && !_letter.hasMatch(full[start])) {
      start++;
    }
    while (end > start && !_letter.hasMatch(full[end - 1])) {
      end--;
    }
    if (start >= end) return null;

    var word = full.substring(start, end);
    var wordRect = rects.boundingRect(start: start, end: end);

    // Palabra partida por guion a final de línea: "under-\nstand".
    final after = end < full.length ? full.substring(end, (end + 3).clamp(0, full.length)) : '';
    if (RegExp(r'^-\s*\n').hasMatch(after) || RegExp(r'^-\r?\n').hasMatch(after)) {
      var j = end + 1;
      while (j < full.length && (full[j] == '\n' || full[j] == '\r' || full[j] == ' ')) {
        j++;
      }
      var k = j;
      while (k < n && _letter.hasMatch(full[k])) {
        k++;
      }
      if (k > j) word += full.substring(j, k);
    }

    // 3. Frase que contiene la palabra (contexto).
    var s = start;
    var guard = 0;
    while (s > 0 && guard < 500) {
      final c = full[s - 1];
      if (_sentenceEnd.contains(c) && (s >= full.length || _isSpace(full[s]))) break;
      s--;
      guard++;
    }
    var e = end;
    guard = 0;
    while (e < full.length && guard < 500) {
      final c = full[e];
      e++;
      guard++;
      if (_sentenceEnd.contains(c) && (e >= full.length || _isSpace(full[e]))) break;
    }
    final sentence = _clean(full.substring(s, e));
    // Posición de la palabra dentro de la frase limpia.
    final prefixLen = _clean(full.substring(s, start)).length;
    var offset = sentence.indexOf(word, (prefixLen - 1).clamp(0, sentence.length));
    if (offset < 0) offset = sentence.indexOf(word);

    return WordHit(
      word: word,
      wordOffset: offset,
      sentence: sentence.isEmpty ? word : sentence,
      pageNumber: page.pageNumber,
      documentRect: wordRect.toRectInDocument(page: page, pageRect: pageRect),
    );
  }

  static bool _isSpace(String c) => c.trim().isEmpty;

  static String _clean(String s) => s
      .replaceAll(RegExp(r'-\s*\r?\n\s*'), '') // une palabras partidas
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void clear() => _textCache.clear();
}
