import 'dart:async';
import 'dart:convert';

import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;

import '../core/languages.dart';
import 'dictionary_service.dart';
import 'settings_service.dart';

/// Resultado mostrado en el cuadro emergente.
class TranslationResult {
  TranslationResult({
    required this.word,
    required this.sentence,
    required this.source,
    required this.target,
    required this.wordTranslation,
    this.sentenceTranslation,
    this.alternatives = const [],
    this.partOfSpeech,
    this.lemma,
    this.explanation,
    this.fromAi = false,
    this.phrase,
    this.phraseTranslation,
  });

  /// Expresión detectada alrededor de la palabra (p. ej. phrasal verb).
  final String? phrase;
  final String? phraseTranslation;

  /// Entradas del diccionario offline (palabra/lema y, si hay, la expresión).
  List<DictEntry> dictionary = const [];
  List<DictEntry> phraseDictionary = const [];

  String? get ipa => dictionary.map((e) => e.ipa).firstWhere((i) => i != null, orElse: () => null);
  String? get displayPos =>
      partOfSpeech ?? (dictionary.isEmpty ? null : dictionary.first.pos);
  String? get displayLemma {
    if (lemma != null) return lemma;
    for (final e in dictionary) {
      if (e.word.toLowerCase() != word.toLowerCase()) return e.word;
    }
    return null;
  }

  final String word;
  final String sentence;
  final AppLanguage source;
  final AppLanguage target;

  /// Traducción de la palabra en ESTE contexto.
  final String wordTranslation;

  /// Traducción completa de la frase (contexto).
  final String? sentenceTranslation;
  final List<String> alternatives;
  final String? partOfSpeech;
  final String? lemma;
  final String? explanation;
  final bool fromAi;
}

class TranslationException implements Exception {
  TranslationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Traducción contextual:
///  * Offline (ML Kit, gratis): palabra + frase completa como contexto.
///  * IA opcional (Claude): elige el significado exacto según la frase.
class TranslationService {
  TranslationService._();
  static final TranslationService instance = TranslationService._();

  final _modelManager = OnDeviceTranslatorModelManager();
  final _identifier = LanguageIdentifier(confidenceThreshold: 0.45);
  final Map<String, OnDeviceTranslator> _translators = {};
  final Map<String, TranslationResult> _cache = {};

  SettingsService get _settings => SettingsService.instance;

  /// Detecta el idioma del texto; si no lo reconoce usa el de ajustes.
  Future<AppLanguage> detectLanguage(String text) async {
    if (!_settings.autoDetectSource) return _settings.sourceLanguage;
    try {
      final code = await _identifier.identifyLanguage(text);
      return Languages.tryByCode(code) ?? _settings.sourceLanguage;
    } catch (_) {
      return _settings.sourceLanguage;
    }
  }

  Future<bool> isModelDownloaded(AppLanguage l) =>
      _modelManager.isModelDownloaded(l.mlkit.bcpCode);

  Future<bool> downloadModel(AppLanguage l) =>
      _modelManager.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);

  Future<bool> deleteModel(AppLanguage l) => _modelManager.deleteModel(l.mlkit.bcpCode);

  /// Garantiza que los modelos offline de ambos idiomas estén descargados.
  Future<void> ensureModels(AppLanguage a, AppLanguage b) async {
    for (final l in {a, b}) {
      if (!await isModelDownloaded(l)) {
        final ok = await downloadModel(l);
        if (!ok) {
          throw TranslationException(
              'No se pudo descargar el diccionario offline de ${l.name}. Conéctate a internet una vez.');
        }
      }
    }
  }

  OnDeviceTranslator _translator(AppLanguage s, AppLanguage t) {
    final key = '${s.code}>${t.code}';
    return _translators.putIfAbsent(
        key, () => OnDeviceTranslator(sourceLanguage: s.mlkit, targetLanguage: t.mlkit));
  }

