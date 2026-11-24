import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import 'screens/home_screen.dart';
import 'services/dictionary_service.dart';
import 'services/library_service.dart';
import 'services/settings_service.dart';
import 'services/vocabulary_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  await SettingsService.instance.load();
  await LibraryService.instance.load();
  await VocabularyService.instance.load();
  DictionaryService.instance.warmUp();
  runApp(const LinguaPdfApp());
}

class AppTheme {
  static const seed = Color(0xFF3F51B5);

  static ThemeData light() => _base(ColorScheme.fromSeed(seedColor: seed));

  /// Tema oscuro pensado para leer de noche: fondos casi negros,
  /// texto sin blanco puro y acentos suaves.
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: const Color(0xFF121318),
      surfaceContainerLowest: const Color(0xFF0C0D11),
      surfaceContainerLow: const Color(0xFF17181E),
      surfaceContainer: const Color(0xFF1B1C22),
      surfaceContainerHigh: const Color(0xFF23242B),
      surfaceContainerHighest: const Color(0xFF2C2D35),
      onSurface: const Color(0xFFE4E3EA),
      // El cuadro de traducción usa inverseSurface: en oscuro, claro y legible.
      inverseSurface: const Color(0xFFE4E3EA),
      onInverseSurface: const Color(0xFF1B1C22),
      inversePrimary: const Color(0xFF3949AB),
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
      ),
      cardTheme: CardThemeData(color: scheme.surfaceContainerHigh),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

class LinguaPdfApp extends StatelessWidget {
  const LinguaPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'LinguaPDF',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: settings.themeMode,
        themeAnimationDuration: const Duration(milliseconds: 250),
        home: const HomeScreen(),
      ),
    );
  }
}
