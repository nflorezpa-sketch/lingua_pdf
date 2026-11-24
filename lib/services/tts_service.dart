import 'package:flutter_tts/flutter_tts.dart';

import '../core/languages.dart';
import 'settings_service.dart';

/// Pronunciación con el motor de voz del sistema (funciona sin internet
/// si el teléfono tiene instalada la voz del idioma).
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  /// Devuelve false si el idioma no tiene voz instalada en el dispositivo.
  Future<bool> speak(String text, AppLanguage lang, {double? rate}) async {
    await _init();
    await _tts.stop();
    final available = await _tts.isLanguageAvailable(lang.ttsLocale);
    if (available == false) {
      // Intento con el código corto ("en") antes de rendirnos.
      final short = await _tts.isLanguageAvailable(lang.code);
      if (short == false) return false;
      await _tts.setLanguage(lang.code);
    } else {
      await _tts.setLanguage(lang.ttsLocale);
    }
    await _tts.setSpeechRate(rate ?? SettingsService.instance.speechRate);
    await _tts.setPitch(1.0);
    await _tts.speak(text);
    return true;
  }

  Future<void> stop() => _tts.stop();
}
