import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/languages.dart';
import 'translation_service.dart';

class VocabEntry {
  VocabEntry({
    required this.word,
    required this.translation,
    required this.sentence,
    required this.sourceCode,
    required this.targetCode,
    required this.savedAt,
    this.bookTitle,
    this.explanation,
  });

  final String word;
  final String translation;
  final String sentence;
  final String sourceCode;
  final String targetCode;
  final DateTime savedAt;
  final String? bookTitle;
  final String? explanation;

  AppLanguage get source => Languages.byCode(sourceCode);
  AppLanguage get target => Languages.byCode(targetCode, fallback: Languages.spanish);

  String get key => '$sourceCode|${word.toLowerCase()}';

  Map<String, dynamic> toJson() => {
        'word': word,
        'translation': translation,
        'sentence': sentence,
        'source': sourceCode,
        'target': targetCode,
        'savedAt': savedAt.toIso8601String(),
        'book': bookTitle,
        'explanation': explanation,
      };

  factory VocabEntry.fromJson(Map<String, dynamic> j) => VocabEntry(
        word: j['word'] as String,
        translation: j['translation'] as String,
        sentence: j['sentence'] as String,
        sourceCode: j['source'] as String,
        targetCode: j['target'] as String,
        savedAt: DateTime.parse(j['savedAt'] as String),
        bookTitle: j['book'] as String?,
        explanation: j['explanation'] as String?,
      );
}

/// Palabras guardadas por el usuario para repasar.
class VocabularyService extends ChangeNotifier {
  VocabularyService._();
  static final VocabularyService instance = VocabularyService._();

  final List<VocabEntry> _entries = [];
  List<VocabEntry> get entries => List.unmodifiable(_entries.reversed);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('vocab');
    _entries.clear();
    if (raw != null) {
      _entries.addAll((jsonDecode(raw) as List).map((e) => VocabEntry.fromJson(e as Map<String, dynamic>)));
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vocab', jsonEncode(_entries.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  bool contains(String word, AppLanguage source) =>
      _entries.any((e) => e.key == '${source.code}|${word.toLowerCase()}');

  Future<void> toggle(TranslationResult r, {String? bookTitle}) async {
    final key = '${r.source.code}|${r.word.toLowerCase()}';
    final idx = _entries.indexWhere((e) => e.key == key);
    if (idx >= 0) {
      _entries.removeAt(idx);
    } else {
      _entries.add(VocabEntry(
        word: r.word,
        translation: r.wordTranslation,
        sentence: r.sentence,
        sourceCode: r.source.code,
        targetCode: r.target.code,
        savedAt: DateTime.now(),
        bookTitle: bookTitle,
        explanation: r.explanation,
      ));
    }
    await _save();
  }

  Future<void> remove(VocabEntry e) async {
    _entries.remove(e);
    await _save();
  }
}
