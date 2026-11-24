import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/languages.dart';

/// Ajustes globales de la app (persistidos).
class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const defaultAiModel = 'claude-opus-5-5';

  late SharedPreferences _prefs;
  final _secure = const FlutterSecureStorage();

  AppLanguage sourceLanguage = Languages.english;
  AppLanguage targetLanguage = Languages.spanish;
  bool autoDetectSource = true;
  bool useAi = false;
  String aiModel = defaultAiModel;
  String _apiKey = '';
  double speechRate = 0.45;
  ThemeMode themeMode = ThemeMode.system;
  /// Aspecto de las páginas del PDF:
  /// 0 = automático (noche si la app está en oscuro), 1 = sepia, 2 = noche, 3 = normal.
  int pageMode = 0;

  String get apiKey => _apiKey;
  bool get aiAvailable => useAi && _apiKey.trim().isNotEmpty;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    sourceLanguage = Languages.byCode(_prefs.getString('source'), fallback: Languages.english);
    targetLanguage = Languages.byCode(_prefs.getString('target'), fallback: Languages.spanish);
    autoDetectSource = _prefs.getBool('autoDetect') ?? true;
    useAi = _prefs.getBool('useAi') ?? false;
    aiModel = _prefs.getString('aiModel') ?? defaultAiModel;
    speechRate = _prefs.getDouble('speechRate') ?? 0.45;
    themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.system.index];
    pageMode = _prefs.getInt('pageMode') ?? 0;
    try {
      _apiKey = await _secure.read(key: 'anthropic_api_key') ?? '';
    } catch (_) {
      _apiKey = '';
    }
  }

  Future<void> setSource(AppLanguage l) async {
    sourceLanguage = l;
    await _prefs.setString('source', l.code);
    notifyListeners();
  }

  Future<void> setTarget(AppLanguage l) async {
    targetLanguage = l;
    await _prefs.setString('target', l.code);
    notifyListeners();
  }

  Future<void> swapLanguages() async {
    final s = sourceLanguage;
    sourceLanguage = targetLanguage;
    targetLanguage = s;
    await _prefs.setString('source', sourceLanguage.code);
    await _prefs.setString('target', targetLanguage.code);
    notifyListeners();
  }

  Future<void> setAutoDetect(bool v) async {
    autoDetectSource = v;
    await _prefs.setBool('autoDetect', v);
    notifyListeners();
  }

  Future<void> setUseAi(bool v) async {
    useAi = v;
    await _prefs.setBool('useAi', v);
    notifyListeners();
  }

  Future<void> setAiModel(String v) async {
    aiModel = v.trim().isEmpty ? defaultAiModel : v.trim();
    await _prefs.setString('aiModel', aiModel);
    notifyListeners();
  }

  Future<void> setApiKey(String v) async {
    _apiKey = v.trim();
    await _secure.write(key: 'anthropic_api_key', value: _apiKey);
    notifyListeners();
  }

  Future<void> setSpeechRate(double v) async {
    speechRate = v;
    await _prefs.setDouble('speechRate', v);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  Future<void> setPageMode(int v) async {
    pageMode = v;
    await _prefs.setInt('pageMode', v);
    notifyListeners();
  }
}
