import 'package:flutter/material.dart';

import '../core/languages.dart';
import '../services/settings_service.dart';

/// Chip "🇬🇧 → 🇪🇸" que abre el selector de idiomas.
class LanguageBar extends StatelessWidget {
  const LanguageBar({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final src = s.autoDetectSource ? 'Auto' : s.sourceLanguage.code.toUpperCase();
        return ActionChip(
          visualDensity: compact ? VisualDensity.compact : null,
          avatar: Text(s.autoDetectSource ? '🌐' : s.sourceLanguage.flag),
          label: Text('$src → ${s.targetLanguage.flag} ${s.targetLanguage.code.toUpperCase()}'),
          tooltip: 'Idiomas de traducción',
          onPressed: () => showLanguageSheet(context),
        );
      },
    );
  }
}

Future<void> showLanguageSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => const _LanguageSheet(),
  );
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  @override
  Widget build(BuildContext context) {
    final s = SettingsService.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Idiomas', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _LangDropdown(
                    label: 'Idioma del libro',
                    value: s.sourceLanguage,
                    enabled: !s.autoDetectSource,
                    onChanged: s.setSource,
                  ),
                ),
                IconButton(
                  tooltip: 'Intercambiar',
                  onPressed: s.autoDetectSource ? null : s.swapLanguages,
                  icon: const Icon(Icons.swap_horiz_rounded),
                ),
                Expanded(
                  child: _LangDropdown(
                    label: 'Traducir a',
                    value: s.targetLanguage,
                    onChanged: s.setTarget,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Detectar el idioma automáticamente'),
                subtitle: const Text('Útil en libros que mezclan idiomas'),
                value: s.autoDetectSource,
                onChanged: s.setAutoDetect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangDropdown extends StatelessWidget {
  const _LangDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final AppLanguage value;
  final ValueChanged<AppLanguage> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AppLanguage>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final l in Languages.all)
          DropdownMenuItem(value: l, child: Text('${l.flag}  ${l.name}', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: enabled ? (l) => l == null ? null : onChanged(l) : null,
    );
  }
}
