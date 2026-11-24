import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../reader/reader_screen.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../widgets/language_bar.dart';
import 'settings_screen.dart';
import 'vocabulary_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [_LibraryTab(), VocabularyScreen()],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => importPdf(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Añadir PDF'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Biblioteca'),
          NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined), selectedIcon: Icon(Icons.bookmarks), label: 'Vocabulario'),
        ],
      ),
    );
  }
}

Future<void> importPdf(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
  if (files.isEmpty || files.first.path == null) return;
  try {
    final book = await LibraryService.instance.importFile(files.first.path!, name: files.first.name);
    navigator.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir el PDF: $e')));
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context) {
    final lib = LibraryService.instance;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final books = lib.books;
        return CustomScrollView(slivers: [
          SliverAppBar.large(
            title: const Text('Mis libros'),
            actions: [
              const LanguageBar(),
              IconButton(
                tooltip: 'Tema claro / oscuro',
                icon: Icon(theme.brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined),
                onPressed: () => SettingsService.instance.setThemeMode(
                    theme.brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark),
              ),
              IconButton(
                tooltip: 'Ajustes',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          if (books.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.auto_stories_outlined, size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Tu biblioteca está vacía', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Añade un PDF en inglés (u otro idioma). Mientras lees, mantén el dedo sobre una palabra para traducirla y escuchar su pronunciación.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 80),
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList.separated(
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _BookTile(book: books[i]),
              ),
            ),
        ]);
      },
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.filled(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Container(
              width: 52,
              height: 70,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.picture_as_pdf_rounded, color: theme.colorScheme.onPrimaryContainer, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(book.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  book.pageCount > 0 ? 'Página ${book.lastPage} de ${book.pageCount}' : 'Sin abrir',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: book.progress, borderRadius: BorderRadius.circular(4)),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final ctrl = TextEditingController(text: book.title);
                  final name = await showDialog<String>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Renombrar'),
                      content: TextField(controller: ctrl, autofocus: true),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Guardar')),
                      ],
                    ),
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await LibraryService.instance.rename(book, name.trim());
                  }
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('¿Quitar de la biblioteca?'),
                      content: Text('Se borrará la copia de "${book.title}" guardada en la app.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Quitar')),
                      ],
                    ),
                  );
                  if (ok == true) await LibraryService.instance.remove(book);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Renombrar')),
                PopupMenuItem(value: 'delete', child: Text('Quitar')),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
