import '../models/content_identity.dart';
import '../utils/app_failure.dart';
import '../services/source_http_client.dart';
import '../services/image_repository.dart';
import '../services/repository_image.dart';
import '../utils/network_errors.dart';
import '../widgets/webtoon_viewer.dart';
import '../providers/download_queue_provider.dart';
import '../services/bookmark_service.dart';
import '../services/alternative_chapter_service.dart';
import '../services/myanimelist_service.dart';
import 'myanimelist_screen.dart';
import '../widgets/alternative_chapter_picker.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/online_manga.dart';
import '../models/reader_settings_enums.dart';
import '../models/reading_progress.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/library_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../services/volume_button_service.dart';
import '../utils/fs_scanner.dart';
import '../utils/reader_paging.dart';
import '../services/online_catalog_service.dart';
import '../widgets/chapter_drawer.dart';

class ReaderScreen extends StatefulWidget {
  final Manga manga;
  final int initialChapterIndex;
  final int initialPageIndex;

  const ReaderScreen({
    super.key,
    required this.manga,
    required this.initialChapterIndex,
    required this.initialPageIndex,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  int _preloadRadius = 1;
  DownloadQueueProvider? _queue;
  Timer? _readerHeartbeat;
  CancellationToken? _chapterCancellation;
  String? _chapterError;
  ReaderSettingsProvider? _settings;
  String? _modeKey;
  bool _lastCrop = false;
  final Map<String, Size> _dimensions = {};
  final Set<String> _loadedPages = {};
  final Set<String> _readPages = {};
  final Map<String, ({ImageStream stream, ImageStreamListener listener})>
  _streams = {};
  int _imageRevision = 0;
  int _webtoonAnchor = 0;
  bool _originalQuality = false;
  bool _imageError = false;
  late OnlineMangaDetail _readingDetail;
  bool _loadingMoreChapters = false;
  bool _disposing = false;
  List<Chapter> get _chapters => _readingDetail.chapters;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final VolumeButtonService _volumeButtonService = VolumeButtonService();
  late int _chapterIndex;
  late int _pageIndex;
  PageController _pageController = PageController(initialPage: 0);
  final Map<String, List<String>> _chapterPagesCache = <String, List<String>>{};
  bool _showControls = true;
  bool _edgeSwipeHandled = false;
  bool _loadingChapter = true;
  int _chapterOpenGen = 0;
  Timer? _controlsHideTimer;

  Chapter? get _currentChapter {
    if (_chapters.isEmpty) {
      return null;
    }
    return _chapters[_chapterIndex];
  }

  List<String> get _pages => _currentPages;

  List<String> get _currentPages {
    final chapter = _currentChapter;
    if (chapter == null) {
      return <String>[];
    }
    return _chapterPagesCache[chapter.path] ?? chapter.pages;
  }

  bool _useDoublePage(ReaderSettingsProvider settings) {
    return settings.doublePage && settings.isHorizontal && _pages.isNotEmpty;
  }

  int _viewerItemCount(ReaderSettingsProvider settings) {
    if (_useDoublePage(settings)) {
      return ReaderPaging.spreadCount(
        _pages.length,
        coverAlone: settings.coverAlone,
      );
    }
    return _pages.length;
  }

  int _viewerIndexForPage(int pageIndex, ReaderSettingsProvider settings) {
    if (_useDoublePage(settings)) {
      return ReaderPaging.spreadForPage(
        pageIndex,
        coverAlone: settings.coverAlone,
      );
    }
    return pageIndex;
  }

  int _pageIndexForViewer(int viewerIndex, ReaderSettingsProvider settings) {
    if (_useDoublePage(settings)) {
      return ReaderPaging.firstPageForSpread(
        viewerIndex,
        coverAlone: settings.coverAlone,
      );
    }
    return viewerIndex;
  }

  @override
  void initState() {
    super.initState();
    _readingDetail = OnlineMangaDetail(
      title: widget.manga.title,
      url: widget.manga.sourceUrl ?? widget.manga.path,
      chapters: List.from(widget.manga.chapters),
      hasMoreChapters: widget.manga.hasMoreChapters,
      nextChapterCursor: widget.manga.nextChapterCursor,
    );
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
    _chapterIndex = _safeChapterIndex(widget.initialChapterIndex);
    _pageIndex = 0;
    _loadingChapter = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        context.read<LibraryProvider>().recordMangaOpen(widget.manga.path),
      );
      _settings = context.read<ReaderSettingsProvider>();
      _queue = Provider.of<DownloadQueueProvider?>(context, listen: false);
      _queue?.setReaderActive(true);
      _readerHeartbeat = Timer.periodic(const Duration(seconds: 12), (_) {
        if (mounted) {
          _queue?.setReaderActive(
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
          );
        }
      });
      _settings!.addListener(_onSettingsChanged);
      unawaited(
        _settings!.bindManga(widget.manga.sourceUrl ?? widget.manga.path),
      );
      _modeKey = _settingsKey(_settings!);
      _syncVolumeListener();
      _scheduleControlsHide();
    });
    unawaited(
      _openChapter(_chapterIndex, initialPage: widget.initialPageIndex),
    );
  }

  @override
  void dispose() {
    _disposing = true;
    _readerHeartbeat?.cancel();
    _queue?.setReaderActive(false);
    SystemChrome.setPreferredOrientations([]);
    _chapterCancellation?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_onSettingsChanged);
    unawaited(_settings?.unbindManga());
    for (final record in _streams.values) {
      record.stream.removeListener(record.listener);
    }
    _streams.clear();
    _controlsHideTimer?.cancel();
    _volumeButtonService.stopListening();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageController.dispose();
    super.dispose();
  }

  void _syncVolumeListener() {
    final settings = context.read<ReaderSettingsProvider>();
    if (settings.volumeNavigation) {
      unawaited(
        _volumeButtonService.startListening((isNextPage) {
          if (!mounted) {
            return;
          }
          _goToRelativePage(isNextPage ? 1 : -1);
        }),
      );
    } else {
      _volumeButtonService.stopListening();
    }
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    if (!_showControls) {
      return;
    }
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() => _showControls = false);
    });
  }

  int _safeChapterIndex(int value) {
    if (_chapters.isEmpty) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value >= _chapters.length) {
      return _chapters.length - 1;
    }
    return value;
  }

  Future<void> _openChapter(int index, {int initialPage = 0}) async {
    _chapterCancellation?.cancel();
    final cancellation = CancellationToken();
    _chapterCancellation = cancellation;
    final gen = ++_chapterOpenGen;
    final safeIndex = _safeChapterIndex(index);
    final chapter = _chapters.isEmpty ? null : _chapters[safeIndex];
    if (chapter == null) {
      if (!mounted || gen != _chapterOpenGen) {
        return;
      }
      setState(() {
        _chapterIndex = safeIndex;
        _pageIndex = 0;
        _loadingChapter = false;
      });
      return;
    }

    if (!mounted || gen != _chapterOpenGen) {
      return;
    }

    final chapterPath = chapter.path;

    setState(() {
      _chapterIndex = safeIndex;
      _pageIndex = 0;
      _loadingChapter = true;
      _chapterError = null;
      _imageError = false;
    });

    try {
      final List<String> pages =
          _chapterPagesCache[chapterPath] ??
          await SourceHttpClient.withCancellation(
            cancellation,
            () => _loadChapterPages(chapterPath),
          );

      // Index before images can finish the chapter, including cached local pages.
      // MAL storage failures must not prevent local reading.
      await MyAnimeListService.shared
          .registerManga(widget.manga, chapters: [chapter])
          .catchError((_) {});

      if (!mounted || gen != _chapterOpenGen) {
        return;
      }

      final settings = context.read<ReaderSettingsProvider>();
      final safePage = ReaderPaging.startPage(
        initialPage: initialPage,
        pageCount: pages.length,
      );
      final viewerIndex = settings.doublePage && settings.isHorizontal
          ? ReaderPaging.spreadForPage(
              safePage,
              coverAlone: settings.coverAlone,
            )
          : safePage;
      final firstVisible = settings.doublePage && settings.isHorizontal
          ? ReaderPaging.firstPageForSpread(
              viewerIndex,
              coverAlone: settings.coverAlone,
            )
          : safePage;
      final oldController = _pageController;

      setState(() {
        if (pages.isEmpty) {
          _chapterError = 'Este capítulo no tiene páginas disponibles.';
        }
        _chapterPagesCache[chapterPath] = pages;
        while (_chapterPagesCache.length > 3) {
          final oldest = _chapterPagesCache.keys.first;
          if (oldest == chapterPath) break;
          _chapterPagesCache.remove(oldest);
        }
        _webtoonAnchor = safePage;
        _imageRevision++;
        _pageIndex = firstVisible;
        _loadingChapter = false;
        _pageController = PageController(initialPage: viewerIndex);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        oldController.dispose();
        if (!mounted || gen != _chapterOpenGen) {
          return;
        }
        if (_pageController.hasClients) {
          final current = _pageController.page?.round();
          if (current != viewerIndex) {
            _pageController.jumpToPage(viewerIndex);
          }
        }
      });

      _recordChapterStats();
      _saveProgress();
      _precacheVisiblePages();
      final ref = widget.manga.sourceUrl ?? widget.manga.path;
      if (ContentIdentity.isRemote(ref)) {
        unawaited(
          _queue
                  ?.prepareAhead(ref, _currentChapter?.sourceUrl ?? chapterPath)
                  .catchError((_) {}) ??
              Future<void>.value(),
        );
      }
    } catch (error) {
      if (!mounted || gen != _chapterOpenGen) return;
      setState(() {
        _loadingChapter = false;
        _chapterError = NetworkErrors.friendly(error);
      });
    }
  }

  String _settingsKey(ReaderSettingsProvider settings) =>
      '${settings.readingDirection.name}|${settings.doublePage}|${settings.continuousVertical}|${settings.coverAlone}|${settings.cropWhite}|${settings.orientation}';
  void _onSettingsChanged() {
    if (!mounted || _settings == null) return;
    final next = _settingsKey(_settings!);
    if (_lastCrop != _settings!.cropWhite) {
      _lastCrop = _settings!.cropWhite;
      for (final record in _streams.values) {
        record.stream.removeListener(record.listener);
      }
      _streams.clear();
      _loadedPages.clear();
      _dimensions.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _precacheVisiblePages();
      });
    }
    unawaited(
      SystemChrome.setPreferredOrientations(switch (_settings!.orientation) {
        'portrait' => [DeviceOrientation.portraitUp],
        'landscape' => [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        _ => [],
      }),
    );
    _syncVolumeListener();
    if (next != _modeKey) {
      _modeKey = next;
      final old = _pageController;
      setState(() {
        _webtoonAnchor = _pageIndex;
        _imageRevision++;
        final viewer = _viewerIndexForPage(_pageIndex, _settings!);
        _pageIndex = _pageIndexForViewer(viewer, _settings!);
        _pageController = PageController(initialPage: viewer);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
      });
      _saveProgress();
    }
  }

  @override
  void didChangeMetrics() {
    if (!mounted || _settings?.continuousVertical != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _webtoonAnchor = _pageIndex;
          _imageRevision++;
        });
      }
    });
  }

  @override
  void didHaveMemoryPressure() {
    _preloadRadius = 0;
    PaintingBinding.instance.imageCache.clear();
    _chapterPagesCache.removeWhere((key, _) => key != _currentChapter?.path);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveProgress();
      unawaited(context.read<LibraryProvider>().flushStats());
    }
  }

  void _recordChapterStats() {
    final library = context.read<LibraryProvider>();
    unawaited(library.recordChapterOpen());
  }

  void _saveProgress() {
    final chapter = _currentChapter;
    if (chapter == null) {
      return;
    }

    final progress = ReadingProgress(
      mangaPath: widget.manga.sourceUrl ?? widget.manga.path,
      mangaTitle: widget.manga.title,
      coverPath: widget.manga.coverPath,
      chapterPath: chapter.sourceUrl ?? chapter.path,
      chapterTitle: chapter.title,
      pageIndex: _pageIndex,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      sourceId:
          OnlineCatalogService.sourceIdForRef(widget.manga.path) ??
          OnlineCatalogService.sourceIdForRef(chapter.path) ??
          (Uri.tryParse(widget.manga.path)?.hasScheme == true
              ? OnlineCatalogService.normalizeSourceId(
                  OnlineCatalogService.activeSourceId,
                )
              : null),
    );

    unawaited(
      context.read<LibraryProvider>().updateProgress(progress).catchError((
        Object error,
      ) {
        debugPrint('Progreso: $error');
      }),
    );
  }

  Future<void> _goToPageDialog() async {
    final pages = _pages;
    if (pages.isEmpty) {
      return;
    }
    final controller = TextEditingController(text: '${_pageIndex + 1}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Ir a pagina'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Pagina (1-${pages.length})',
            ),
            onSubmitted: (value) {
              final n = int.tryParse(value);
              Navigator.of(context).pop(n);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(int.tryParse(controller.text)),
              child: const Text('Ir'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null || !mounted) {
      return;
    }
    final target = (result - 1).clamp(0, pages.length - 1);
    if (context.read<ReaderSettingsProvider>().continuousVertical) {
      setState(() {
        _pageIndex = target;
        _webtoonAnchor = target;
        _imageRevision++;
      });
      _saveProgress();
      return;
    }
    final settings = context.read<ReaderSettingsProvider>();
    final viewerIndex = _viewerIndexForPage(target, settings);
    setState(() => _pageIndex = target);
    if (_pageController.hasClients) {
      await _pageController.animateToPage(
        viewerIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    }
    _saveProgress();
  }

  void _onViewerChanged(int viewerIndex) {
    if (_disposing || !mounted || _loadingChapter) {
      return;
    }
    final settings = context.read<ReaderSettingsProvider>();
    final pageIndex = _pageIndexForViewer(viewerIndex, settings);
    setState(() {
      _imageError = false;
      _pageIndex = pageIndex;
    });
    _markVisibleLoaded();
    _saveProgress();
    _precacheVisiblePages();
    _edgeSwipeHandled = false;
  }

  Future<List<String>> _loadChapterPages(String chapterPath) async {
    if (_isRemotePath(chapterPath)) {
      return OnlineCatalogService.fetchChapterPages(
        chapterPath,
        dataSaver: _originalQuality ? false : null,
      );
    }

    return compute<String, List<String>>(
      FsScanner.loadChapterPages,
      chapterPath,
    );
  }

  bool _isRemotePath(String path) {
    return ContentIdentity.isRemote(path);
  }

  bool _handleGalleryNotification(
    ScrollNotification notification,
    ReaderSettingsProvider settings,
  ) {
    if (_pages.isEmpty) {
      return false;
    }

    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _edgeSwipeHandled = false;
    }

    if (_edgeSwipeHandled) {
      return false;
    }

    final atLastPage =
        _viewerIndexForPage(_pageIndex, settings) >=
        _viewerItemCount(settings) - 1;
    final atFirstPage = _pageIndex <= 0;
    if (!atLastPage && !atFirstPage) {
      return false;
    }

    if (settings.verticalMode && notification is OverscrollNotification) {
      if (atLastPage &&
          notification.metrics.atEdge &&
          notification.metrics.pixels >= notification.metrics.maxScrollExtent &&
          notification.overscroll > 0) {
        _edgeSwipeHandled = true;
        _goNextChapter();
      } else if (atFirstPage &&
          notification.metrics.atEdge &&
          notification.metrics.pixels <= notification.metrics.minScrollExtent &&
          notification.overscroll < 0) {
        _edgeSwipeHandled = true;
        _goPrevChapter(lastPage: true);
      }
      return false;
    }

    if (notification is! UserScrollNotification) {
      return false;
    }

    if (settings.verticalMode) {
      return false;
    }

    if (atLastPage &&
        notification.direction == ScrollDirection.reverse &&
        notification.metrics.atEdge &&
        notification.metrics.pixels >= notification.metrics.maxScrollExtent) {
      _edgeSwipeHandled = true;
      _goNextChapter();
    }

    if (atFirstPage &&
        notification.direction == ScrollDirection.forward &&
        notification.metrics.atEdge &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent) {
      _edgeSwipeHandled = true;
      _goPrevChapter(lastPage: true);
    }

    return false;
  }

  void _toggleControls() {
    if (_disposing || !mounted) return;
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _scheduleControlsHide();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Future<void> _goNextChapter() async {
    final origin = _chapterIndex, gen = _chapterOpenGen;
    if (_chapterIndex + 1 >= _chapters.length &&
        _readingDetail.hasMoreChapters) {
      if (_loadingMoreChapters) return;
      _loadingMoreChapters = true;
      try {
        var detail = await OnlineCatalogService.loadMoreChapters(
          _readingDetail,
        );
        while (detail.hasMoreChapters &&
            detail.chapters.length == _chapters.length) {
          detail = await OnlineCatalogService.loadMoreChapters(detail);
        }
        if (!mounted || origin != _chapterIndex || gen != _chapterOpenGen) {
          return;
        }
        setState(() => _readingDetail = detail);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(NetworkErrors.friendly(error))),
          );
        }
        return;
      } finally {
        _loadingMoreChapters = false;
      }
    }
    if (!mounted) return;
    if (_chapterIndex + 1 >= _chapters.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No hay mas capitulos.')));
      return;
    }
    unawaited(_openChapter(_chapterIndex + 1, initialPage: 0));
  }

  void _goPrevChapter({bool lastPage = false}) {
    if (_chapterIndex - 1 < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estas en el primer capitulo.')),
      );
      return;
    }
    unawaited(_openChapter(_chapterIndex - 1, initialPage: lastPage ? -1 : 0));
  }

  void _goToRelativePage(int delta) {
    if (_disposing || !mounted) return;
    final settings = context.read<ReaderSettingsProvider>();
    final pages = _currentPages;
    if (pages.isEmpty) {
      return;
    }

    final spread = _viewerIndexForPage(_pageIndex, settings) + delta;
    final nextPage = _useDoublePage(settings)
        ? (spread < 0 ? -1 : _pageIndexForViewer(spread, settings))
        : _pageIndex + delta;

    if (nextPage < 0) {
      _goPrevChapter(lastPage: true);
      return;
    }
    if (nextPage >= pages.length) {
      _goNextChapter();
      return;
    }

    _animateToPage(nextPage, settings);
  }

  void _animateToPage(int pageIndex, ReaderSettingsProvider settings) {
    if (settings.verticalMode && settings.continuousVertical) {
      setState(() {
        _pageIndex = pageIndex;
        _webtoonAnchor = pageIndex;
        _imageRevision++;
      });
      _saveProgress();
      _precacheVisiblePages();
      return;
    }
    if (!_pageController.hasClients) {
      setState(() => _pageIndex = pageIndex);
      _saveProgress();
      return;
    }

    final viewerIndex = _viewerIndexForPage(pageIndex, settings);
    final duration = settings.transitionDuration;

    if (duration == Duration.zero) {
      _pageController.jumpToPage(viewerIndex);
      return;
    }

    unawaited(
      _pageController.animateToPage(
        viewerIndex,
        duration: duration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  ({dynamic minScale, dynamic maxScale, dynamic initialScale}) _photoScales(
    ReaderSettingsProvider settings, {
    int? index,
  }) {
    final page = (index ?? _pageIndex).clamp(
      0,
      (_pages.length - 1).clamp(0, 1 << 30),
    );
    final dimensions = _pages.isEmpty ? null : _dimensions[_pages[page]];
    dynamic scale = PhotoViewComputedScale.contained;
    if (settings.pageFitMode == PageFitMode.original) {
      scale = 1.0;
    } else if (dimensions != null) {
      final viewport = MediaQuery.sizeOf(context);
      final width =
          _useDoublePage(settings) && !(settings.coverAlone && page == 0)
          ? viewport.width / 2
          : viewport.width;
      scale = settings.pageFitMode == PageFitMode.fitWidth
          ? width / dimensions.width
          : viewport.height / dimensions.height;
    }
    return (
      minScale: settings.freeZoom
          ? PhotoViewComputedScale.contained * 0.8
          : scale,
      maxScale: settings.freeZoom ? PhotoViewComputedScale.covered * 4 : scale,
      initialScale: scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<ReaderSettingsProvider>();
    final chapter = _currentChapter;
    final pages = _currentPages;
    final isLoadingChapter = _loadingChapter;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: ChapterDrawer(
        chapters: _chapters,
        currentIndex: _chapterIndex,
        onSelect: (index) {
          Navigator.of(context).maybePop();
          unawaited(_openChapter(index));
        },
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _chapterError != null
                  ? _buildChapterError(theme)
                  : chapter == null
                  ? _buildEmptyState(theme)
                  : isLoadingChapter
                  ? _buildLoadingState(theme)
                  : pages.isEmpty
                  ? _buildEmptyState(theme)
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) =>
                          _handleGalleryNotification(notification, settings),
                      child: _buildReaderContent(theme, settings),
                    ),
            ),
            if (_chapterError == null &&
                !_imageError &&
                pages.isNotEmpty &&
                settings.tapNavigation)
              _buildTapZones()
            else if (_chapterError == null && !_imageError && pages.isNotEmpty)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                ),
              ),
            if (_showControls) _buildTopOverlay(theme, chapter, settings),
            if (_showControls) _buildBottomOverlay(theme, settings),
          ],
        ),
      ),
    );
  }

  Widget _buildTapZones() {
    final rtl = context.read<ReaderSettingsProvider>().isRightToLeft;
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _goToRelativePage(rtl ? 1 : -1),
            ),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _goToRelativePage(rtl ? -1 : 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderContent(ThemeData theme, ReaderSettingsProvider settings) {
    if (settings.verticalMode && settings.continuousVertical) {
      return WebtoonViewer(
        key: ValueKey('webtoon-${_currentChapter?.path ?? ''}-$_imageRevision'),
        initialPage: _webtoonAnchor,
        pages: _pages,
        imageProvider: _imageProviderForPath,
        onPageChanged: (page) {
          if (page != _pageIndex) _onViewerChanged(page);
        },
        onLoaded: (page) {
          _loadedPages.add(_pages[page]);
          _markVisibleLoaded();
        },
        errorBuilder: (error) => _buildImageError(theme, error),
      );
    }
    if (_useDoublePage(settings)) {
      return _buildDoublePageViewer(theme, settings);
    }
    return _buildSinglePageGallery(theme, settings);
  }

  Widget _buildSinglePageGallery(
    ThemeData theme,
    ReaderSettingsProvider settings,
  ) {
    return PhotoViewGallery.builder(
      key: ValueKey<String>(
        '$_imageRevision-gallery-${_currentChapter?.path ?? ''}',
      ),
      pageController: _pageController,
      scrollDirection: settings.verticalMode ? Axis.vertical : Axis.horizontal,
      reverse: settings.isRightToLeft,
      itemCount: _pages.length,
      backgroundDecoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      onPageChanged: _onViewerChanged,
      loadingBuilder: (context, event) => _buildPageLoading(theme, event),
      builder: (context, index) {
        final pageScales = _photoScales(settings, index: index);
        return PhotoViewGalleryPageOptions(
          imageProvider: _imageProviderForPath(_pages[index]),
          minScale: pageScales.minScale,
          maxScale: pageScales.maxScale,
          initialScale: pageScales.initialScale,
          basePosition: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) =>
              _buildImageError(theme, error),
        );
      },
    );
  }

  Widget _buildDoublePageViewer(
    ThemeData theme,
    ReaderSettingsProvider settings,
  ) {
    final spreadCount = _viewerItemCount(settings);

    return PageView.builder(
      key: ValueKey<String>(
        '$_imageRevision-spreads-${_currentChapter?.path ?? ''}',
      ),
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      reverse: settings.isRightToLeft,
      itemCount: spreadCount,
      onPageChanged: _onViewerChanged,
      itemBuilder: (context, spreadIndex) {
        final firstIndex = ReaderPaging.firstPageForSpread(
          spreadIndex,
          coverAlone: settings.coverAlone,
        );
        final secondIndex = firstIndex + 1;
        final hasSecond =
            secondIndex < _pages.length &&
            !(settings.coverAlone && spreadIndex == 0);

        Widget buildPage(int index) {
          final scales = _photoScales(settings, index: index);
          return PhotoView(
            imageProvider: _imageProviderForPath(_pages[index]),
            minScale: scales.minScale,
            maxScale: scales.maxScale,
            initialScale: scales.initialScale,
            basePosition: Alignment.center,
            filterQuality: FilterQuality.high,
            backgroundDecoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
            ),
            loadingBuilder: (context, event) => _buildPageLoading(theme, event),
            errorBuilder: (context, error, stackTrace) =>
                _buildImageError(theme, error),
          );
        }

        if (settings.isRightToLeft) {
          return Row(
            children: [
              if (hasSecond) Expanded(child: buildPage(secondIndex)),
              Expanded(child: buildPage(firstIndex)),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: buildPage(firstIndex)),
            if (hasSecond) Expanded(child: buildPage(secondIndex)),
          ],
        );
      },
    );
  }

  Widget _buildPageLoading(ThemeData theme, ImageChunkEvent? event) {
    final value = event == null || event.expectedTotalBytes == null
        ? null
        : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1);
    return Center(
      child: CircularProgressIndicator(
        value: value,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildTopOverlay(
    ThemeData theme,
    Chapter? chapter,
    ReaderSettingsProvider settings,
  ) {
    final totalPages = _currentPages.length;
    final currentPage = totalPages == 0 ? 0 : _pageIndex + 1;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
              theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (chapter != null)
                    Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (settings.showPageNumber)
              GestureDetector(
                onTap: () => unawaited(_goToPageDialog()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$currentPage/$totalPages',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: 'Marcadores y fuentes',
              onSelected: (v) {
                if (v == 'save') unawaited(_bookmark());
                if (v == 'list') unawaited(_bookmarks());
                if (v == 'source') unawaited(_alternatives());
                if (v == 'mal') {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              MyAnimeListScreen(manga: widget.manga),
                        ),
                      )
                      .then((_) {
                        if (mounted) {
                          unawaited(
                            MyAnimeListService.shared
                                .registerManga(
                                  widget.manga,
                                  chapters: [?_currentChapter],
                                )
                                .catchError((_) {}),
                          );
                        }
                      });
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'mal',
                  child: Text('Vincular con MyAnimeList'),
                ),
                PopupMenuItem(
                  value: 'save',
                  child: Text('Añadir/quitar marcador'),
                ),
                PopupMenuItem(value: 'list', child: Text('Mis marcadores')),
                PopupMenuItem(
                  value: 'source',
                  child: Text('Buscar capítulo en otra fuente'),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Calidad original para ampliar',
              icon: Icon(_originalQuality ? Icons.hd : Icons.hd_outlined),
              onPressed: () {
                final page = _pageIndex;
                setState(() {
                  _originalQuality = !_originalQuality;
                  _imageRevision++;
                });
                if (OnlineCatalogService.sourceIdForRef(
                      _currentChapter?.path,
                    ) ==
                    'mangadex') {
                  _chapterPagesCache.remove(_currentChapter!.path);
                  unawaited(_openChapter(_chapterIndex, initialPage: page));
                } else {
                  _precacheVisiblePages();
                }
              },
            ),
            IconButton(
              tooltip: 'Marcar capitulo leido',
              onPressed: chapter == null
                  ? null
                  : () async {
                      final reader = context.read<ChapterReadProvider>();
                      final wasRead = reader.isRead(chapter.path);
                      await MyAnimeListService.shared
                          .registerManga(widget.manga, chapters: [chapter])
                          .catchError((_) {});
                      if (!mounted) return;
                      await reader.toggle(chapter.path);
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            wasRead
                                ? 'Capitulo marcado como no leido'
                                : 'Capitulo marcado como leido',
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
              icon: const Icon(Icons.done_all_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomOverlay(ThemeData theme, ReaderSettingsProvider settings) {
    final totalPages = _currentPages.length;
    final progress = totalPages <= 1 ? 1.0 : _pageIndex / (totalPages - 1);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
              theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (totalPages > 1) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (value) {
                    final target = (value * (totalPages - 1)).round();
                    _animateToPage(target, settings);
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Capitulo anterior',
                  onPressed: _goPrevChapter,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: 'Pagina anterior',
                  onPressed: () => _goToRelativePage(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: settings.readingDirection.label,
                  onPressed: settings.toggleMode,
                  icon: Icon(
                    settings.verticalMode
                        ? Icons.swap_vert
                        : settings.isRightToLeft
                        ? Icons.format_textdirection_r_to_l
                        : Icons.format_textdirection_l_to_r,
                  ),
                ),
                IconButton(
                  tooltip: 'Capitulos',
                  onPressed: _openDrawer,
                  icon: const Icon(Icons.menu_book_outlined),
                ),
                IconButton(
                  tooltip: 'Pagina siguiente',
                  onPressed: () => _goToRelativePage(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                IconButton(
                  tooltip: 'Capitulo siguiente',
                  onPressed: _goNextChapter,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Este capitulo no tiene paginas disponibles.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Cargando capitulo...', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  void _markVisibleLoaded() {
    if (!mounted || _loadingChapter || _pages.isEmpty) return;
    final settings = context.read<ReaderSettingsProvider>();
    final count =
        _useDoublePage(settings) && !(settings.coverAlone && _pageIndex == 0)
        ? 2
        : 1;
    final visible = [
      for (var i = _pageIndex; i < _pageIndex + count && i < _pages.length; i++)
        i,
    ];
    for (final index in visible) {
      if (!_loadedPages.contains(_pages[index])) continue;
      final key = '${_currentChapter?.path ?? ''}:$index';
      if (_readPages.add(key)) {
        unawaited(context.read<LibraryProvider>().recordPageRead());
      }
    }
    if (_currentChapter?.complete == true &&
        visible.contains(_pages.length - 1) &&
        visible.every((i) => _loadedPages.contains(_pages[i]))) {
      final chapter = _currentChapter!;
      unawaited(
        context.read<ChapterReadProvider>().markRead(
          chapter.sourceUrl ?? chapter.path,
        ),
      );
    }
  }

  void _precacheVisiblePages() {
    if (!mounted || _pages.isEmpty) return;
    final chapter = _currentChapter?.path;
    if (_preloadRadius > 0) {
      _preloadRadius =
          PaintingBinding.instance.imageCache.currentSizeBytes >
                  32 * 1024 * 1024 ||
              ImageRepository.shared.latencyMs > 1500
          ? 0
          : ImageRepository.shared.latencyMs < 350
          ? 2
          : 1;
    }
    for (
      var index = (_pageIndex - 1).clamp(0, _pages.length - 1);
      index <= (_pageIndex + _preloadRadius).clamp(0, _pages.length - 1);
      index++
    ) {
      final path = _pages[index];
      if (_loadedPages.contains(path)) {
        _markVisibleLoaded();
        continue;
      }
      if (_streams.containsKey(path)) continue;
      final stream = _imageProviderForPath(
        path,
      ).resolve(createLocalImageConfiguration(context));
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, sync) {
          stream.removeListener(listener);
          _streams.remove(path);
          if (!mounted) {
            info.dispose();
            return;
          }
          _dimensions[path] = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          info.dispose();
          _loadedPages.add(path);
          if (chapter == _currentChapter?.path) {
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && chapter == _currentChapter?.path) {
                _markVisibleLoaded();
              }
            });
          }
        },
        onError: (Object error, StackTrace? stack) {
          stream.removeListener(listener);
          _streams.remove(path);
        },
      );
      _streams[path] = (stream: stream, listener: listener);
      stream.addListener(listener);
    }
  }

  ImageProvider _imageProviderForPath(String path) {
    final width =
        (MediaQuery.sizeOf(context).width *
                MediaQuery.devicePixelRatioOf(context))
            .round()
            .clamp(360, 1440);
    return boundedImage(
      path,
      width: width,
      original: _originalQuality,
      cropWhite: _settings?.cropWhite ?? false,
    );
  }

  Widget _buildChapterError(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 40),
          const SizedBox(height: 12),
          Text(_chapterError!, textAlign: TextAlign.center),
          TextButton(
            onPressed: () => unawaited(_alternatives()),
            child: const Text('Buscar capítulo en otra fuente'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar capítulo'),
            onPressed: () {
              final chapter = _currentChapter;
              if (chapter != null) _chapterPagesCache.remove(chapter.path);
              unawaited(_openChapter(_chapterIndex, initialPage: _pageIndex));
            },
          ),
          TextButton(
            onPressed: _goNextChapter,
            child: const Text('Siguiente capítulo'),
          ),
        ],
      ),
    ),
  );
  Future<void> _retryImage() async {
    if (_pages.isEmpty) return;
    final path = _pages[_pageIndex];
    try {
      await _imageProviderForPath(path).evict();
      if (ContentIdentity.isRemote(path)) {
        await ImageRepository.shared.resolve(
          path,
          headers: OnlineCatalogService.imageRequestHeaders(path),
          refresh: true,
        );
      }
      if (!mounted) return;
      _loadedPages.remove(path);
      setState(() {
        _imageError = false;
        _imageRevision++;
      });
      _precacheVisiblePages();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(NetworkErrors.friendly(error))));
      }
    }
  }

  Widget _buildImageError(ThemeData theme, Object error) {
    if (!_imageError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_imageError) {
          setState(() {
            _imageError = true;
            _showControls = true;
          });
        }
      });
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 46,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            const Text('No se pudo cargar la imagen.'),
            TextButton(
              onPressed: () => unawaited(_alternatives()),
              child: const Text('Buscar capítulo en otra fuente'),
            ),
            const SizedBox(height: 8),
            Text(NetworkErrors.friendly(error), textAlign: TextAlign.center),
            TextButton.icon(
              onPressed: () => unawaited(_retryImage()),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar imagen'),
            ),
            TextButton(
              onPressed: () => _goToRelativePage(1),
              child: const Text('Siguiente página'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _alternatives() async {
    final chapter = _currentChapter;
    if (chapter == null) return;
    final selected = await showModalBottomSheet<AlternativeChapter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: AlternativeChapterPicker(
          title: widget.manga.title,
          origin: _readingDetail.url,
          chapter: chapter,
        ),
      ),
    );
    if (selected == null || !mounted) return;
    _saveProgress();
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: selected.manga.toOfflineManga(),
          initialChapterIndex: selected.index,
          initialPageIndex: 0,
        ),
      ),
    );
  }

  Future<void> _bookmark() async {
    final chapter = _currentChapter;
    if (chapter == null || _pages.isEmpty) return;
    final added = await BookmarkService.toggle(
      manga: _readingDetail.url,
      title: widget.manga.title,
      chapter: chapter.sourceUrl ?? chapter.path,
      chapterTitle: chapter.title,
      page: _pageIndex,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added ? 'Marcador guardado' : 'Marcador eliminado'),
        ),
      );
    }
  }

  Future<void> _bookmarks() async {
    final rows = await BookmarkService.list(_readingDetail.url);
    if (!mounted) return;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (c) => SafeArea(
        child: rows.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No hay marcadores para esta obra.'),
              )
            : ListView(
                children: [
                  for (final row in rows)
                    ListTile(
                      title: Text(row['chapterTitle'] as String),
                      subtitle: Text('Página ${(row['page'] as int) + 1}'),
                      onTap: () => Navigator.pop(c, row),
                    ),
                ],
              ),
      ),
    );
    if (selected == null || !mounted) return;
    final index = _chapters.indexWhere(
      (c) =>
          c.path == selected['chapter'] || c.sourceUrl == selected['chapter'],
    );
    if (index >= 0) {
      await _openChapter(index, initialPage: selected['page'] as int);
      return;
    }
    try {
      final detail = await OnlineCatalogService.resolveChapter(
        _readingDetail,
        selected['chapter'] as String,
      );
      if (!mounted) return;
      setState(() => _readingDetail = detail);
      await _openChapter(
        detail.chapters.indexWhere((c) => c.path == selected['chapter']),
        initialPage: selected['page'] as int,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(NetworkErrors.friendly(e))));
      }
    }
  }
}
