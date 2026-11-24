import 'package:flutter/material.dart';

import '../services/tts_service.dart';
import '../services/vocabulary_service.dart';

/// Palabras guardadas desde el lector, con su frase de contexto.
class VocabularyScreen extends StatelessWidget {
  const VocabularyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vocab = VocabularyService.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: vocab,
      builder: (context, _) {
        final items = vocab.entries;
        return CustomScrollView(slivers: [
          SliverAppBar.large(title: Text('Vocabulario (${items.length})')),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.bookmark_add_outlined, size: 64, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Aún no has guardado palabras', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Pulsa el marcador del cuadro de traducción para guardarlas aquí y repasarlas.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final e = items[i];
                  return Dismissible(
                    key: ValueKey('${e.key}${e.savedAt}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: theme.colorScheme.errorContainer,
                      child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
                    ),
                    onDismissed: (_) => vocab.remove(e),
                    child: Card.outlined(
                      child: ExpansionTile(
                        shape: const Border(),
                        leading: IconButton(
                          tooltip: 'Escuchar',
                          icon: const Icon(Icons.volume_up_rounded),
                          onPressed: () => TtsService.instance.speak(e.word, e.source, rate: 0.4),
                        ),
                        title: Text(e.word, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${e.source.flag} → ${e.target.flag}  ${e.translation}'),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('“${e.sentence}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                          if (e.explanation != null && e.explanation!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(e.explanation!),
                          ],
                          if (e.bookTitle != null) ...[
                            const SizedBox(height: 6),
                            Text('📖 ${e.bookTitle}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ]);
      },
    );
  }
}
