import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/settings_screen.dart';
import '../services/library_service.dart';
import '../services/settings_service.dart';
import '../services/translation_service.dart';
import '../widgets/language_bar.dart';
import 'translation_popup.dart';
import 'word_locator.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});
  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ActiveWord {
  _ActiveWord(this.hit, this.future);
  final WordHit hit;
  final Future<TranslationResult> future;
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _controller = PdfViewerController();
  late final _locator = WordLocator(_controller);
  final _stackKey = GlobalKey();
  final _settings = SettingsService.instance;

  _ActiveWord? _active;
  bool _chrome = true;
  int _page = 1;
  int _pageCount = 0;
  bool _showHint = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _page = widget.book.lastPage;
    _controller.addListener(_onViewerChanged);
    _settings.addListener(_onSettings);
    _prepareModels();
    _maybeShowHint();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    LibraryService.instance.updateProgress(widget.book, page: _page, pageCount: _pageCount);
    _controller.removeListener(_onViewerChanged);
    _settings.removeListener(_onSettings);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onSettings() => setState(() {});

  /// El cuadro sigue a la palabra al hacer scroll / zoom.
  void _onViewerChanged() {
    if (_active != null && mounted) setState(() {});
  }

  Future<void> _maybeShowHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('hintShown') ?? false)) {
      setState(() => _showHint = true);
      await prefs.setBool('hintShown', true);
    }
  }

  Future<void> _prepareModels() async {
    final t = TranslationService.instance;
    final s = _settings.sourceLanguage, d = _settings.targetLanguage;
    if (await t.isModelDownloaded(s) && await t.isModelDownloaded(d)) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      duration: Duration(seconds: 3),
      content: Text('Descargando diccionarios offline (solo la primera vez)…'),
    ));
    try {
      await t.ensureModels(s, d);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  bool _onTap(BuildContext context, PdfViewerController c, PdfViewerGeneralTapHandlerDetails d) {
    switch (d.type) {
      case PdfViewerGeneralTapType.longPress:
        _lookup(d.documentPosition);
        return true;
      case PdfViewerGeneralTapType.tap:
        if (_active != null) {
          setState(() => _active = null);
        } else {
          _toggleChrome();
        }
        return true;
      default:
        return false;
    }
  }

  Future<void> _lookup(Offset docPos) async {
    final hit = await _locator.locate(docPos);
    if (!mounted) return;
    if (hit == null) {
      setState(() => _active = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          duration: Duration(seconds: 2),
          content: Text('No hay texto aquí (¿es un PDF escaneado como imagen?)'),
        ));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _showHint = false;
      _active = _ActiveWord(
        hit,
        TranslationService.instance
            .translate(word: hit.word, sentence: hit.sentence, wordOffset: hit.wordOffset),
      );
    });
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(_chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _onPageChanged(int? page) {
    if (page == null) return;
    setState(() => _page = page);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      LibraryService.instance.updateProgress(widget.book, page: page, pageCount: _pageCount);
    });
  }

  /// Rectángulo de la palabra convertido a coordenadas del Stack.
  Rect? _anchorInStack(WordHit hit) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !_controller.isReady) return null;
    final tl = _controller.documentToGlobal(hit.documentRect.topLeft);
    final br = _controller.documentToGlobal(hit.documentRect.bottomRight);
    if (tl == null || br == null) return null;
    return Rect.fromPoints(stackBox.globalToLocal(tl), stackBox.globalToLocal(br));
  }

  bool get _appDark => Theme.of(context).brightness == Brightness.dark;

  /// Modo efectivo: "automático" = noche en tema oscuro, normal en claro.
  int get _effectiveMode => _settings.pageMode == 0 ? (_appDark ? 2 : 3) : _settings.pageMode;

  ColorFilter? get _pageFilter => switch (_effectiveMode) {
        1 => const ColorFilter.matrix([
            0.393, 0.769, 0.189, 0, 0, //
            0.349, 0.686, 0.168, 0, 0,
            0.272, 0.534, 0.131, 0, 0,
            0, 0, 0, 1, 0,
          ]),
        2 => const ColorFilter.matrix([
            -0.9, 0, 0, 0, 230, //
            0, -0.9, 0, 0, 230,
            0, 0, -0.9, 0, 230,
            0, 0, 0, 1, 0,
          ]),
        _ => null,
      };

  Color get _viewerBackground => switch (_effectiveMode) {
        1 => _appDark ? const Color(0xFF2A251C) : const Color(0xFFE9E0CC),
        2 => const Color(0xFF0C0D11),
        _ => _appDark ? const Color(0xFF17181E) : const Color(0xFFE8E8EC),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewer = PdfViewer.file(
      widget.book.path,
      controller: _controller,
      initialPageNumber: widget.book.lastPage,
      params: PdfViewerParams(
        backgroundColor: _viewerBackground,
        pageImageColorFilter: _pageFilter,
        // Desactivamos la selección nativa: la pulsación larga = traducir.
        textSelectionParams: const PdfTextSelectionParams(enabled: false),
        onGeneralTap: _onTap,
        onPageChanged: _onPageChanged,
        onViewerReady: (doc, c) {
          setState(() => _pageCount = doc.pages.length);
          LibraryService.instance.updateProgress(widget.book, page: _page, pageCount: _pageCount);
        },
        loadingBannerBuilder: (context, downloaded, total) =>
            const Center(child: CircularProgressIndicator()),
      ),
    );

    final active = _active;
    final anchor = active == null ? null : _anchorInStack(active.hit);

    return Scaffold(
      backgroundColor: _viewerBackground,
      body: Stack(
        key: _stackKey,
        children: [
          Positioned.fill(child: viewer),
          if (active != null && anchor != null)
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) => TranslationPopup(
                  key: ValueKey(active.hit.documentRect),
                  word: active.hit.word,
                  anchor: anchor,
                  bounds: constraints.biggest,
                  future: active.future,
                  bookTitle: widget.book.title,
                  topInset: MediaQuery.paddingOf(context).top + (_chrome ? 56 : 0),
                  bottomInset: MediaQuery.paddingOf(context).bottom + (_chrome ? 64 : 0),
                  onClose: () => setState(() => _active = null),
                ),
              ),
            ),
          if (_showHint) _hint(theme),
          // Barra superior
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _chrome ? 0 : -140,
            left: 0,
            right: 0,
            child: _topBar(theme),
          ),
          // Barra inferior
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _chrome ? 0 : -120,
            left: 0,
            right: 0,
            child: _bottomBar(theme),
          ),
        ],
      ),
    );
  }

  Widget _topBar(ThemeData theme) => Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.96),
        elevation: 2,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              const BackButton(),
              Expanded(
                child: Text(widget.book.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              ),
              const LanguageBar(compact: true),
              PopupMenuButton<int>(
                tooltip: 'Modo de página',
                icon: const Icon(Icons.contrast_rounded),
                initialValue: _settings.pageMode,
                onSelected: _settings.setPageMode,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('Automático (según el tema)')),
                  PopupMenuItem(value: 3, child: Text('Página normal')),
                  PopupMenuItem(value: 1, child: Text('Sepia (descanso visual)')),
                  PopupMenuItem(value: 2, child: Text('Noche')),
                ],
              ),
              IconButton(
                tooltip: 'Ajustes',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ]),
          ),
        ),
      );

  Widget _bottomBar(ThemeData theme) {
    final count = _pageCount;
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(children: [
            Text('$_page / ${count == 0 ? '–' : count}', style: theme.textTheme.labelLarge),
            Expanded(
              child: count <= 1
                  ? const SizedBox(height: 48)
                  : Slider(
                      value: _page.clamp(1, count).toDouble(),
                      min: 1,
                      max: count.toDouble(),
                      divisions: count - 1,
                      label: '$_page',
                      onChanged: (v) => setState(() => _page = v.round()),
                      onChangeEnd: (v) => _controller.goToPage(pageNumber: v.round()),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _hint(ThemeData theme) => Positioned(
        left: 24,
        right: 24,
        bottom: 110,
        child: Material(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(children: [
              Icon(Icons.touch_app_rounded, color: theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Mantén el dedo sobre cualquier palabra para ver su traducción en contexto y escuchar cómo se pronuncia.',
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: theme.colorScheme.onPrimaryContainer,
                onPressed: () => setState(() => _showHint = false),
              ),
            ]),
          ),
        ),
      );
}