  Future<TranslationResult> translate({
    required String word,
    required String sentence,
    int wordOffset = -1,
    AppLanguage? forcedSource,
  }) async {
    if (wordOffset < 0) wordOffset = sentence.indexOf(word);
    final target = _settings.targetLanguage;
    final source = forcedSource ?? await detectLanguage(sentence.length > 20 ? sentence : word);
    final useAi = _settings.aiAvailable;
    final cacheKey = '${useAi ? 'ai' : 'ml'}|${source.code}>${target.code}|$word|$sentence';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    if (source == target) {
      return TranslationResult(
        word: word,
        sentence: sentence,
        source: source,
        target: target,
        wordTranslation: word,
        explanation: 'La palabra ya está en ${target.name}. Cambia el idioma destino en Ajustes.',
      );
    }

    TranslationResult result;
    if (useAi) {
      try {
        result = await _translateWithClaude(word, sentence, source, target);
      } catch (e) {
        // Si la IA falla (sin internet, clave inválida…) seguimos offline.
        result = await _translateOffline(word, sentence, wordOffset, source, target,
            note: 'IA no disponible ($e). Mostrando traducción offline.');
      }
    } else {
      result = await _translateOffline(word, sentence, wordOffset, source, target);
    }
    await _addDictionary(result);
    _cache[cacheKey] = result;
    return result;
  }

  // ---------------------------------------------------------------------------
  // Traducción offline mejorada
  // ---------------------------------------------------------------------------

  /// Marcadores que se insertan alrededor de la palabra en la frase. Después de
  /// traducir la frase entera, lo que queda entre ellos es la traducción de la
  /// palabra *en su contexto*. Se prueban en orden hasta que uno sobrevive.
  static const _markers = <(String, String, String)>[
    // (apertura, cierre, regex de extracción)
    ('[', ']', r'\[\s*([^\[\]]+?)\s*\]'),
    ('«', '»', r'[«"“„]\s*([^«»"“”„]+?)\s*[»"”]'),
    ('"', '"', r'["“«„]\s*([^"“”«»„]+?)\s*["”»]'),
  ];

  /// Partículas de phrasal verbs en inglés.
  static const _particles = {
    'up', 'down', 'out', 'off', 'on', 'over', 'away', 'back', 'through', 'around',
    'along', 'across', 'apart', 'aside', 'forward', 'in', 'into',
  };

