import 'package:google_mlkit_translation/google_mlkit_translation.dart';

/// Idioma soportado por la app: traducción offline (ML Kit) + voz (TTS).
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.name,
    required this.flag,
    required this.ttsLocale,
    required this.mlkit,
  });

  /// Código BCP-47 corto ("en", "es"...).
  final String code;

  /// Nombre visible en español.
  final String name;
  final String flag;

  /// Locale usado por el motor de voz del sistema.
  final String ttsLocale;
  final TranslateLanguage mlkit;

  @override
  bool operator ==(Object other) => other is AppLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

class Languages {
  static const english = AppLanguage(
      code: 'en', name: 'Inglés', flag: '🇬🇧', ttsLocale: 'en-US', mlkit: TranslateLanguage.english);
  static const spanish = AppLanguage(
      code: 'es', name: 'Español', flag: '🇪🇸', ttsLocale: 'es-ES', mlkit: TranslateLanguage.spanish);

  static const all = <AppLanguage>[
    english,
    spanish,
    AppLanguage(code: 'fr', name: 'Francés', flag: '🇫🇷', ttsLocale: 'fr-FR', mlkit: TranslateLanguage.french),
    AppLanguage(code: 'de', name: 'Alemán', flag: '🇩🇪', ttsLocale: 'de-DE', mlkit: TranslateLanguage.german),
    AppLanguage(code: 'it', name: 'Italiano', flag: '🇮🇹', ttsLocale: 'it-IT', mlkit: TranslateLanguage.italian),
    AppLanguage(code: 'pt', name: 'Portugués', flag: '🇵🇹', ttsLocale: 'pt-PT', mlkit: TranslateLanguage.portuguese),
    AppLanguage(code: 'nl', name: 'Neerlandés', flag: '🇳🇱', ttsLocale: 'nl-NL', mlkit: TranslateLanguage.dutch),
    AppLanguage(code: 'ca', name: 'Catalán', flag: '🏳️', ttsLocale: 'ca-ES', mlkit: TranslateLanguage.catalan),
    AppLanguage(code: 'ru', name: 'Ruso', flag: '🇷🇺', ttsLocale: 'ru-RU', mlkit: TranslateLanguage.russian),
    AppLanguage(code: 'ja', name: 'Japonés', flag: '🇯🇵', ttsLocale: 'ja-JP', mlkit: TranslateLanguage.japanese),
    AppLanguage(code: 'zh', name: 'Chino', flag: '🇨🇳', ttsLocale: 'zh-CN', mlkit: TranslateLanguage.chinese),
    AppLanguage(code: 'ko', name: 'Coreano', flag: '🇰🇷', ttsLocale: 'ko-KR', mlkit: TranslateLanguage.korean),
  ];

  static AppLanguage byCode(String? code, {AppLanguage fallback = english}) {
    if (code == null) return fallback;
    for (final l in all) {
      if (l.code == code) return l;
    }
    return fallback;
  }

  static AppLanguage? tryByCode(String? code) {
    for (final l in all) {
      if (l.code == code) return l;
    }
    return null;
  }
}
