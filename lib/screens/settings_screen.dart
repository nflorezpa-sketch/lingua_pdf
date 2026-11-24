import 'package:flutter/material.dart';

import '../core/languages.dart';
import '../services/settings_service.dart';
import '../services/translation_service.dart';
import '../services/tts_service.dart';
import '../widgets/language_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = SettingsService.instance;
  late final _keyCtrl = TextEditingController(text: s.apiKey);
  late final _modelCtrl = TextEditingController(text: s.aiModel);
  bool _obscure = true;

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _section('Idiomas', theme),
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: const Text('Traducción'),
              subtitle: Text(
                  '${s.autoDetectSource ? 'Detección automática' : s.sourceLanguage.name} → ${s.targetLanguage.name}'),
              onTap: () => showLanguageSheet(context),
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Diccionarios offline'),
              subtitle: const Text('Descarga los idiomas para traducir sin internet'),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const _OfflineModelsScreen())),
            ),
            _section('Pronunciación', theme),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const Text('Velocidad de la voz'),
              subtitle: Slider(
                value: s.speechRate,
                min: 0.2,
                max: 0.8,
                divisions: 6,
                label: s.speechRate.toStringAsFixed(1),
                onChanged: s.setSpeechRate,
              ),
              trailing: IconButton(
                tooltip: 'Probar',
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: () => TtsService.instance
                    .speak('The quick brown fox jumps over the lazy dog.', Languages.english),
              ),
            ),
            _section('Traducción con IA (opcional)', theme),
            SwitchListTile(
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Usar IA para el contexto'),
              subtitle: const Text(
                  'Claude elige el significado exacto de la palabra en la frase, detecta expresiones y phrasal verbs y explica su uso. Necesita internet y una API key de Anthropic.'),
              value: s.useAi,
              onChanged: s.setUseAi,
            ),
            if (s.useAi) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _keyCtrl,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key de Anthropic',
                    hintText: 'sk-ant-…',
                    helperText: 'Se guarda cifrada solo en este dispositivo (console.anthropic.com)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  onChanged: s.setApiKey,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Modelo',
                    helperText: 'Por defecto: ${SettingsService.defaultAiModel}',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: s.setAiModel,
                  onTapOutside: (_) => s.setAiModel(_modelCtrl.text),
                ),
              ),
              if (s.apiKey.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Sin API key se usará la traducción offline.'),
                ),
            ],
            _section('Créditos', theme),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Diccionario inglés–español'),
              subtitle: const Text(
                  'Datos de Wiktionary (wiktionary.org), extraídos con wiktextract (kaikki.org). '
                  'Licencia CC BY-SA 4.0. Traducción automática: Google ML Kit.'),
              onTap: () => showLicensePage(context: context, applicationName: 'LinguaPDF'),
            ),
            _section('Apariencia', theme),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: const Text('Tema'),
              trailing: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined)),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.setThemeMode(v.first),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(title,
            style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
      );
}

class _OfflineModelsScreen extends StatefulWidget {
  const _OfflineModelsScreen();

  @override
  State<_OfflineModelsScreen> createState() => _OfflineModelsScreenState();
}

class _OfflineModelsScreenState extends State<_OfflineModelsScreen> {
  final _t = TranslationService.instance;
  final Map<String, bool> _downloaded = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final l in Languages.all) {
      _downloaded[l.code] = await _t.isModelDownloaded(l);
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggle(AppLanguage l) async {
    setState(() => _busy.add(l.code));
    try {
      if (_downloaded[l.code] == true) {
        await _t.deleteModel(l);
      } else {
        await _t.downloadModel(l);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    _busy.remove(l.code);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diccionarios offline')),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Cada idioma ocupa unos 30 MB. El inglés viene incluido como base.'),
        ),
        for (final l in Languages.all)
          ListTile(
            leading: Text(l.flag, style: const TextStyle(fontSize: 24)),
            title: Text(l.name),
            trailing: _busy.contains(l.code)
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : _downloaded[l.code] == null
                    ? null
                    : _downloaded[l.code]!
                        ? IconButton(
                            tooltip: 'Borrar',
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            onPressed: l.code == 'en' ? null : () => _toggle(l),
                          )
                        : IconButton(
                            tooltip: 'Descargar',
                            icon: const Icon(Icons.download_rounded),
                            onPressed: () => _toggle(l),
                          ),
          ),
      ]),
    );
  }
}
