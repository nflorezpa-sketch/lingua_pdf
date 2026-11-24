import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// Un significado: traducciones al español + pista del sentido en inglés.
class DictSense {
  DictSense({this.gloss, required this.es, this.inContext = false});
  final String? gloss;
  final List<String> es;

  /// Es el significado que encaja con la frase que se está leyendo.
  bool inContext;
}

class DictEntry {
  DictEntry({
    required this.word,
    this.pos,
    this.ipa,
    required this.senses,
    this.formInfo,
  });

  /// Forma base (lema) de la palabra.
  final String word;
  final String? pos;
  final String? ipa;
  final List<DictSense> senses;

  /// Si se llegó desde una forma flexionada: "present participle of pick".
  final String? formInfo;
}

/// Diccionario offline inglés→español generado a partir de Wiktionary
/// (tools/build_dictionary.py). Datos bajo CC BY-SA 4.0.
class DictionaryService {
  DictionaryService._();
  static final DictionaryService instance = DictionaryService._();

  static const _asset = 'assets/dict/en_es.db';
  static const _version = 1; // súbelo al regenerar la base de datos

  Database? _db;
  Future<Database?>? _opening;

  bool supports(String source, String target) => source == 'en' && target == 'es';

  Future<Database?> _open() => _opening ??= _doOpen();

