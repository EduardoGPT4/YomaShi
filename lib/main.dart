import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/categories_provider.dart';
import 'providers/chapter_read_provider.dart';
import 'providers/download_queue_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/library_provider.dart';
import 'providers/reader_settings_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/source_provider.dart';
import 'providers/density_provider.dart';
import 'providers/theme_accent_provider.dart';
import 'data/library_store.dart';
import 'models/automation_settings.dart';
import 'services/maintenance_service.dart';
import 'services/rotating_backup_service.dart';
import 'services/diagnostics.dart';
import 'services/myanimelist_service.dart';
import 'screens/main_shell.dart';
import 'services/download_notification_service.dart';
import 'services/background_downloads.dart';
import 'models/ui_density.dart';
import 'widgets/app_metrics.dart';
import 'widgets/onboarding_flow.dart';
import 'widgets/startup_storage.dart';

@pragma('vm:entry-point')
Future<void> downloadMain() => runDownloadHost();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LibraryStore.initialize();
  } catch (error, stackTrace) {
    debugPrint('LibraryStore.initialize failed: $error\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No se pudo abrir la biblioteca. Tus archivos se conservan.',
                  ),
                  const SizedBox(height: 12),
                  Text(error.toString()),
                  FilledButton(
                    onPressed: main,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  // Las notificaciones no deben bloquear el arranque de la UI.
  try {
    await DownloadNotificationService.init();
  } catch (error, stackTrace) {
    debugPrint('DownloadNotificationService.init failed: $error\n$stackTrace');
  }
  runApp(const MangaReaderApp());
  unawaited(_prepareMaintenance());
}

Future<void> _prepareMaintenance() async {
  try {
    final settings = await AutomationSettings.load();
    await MaintenancePlatform.schedule(settings);
    if (settings.backups) {
      await RotatingBackupService.run(retain: settings.backupRetention);
    }
  } catch (e) {
    await Diagnostics.record('automatic_backup', e);
  }
}

class MangaReaderApp extends StatelessWidget {
  const MangaReaderApp({super.key});

  /// Clave del Navigator de [MaterialApp]. Necesaria para diálogos globales
  /// (onboarding) que no pueden usar el context de un ancestro de MaterialApp.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeAccentProvider()..load()),
        ChangeNotifierProvider(create: (_) => DensityProvider()..load()),
        ChangeNotifierProvider(create: (_) => SourceProvider()..load()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()..load()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()..load()),
        ChangeNotifierProvider(create: (_) => DownloadQueueProvider()..load()),
        ChangeNotifierProvider(create: (_) => ReaderSettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()..load()),
        ChangeNotifierProvider(create: (_) => ChapterReadProvider()..load()),
      ],
      child: Consumer2<ThemeAccentProvider, DensityProvider>(
        builder: (context, accent, density, _) {
          final theme = _buildTheme(
            accent.primary,
            density.density == UiDensity.comfortable
                ? AppMetrics.comfortable
                : AppMetrics.compact,
          );
          return _AppLifecycleHost(
            theme: theme,
            colorScheme: theme.colorScheme,
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme(Color primary, AppMetrics metrics) {
  const background = Color(0xFF090909);
  const surface = Color(0xFF151515);
  const surfaceVariant = Color(0xFF202020);
  const surfaceSoft = Color(0xFF2A2A2A);
  const secondary = Color(0xFFC7C7C7);
  const tertiary = Color(0xFF9A9A9A);
  const outline = Color(0xFF343434);
  const inverseSurface = Color(0xFFF1F1F1);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ).copyWith(
        surface: surface,
        onSurface: Colors.white,
        surfaceContainerHighest: surfaceVariant,
        onSurfaceVariant: const Color(0xFFD0D0D0),
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: surfaceSoft,
        onPrimaryContainer: Colors.white,
        secondary: secondary,
        onSecondary: Colors.black,
        secondaryContainer: surfaceSoft,
        onSecondaryContainer: Colors.white,
        tertiary: tertiary,
        onTertiary: Colors.black,
        tertiaryContainer: surfaceSoft,
        onTertiaryContainer: Colors.white,
        error: const Color(0xFFD4A3A3),
        onError: Colors.black,
        errorContainer: const Color(0xFF2A1F1F),
        onErrorContainer: Colors.white,
        outline: outline,
        outlineVariant: const Color(0xFF2B2B2B),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: inverseSurface,
        onInverseSurface: Colors.black,
        inversePrimary: const Color(0xFF777777),
        surfaceTint: primary,
      );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    colorScheme: colorScheme,
    visualDensity: metrics.isCompact
        ? VisualDensity.compact
        : VisualDensity.standard,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: metrics.isCompact ? 48 : 56,
      titleTextStyle: TextStyle(
        fontSize: metrics.isCompact ? 18 : 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.secondary,
      foregroundColor: colorScheme.onSecondary,
      elevation: 4,
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,
      padding: EdgeInsets.symmetric(horizontal: metrics.isCompact ? 6 : 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: metrics.isCompact ? 12 : 13,
      ),
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surfaceSoft,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: metrics.navHeight,
      indicatorColor: colorScheme.primary.withAlpha(40),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: metrics.navLabelSize,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.1,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: metrics.navIconSize,
          color: selected
              ? colorScheme.primary
              : colorScheme.onSurface.withAlpha(170),
        );
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.onSurface.withAlpha(24),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.onSurface.withAlpha(18),
      space: 1,
    ),
  );
}

class _AppLifecycleHost extends StatefulWidget {
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _AppLifecycleHost({required this.theme, required this.colorScheme});

  @override
  State<_AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends State<_AppLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Debe usarse el context del Navigator de MaterialApp, no el de este
      // State (que es ancestro de MaterialApp y no tiene Navigator).
      final navContext = MangaReaderApp.navigatorKey.currentContext;
      if (navContext == null) {
        return;
      }
      unawaited(_startFirstLaunch(navContext));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _startFirstLaunch(BuildContext navContext) async {
    await StartupStorage.runFirstLaunch(navContext);
    if (!navContext.mounted) {
      return;
    }
    await OnboardingFlow.showIfNeeded(navContext);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final downloader = context.read<DownloadQueueProvider>();
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(MyAnimeListService.shared.flush().catchError((_) {}));
        unawaited(StartupStorage.ensureFolderAndDefaults(context));
        unawaited(downloader.checkForRetryableJobs());
        unawaited(_prepareMaintenance());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YomaShi',
      navigatorKey: MangaReaderApp.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: widget.theme,
      builder: (context, child) {
        return Stack(
          children: [
            const _AppBackdrop(),
            child ?? const SizedBox.shrink(),
            Consumer<ReaderSettingsProvider>(
              builder: (context, settings, child) {
                final opacity = settings.dimOpacity;
                if (opacity <= 0.0) {
                  return const SizedBox.shrink();
                }
                return IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 180),
                    child: Container(color: widget.colorScheme.scrim),
                  ),
                );
              },
            ),
          ],
        );
      },
      home: const MainShell(),
    );
  }
}

class _AppBackdrop extends StatelessWidget {
  const _AppBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111111), Color(0xFF090909)],
          ),
        ),
      ),
    );
  }
}