  static const _articles = <String, List<String>>{
    'es': ['el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'lo'],
    'fr': ['le', 'la', 'les', "l'", 'l’', 'un', 'une', 'des', 'du'],
    'it': ['il', 'lo', 'la', 'i', 'gli', 'le', "l'", 'l’', 'un', 'uno', 'una'],
    'pt': ['o', 'a', 'os', 'as', 'um', 'uma'],
    'ca': ['el', 'la', 'els', 'les', "l'", 'l’', 'un', 'una'],
    'de': ['der', 'die', 'das', 'den', 'dem', 'ein', 'eine', 'einen'],
    'nl': ['de', 'het', 'een'],
  };

  static const _sourceArticles = {
    'the', 'a', 'an', 'el', 'la', 'los', 'las', 'un', 'una', 'le', 'les', 'der', 'die', 'das',
  };

  Future<TranslationResult> _translateOffline(
      String word, String sentence, int wordOffset, AppLanguage source, AppLanguage target,
      {String? note}) async {
    await ensureModels(source, target);
    final tr = _translator(source, target);
    final hasContext = sentence.trim().isNotEmpty && sentence.trim() != word && wordOffset >= 0;

    // 1. Palabra aislada (en minúscula si solo va en mayúscula por empezar frase).
    final query = _caseForQuery(word, wordOffset, sentence);
    final isolatedF = tr.translateText(query);
    final sentenceF = hasContext ? tr.translateText(sentence) : null;

    // 2. Palabra dentro de su frase (contexto real).
    final contextual =
        hasContext ? await _markedTranslate(tr, sentence, wordOffset, word.length) : null;

    // 3. Phrasal verb / expresión ("picking up", "give in"…).
    String? phrase;
    String? phraseT;
    final ph = source.code == 'en' && hasContext ? _phrasal(sentence, wordOffset, word) : null;
    if (ph != null) {
      phrase = sentence.substring(ph.$1, ph.$1 + ph.$2);
      phraseT = await _markedTranslate(tr, sentence, ph.$1, ph.$2) ??
          _tidy(await tr.translateText(phrase.toLowerCase()), phrase, target);
    }

    final isolated = _tidy(await isolatedF, word, target);
    final main = contextual == null ? isolated : _tidy(contextual, word, target);
    final alternatives = <String>[
      if (isolated.toLowerCase() != main.toLowerCase()) isolated,
    ];

    return TranslationResult(
      word: word,
      sentence: sentence,
      source: source,
      target: target,
      wordTranslation: _matchCase(main, word, wordOffset),
      sentenceTranslation: sentenceF == null ? null : (await sentenceF).trim(),
      alternatives: alternatives,
      phrase: phrase,
      phraseTranslation: phraseT == null ? null : _matchCase(phraseT, word, wordOffset),
      explanation: note,
    );
  }

  /// Añade significados del diccionario offline y marca el que encaja con la frase.
  Future<void> _addDictionary(TranslationResult r) async {
    final dict = DictionaryService.instance;
    if (!dict.supports(r.source.code, r.target.code)) return;
    try {
      var phrase = r.phrase;
      if (phrase == null && r.sentence.length > r.word.length) {
        final off = r.sentence.indexOf(r.word);
        final ph = off >= 0 ? _phrasal(r.sentence, off, r.word) : null;
        if (ph != null) phrase = r.sentence.substring(ph.$1, ph.$1 + ph.$2);
      }
      r.dictionary = await dict.lookup(r.word);
      if (phrase != null) r.phraseDictionary = await dict.lookupPhrase(phrase);
      DictionaryService.markContext(r.phraseDictionary, r.phraseTranslation ?? r.wordTranslation);
      DictionaryService.markContext(r.dictionary, r.wordTranslation);
    } catch (_) {
      // El diccionario es un extra: si falla, se muestra lo demás.
    }
  }

  /// Traduce [sentence] con el tramo [start, start+len) marcado y devuelve
  /// la traducción de ese tramo, o null si el traductor perdió las marcas.
  Future<String?> _markedTranslate(
      OnDeviceTranslator tr, String sentence, int start, int len) async {
    if (start < 0 || start + len > sentence.length) return null;
    final before = sentence.substring(0, start);
    final span = sentence.substring(start, start + len);
    final after = sentence.substring(start + len);
    for (final (open, close, pattern) in _markers) {
      // Si la frase ya contiene ese marcador, la extracción sería ambigua.
      if (sentence.contains(open) || sentence.contains(close)) continue;
      final out = await tr.translateText('$before$open$span$close$after');
      final matches = RegExp(pattern).allMatches(out).toList();
      if (matches.length != 1) continue;
      final t = matches.first.group(1)!.trim();
      if (t.isEmpty || t.length > span.length * 4 + 20) continue;
      return t;
    }
    return null;
  }

  /// Si la palabra (o la siguiente) forma un phrasal verb, devuelve
  /// (inicio, longitud) de la expresión completa dentro de la frase.
  (int, int)? _phrasal(String sentence, int offset, String word) {
    final lower = word.toLowerCase();
    final afterText = sentence.substring((offset + word.length).clamp(0, sentence.length));
    final next = RegExp(r"^\s+([A-Za-z]+)").firstMatch(afterText);
    if (!_particles.contains(lower) && next != null && _particles.contains(next.group(1)!.toLowerCase())) {
      return (offset, word.length + next.end);
    }
    if (_particles.contains(lower)) {
      final beforeText = sentence.substring(0, offset);
      final prev = RegExp(r"([A-Za-z]+)\s+$").firstMatch(beforeText);
      if (prev != null && !_sourceArticles.contains(prev.group(1)!.toLowerCase())) {
        return (prev.start, offset + word.length - prev.start);
      }
    }
    return null;
  }

  /// "Honesty" al inicio de frase se consulta como "honesty"; "Bismarck"
  /// en mitad de frase se deja (probable nombre propio).
  static String _caseForQuery(String word, int offset, String sentence) {
    if (word.length < 2 || word.toUpperCase() == word) return word;
    final first = word[0];
    final capitalized = first != first.toLowerCase();
    if (capitalized && offset <= 0) return first.toLowerCase() + word.substring(1);
    return word;
  }

  /// Ajusta mayúscula inicial del resultado a la de la palabra original.
  static String _matchCase(String t, String word, int offset) {
    if (t.isEmpty || word.isEmpty) return t;
    final wordCap = word[0] != word[0].toLowerCase();
    final properNoun = wordCap && offset > 0;
    if (properNoun) return t;
    return t[0].toLowerCase() + t.substring(1);
  }

  /// Quita puntuación sobrante y artículos que el traductor añade.
  static String _tidy(String t, String sourceWord, AppLanguage target) {
    var r = t.trim().replaceAll(RegExp(r'^[\s"“”«»„¡¿\(\[]+|[\s"“”«»„.,;:!?\)\]]+$'), '');
    final srcFirst = sourceWord.trim().split(RegExp(r'\s+')).first.toLowerCase();
    final arts = _articles[target.code];
    if (arts != null && !_sourceArticles.contains(srcFirst)) {
      for (final a in arts) {
        final apostrophe = a.endsWith("'") || a.endsWith('’');
        final prefix = apostrophe ? a : '$a ';
        if (r.toLowerCase().startsWith(prefix) && r.length > prefix.length + 1) {
          r = r.substring(prefix.length).trimLeft();
          break;
        }
      }
    }
    return r.isEmpty ? t.trim() : r;
  }

  static const _schema = {
    'type': 'object',
    'properties': {
      'translation': {
        'type': 'string',
        'description': 'Traducción de la palabra con el significado que tiene en esta frase.'
      },
      'alternatives': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Otros significados frecuentes de la palabra (máx. 3).'
      },
      'part_of_speech': {'type': 'string'},
      'lemma': {'type': 'string', 'description': 'Forma base (infinitivo, singular…).'},
      'explanation': {
        'type': 'string',
        'description': 'Una frase breve que explica el uso en este contexto.'
      },
      'sentence_translation': {'type': 'string'},
    },
    'required': [
      'translation',
      'alternatives',
      'part_of_speech',
      'lemma',
      'explanation',
      'sentence_translation'
    ],
    'additionalProperties': false,
  };