  Future<Database?> _doOpen() async {
    try {
      final dir = await getDatabasesPath();
      final path = p.join(dir, 'en_es_v$_version.db');
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt('dictVersion') != _version || !File(path).existsSync()) {
        final data = await rootBundle.load(_asset);
        await Directory(dir).create(recursive: true);
        await File(path).writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true);
        await prefs.setInt('dictVersion', _version);
      }
      _db = await openDatabase(path, readOnly: true);
      return _db;
    } catch (_) {
      return null; // sin diccionario la app sigue con ML Kit
    }
  }

  /// Copia el diccionario en segundo plano al arrancar (la primera vez tarda).
  void warmUp() => _open();

  /// Busca la palabra; si es una forma flexionada ("went", "picking")
  /// devuelve también la entrada del lema.
  Future<List<DictEntry>> lookup(String word, {int max = 3}) async {
    final db = await _open();
    if (db == null) return [];
    final key = _norm(word);
    if (key.isEmpty) return [];

    final out = <DictEntry>[];
    final seen = <String>{};

    Future<void> addEntries(String k, {String? formInfo}) async {
      if (out.length >= max || seen.contains(k)) return;
      seen.add(k);
      final rows = await db.query('entries', where: 'key = ?', whereArgs: [k], limit: 8);
      // Una forma flexionada solo encaja con cierta categoría:
      // "picking" (gerundio) viene del verbo, no del sustantivo "pick".
      final allowed = formInfo == null ? null : _posForForm(formInfo);
      for (final r in rows) {
        if (out.length >= max) break;
        if (allowed != null && !allowed.contains(r['pos'])) continue;
        final senses = await db.query('senses',
            columns: ['gloss', 'es'],
            where: 'entry_id = ?',
            whereArgs: [r['id']],
            orderBy: 'idx');
        out.add(DictEntry(
          word: r['word'] as String,
          pos: r['pos'] as String?,
          ipa: r['ipa'] as String?,
          formInfo: formInfo,
          senses: [
            for (final s in senses)
              DictSense(
                gloss: s['gloss'] as String?,
                es: (s['es'] as String).split(', ').where((e) => e.isNotEmpty).toList(),
              ),
          ],
        ));
      }
    }

    await addEntries(key);
    final forms = await db.query('forms',
        columns: ['lemma', 'info'], where: 'key = ?', whereArgs: [key], limit: 4);
    for (final f in forms) {
      final info = (f['info'] as String?)?.trim();
      await addEntries(_norm(f['lemma'] as String),
          formInfo: info == null || info.isEmpty ? 'forma de ${f['lemma']}' : info);
    }
    if (out.isEmpty) {
      for (final c in _guessLemmas(key)) {
        await addEntries(c, formInfo: 'forma de $c');
        if (out.isNotEmpty) break;
      }
    }
    return out;
  }

  /// "picking up" -> busca "pick up" (lema del verbo + partícula).
  Future<List<DictEntry>> lookupPhrase(String phrase) async {
    final db = await _open();
    if (db == null) return [];
    final parts = _norm(phrase).split(' ');
    if (parts.length < 2) return [];
    final direct = await lookup(parts.join(' '), max: 1);
    if (direct.isNotEmpty) return direct;
    final first = parts.first;
    final rest = parts.sublist(1).join(' ');
    final lemmas = <String>{
      ...(await db.query('forms', columns: ['lemma'], where: 'key = ?', whereArgs: [first]))
          .map((r) => _norm(r['lemma'] as String)),
      ..._guessLemmas(first),
    };
    for (final l in lemmas) {
      final r = await lookup('$l $rest', max: 1);
      if (r.isNotEmpty) return r;
    }
    return [];
  }

  /// Marca el significado cuya traducción coincide con la traducción en contexto.
  static void markContext(List<DictEntry> entries, String contextual) {
    final ctx = _stem(contextual);
    if (ctx.isEmpty) return;
    for (final e in entries) {
      for (final s in e.senses) {
        for (final w in s.es) {
          final st = _stem(w);
          if (st.isEmpty) continue;
          final n = st.length < ctx.length ? st.length : ctx.length;
          final k = n < 5 ? n : 5;
          if (st == ctx || (k >= 4 && st.substring(0, k) == ctx.substring(0, k))) {
            s.inContext = true;
            return;
          }
        }
      }
    }
  }

  static Set<String>? _posForForm(String info) {
    final i = info.toLowerCase();
    if (i.contains('participle') || i.contains('past') || i.contains('third-person')) {
      return {'verbo'};
    }
    if (i.contains('plural')) return {'sustantivo', 'pronombre', 'determinante'};
    if (i.contains('comparative') || i.contains('superlative')) return {'adjetivo', 'adverbio'};
    return null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r"^[^a-z0-9']+|[^a-z0-9']+$"), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Quita acentos, "se"/artículos y deja la primera palabra significativa.
  static String _stem(String s) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    var r = s.toLowerCase().trim();
    for (var i = 0; i < from.length; i++) {
      r = r.replaceAll(from[i], to[i]);
    }
    final words = r
        .split(RegExp(r'[\s,;()]+'))
        .where((w) => w.isNotEmpty && !const {'se', 'el', 'la', 'los', 'las', 'un', 'una', 'de', 'lo'}.contains(w))
        .toList();
    return words.isEmpty ? '' : words.first;
  }

  /// Heurística para formas que no estén en la tabla: "breaks" -> "break".
  static List<String> _guessLemmas(String w) {
    final c = <String>[];
    void add(String s) {
      if (s.length >= 2 && s != w && !c.contains(s)) c.add(s);
    }

    if (w.endsWith("'s")) add(w.substring(0, w.length - 2));
    if (w.endsWith('ies')) add('${w.substring(0, w.length - 3)}y');
    if (w.endsWith('es')) add(w.substring(0, w.length - 2));
    if (w.endsWith('s')) add(w.substring(0, w.length - 1));
    if (w.endsWith('ied')) add('${w.substring(0, w.length - 3)}y');
    if (w.endsWith('ed')) {
      final b = w.substring(0, w.length - 2);
      add(b);
      add('${b}e');
      if (b.length > 2 && b[b.length - 1] == b[b.length - 2]) add(b.substring(0, b.length - 1));
    }
    if (w.endsWith('ing')) {
      final b = w.substring(0, w.length - 3);
      add(b);
      add('${b}e');
      if (b.length > 2 && b[b.length - 1] == b[b.length - 2]) add(b.substring(0, b.length - 1));
    }
    if (w.endsWith('ly')) add(w.substring(0, w.length - 2));
    return c;
  }
}