  Future<TranslationResult> _translateWithClaude(
      String word, String sentence, AppLanguage source, AppLanguage target) async {
    final prompt = '''
Eres un tutor de idiomas. Un estudiante que lee un libro en ${source.name} no entiende una palabra.

Frase: """$sentence"""
Palabra seleccionada: "$word"

Responde en ${target.name}. Da la traducción de la palabra con el sentido EXACTO que tiene en esta frase (si forma parte de un phrasal verb o expresión, tradúcela como tal), hasta 3 significados alternativos comunes, la categoría gramatical, la forma base, una explicación de una sola frase y la traducción natural de la frase completa.''';

    final res = await http
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'content-type': 'application/json',
            'x-api-key': _settings.apiKey,
            'anthropic-version': '2026-10-21',
            'anthropic-beta': 'server-side-fallback-2026-07-01',
          },
          body: jsonEncode({
            'model': _settings.aiModel,
            'max_tokens': 2048,
            'fallbacks': 'default',
            // Respuesta rápida: es un cuadro emergente mientras se lee.
            'output_config': {
              'effort': 'low',
              'format': {'type': 'json_schema', 'schema': _schema},
            },
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        msg = (jsonDecode(res.body)['error']?['message'] as String?) ?? msg;
      } catch (_) {}
      throw TranslationException(msg);
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (data['stop_reason'] == 'refusal') {
      throw TranslationException('la IA rechazó la consulta');
    }
    final text = (data['content'] as List)
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
    final j = jsonDecode(text) as Map<String, dynamic>;
    return TranslationResult(
      word: word,
      sentence: sentence,
      source: source,
      target: target,
      wordTranslation: (j['translation'] as String).trim(),
      sentenceTranslation: j['sentence_translation'] as String?,
      alternatives: ((j['alternatives'] as List?) ?? []).cast<String>(),
      partOfSpeech: j['part_of_speech'] as String?,
      lemma: j['lemma'] as String?,
      explanation: j['explanation'] as String?,
      fromAi: true,
    );
  }

  void dispose() {
    for (final t in _translators.values) {
      t.close();
    }
    _translators.clear();
    _identifier.close();
  }
}
