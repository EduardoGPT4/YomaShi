import 'package:path/path.dart' as p;
import '../providers/categories_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../providers/source_provider.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../providers/chapter_read_provider.dart';
import '../providers/download_queue_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../providers/profile_provider.dart';
import '../models/ui_density.dart';
import '../providers/density_provider.dart';
import '../providers/theme_accent_provider.dart';
import '../utils/archive_import.dart';
import '../utils/backup_service.dart';
import '../utils/permissions.dart';
import '../widgets/download_settings_panel.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/reader_settings_panel.dart';
import '../widgets/section_header.dart';
import '../widgets/profile_avatar.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'storage_screen.dart';
import 'automation_screen.dart';
import 'myanimelist_screen.dart';
import 'dart:convert';
import '../services/diagnostics.dart';
import '../utils/app_failure.dart';

/// Identidad del lector y toda la configuración de la app.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _editDisplayName() async {
    final profile = context.read<ProfileProvider>();
    if (profile.usesMyAnimeListIdentity) {
      return;
    }
    final controller = TextEditingController(text: profile.displayName);
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nombre de perfil'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Tu nombre',
              counterText: '',
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (next == null || !mounted) {
      return;
    }
    await profile.setDisplayName(next);
  }

  Future<void> _pickAvatar() async {
    final profile = context.read<ProfileProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path == null) {
        return;
      }
      await profile.setAvatarFromFile(path);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo usar la imagen: $error')),
      );
    }
  }

  Future<void> _pickFolder() async {
    final permission = await StoragePermissionService.request();
    if (!permission.granted) {
      if (permission.permanentlyDenied) {
        await openAppSettings();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permiso requerido para leer carpetas.'),
          ),
        );
      }
      return;
    }

    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecciona carpeta de mangas',
    );
    if (selected != null && mounted) {
      await context.read<LibraryProvider>().addLibraryPath(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Carpeta agregada a la biblioteca.')),
      );
    }
  }

  Future<void> _importArchive() async {
    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<LibraryProvider>();
    final downloader = context.read<DownloadQueueProvider>();

    try {
      var root = downloader.downloadFolderPath;
      if (root == null) {
        final ok = await downloader.chooseDownloadRoot();
        if (!ok) {
          return;
        }
        root = downloader.downloadFolderPath;
        if (root != null) {
          await library.addLibraryPath(root);
        }
      }
      if (root == null) {
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['cbz', 'zip'],
      );
      final path = result?.files.single.path;
      if (path == null) {
        return;
      }

      if (!mounted) return;
      final progress = ValueNotifier<double>(0);
      final cancellation = CancellationToken();
      var dialogOpen = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Importando archivo'),
              content: ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, value, child) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: value),
                    Text('${(value * 100).round()} %'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: cancellation.cancel,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ).then((_) {
          dialogOpen = false;
        }),
      );
      try {
        await ArchiveImport.importCbzOrZip(
          archiveFile: File(path),
          destinationRoot: root,
          onProgress: (value) {
            progress.value = value;
          },
          cancellation: cancellation,
        );
      } finally {
        if (mounted && dialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        progress.dispose();
      }
      await library.rescan();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Archivo importado a la biblioteca.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo importar: $error')),
      );
    }
  }

  Future<void> _exportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await BackupService.exportToFile();
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar backup',
        fileName: p.basename(file.path),
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: await file.readAsBytes(),
      );
      if (mounted && saved != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Backup guardado en $saved')),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $error')),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    final library = context.read<LibraryProvider>();
    final favorites = context.read<FavoritesProvider>();
    final chapters = context.read<ChapterReadProvider>();
    final categories = context.read<CategoriesProvider>();
    final reader = context.read<ReaderSettingsProvider>();
    final source = context.read<SourceProvider>();
    final accent = context.read<ThemeAccentProvider>();
    final density = context.read<DensityProvider>();
    final profile = context.read<ProfileProvider>();
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final preview = await BackupService.preview(File(path));
      if (!mounted) return;
      final merge = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restaurar backup'),
          content: Text(preview.summary),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Reemplazar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Combinar'),
            ),
          ],
        ),
      );
      if (merge == null) return;
      final message = await BackupService.importFromFile(
        File(path),
        merge: merge,
      );
      await Future.wait([
        library.load(),
        favorites.load(),
        chapters.load(),
        categories.load(),
        reader.load(),
        source.load(),
        accent.load(),
        density.load(),
        profile.load(),
      ]);
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo restaurar: $error')),
        );
      }
    }
  }

  Future<void> _exportDiagnostics() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final content = await Diagnostics.export();
      await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar diagnóstico',
        fileName: 'yomashi_diagnostics.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: utf8.encode(content),
      );
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _pickThemeAccent() async {
    final accent = context.read<ThemeAccentProvider>();
    const accents = <Color>[
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF059669),
      Color(0xFFDC2626),
      Color(0xFFEA580C),
      Color(0xFFDB2777),
    ];
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Color de acento'),
          content: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: accents
                .map(
                  (color) => GestureDetector(
                    onTap: () => Navigator.of(context).pop(color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const Color(0xFF7C3AED)),
              child: const Text('Restablecer'),
            ),
          ],
        );
      },
    );
    if (selected == null) {
      return;
    }
    await accent.setAccent(selected);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Color de acento aplicado.')));
  }

  void _showAboutDialog(ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          title: const Text('Acerca de'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YomaShi',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text('Versión ${HomeContentLayout.appVersion}'),
                const SizedBox(height: 10),
                Text(
                  'Lector de manga offline y online.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Novedades 2.4.1',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '• Foto del perfil sincronizada con MyAnimeList.\n'
                  '• Descargas resumidas, progreso claro y detalles desplegables.\n'
                  '• Perfil organizado y conexión de MyAnimeList más sencilla.\n'
                  '• Ajustes desde el lector y búsqueda de capítulos.\n'
                  '• Mejor contraste y controles más fáciles de tocar.\n'
                  '• La búsqueda y los filtros se conservan entre pestañas.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = context.watch<ProfileProvider>();
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: HomeContentLayout.paddingOf(context),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.onSurface.withAlpha(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: profile.myAnimeListAvatarUrl != null
                      ? null
                      : () => unawaited(_pickAvatar()),
                  onLongPress:
                      profile.myAnimeListAvatarUrl == null && profile.hasAvatar
                      ? () => unawaited(profile.clearAvatar())
                      : null,
                  child: Stack(
                    children: [
                      Tooltip(
                        message: profile.myAnimeListAvatarUrl == null
                            ? 'Editar foto local'
                            : 'Foto sincronizada con MyAnimeList',
                        child: ProfileAvatar(profile: profile),
                      ),
                      if (profile.myAnimeListAvatarUrl == null)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 12,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.usesMyAnimeListIdentity
                            ? 'Nombre de MyAnimeList'
                            : 'Nombre',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(150),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: profile.usesMyAnimeListIdentity
                            ? null
                            : () => unawaited(_editDisplayName()),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                profile.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (!profile.usesMyAnimeListIdentity) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.edit_rounded,
                                size: 18,
                                color: theme.colorScheme.onSurface.withAlpha(
                                  140,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (profile.usesMyAnimeListIdentity) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${profile.myAnimeListUsername} · MyAnimeList',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(170),
                          ),
                        ),
                      ],
                      if (!profile.usesMyAnimeListIdentity) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Toca la foto o el nombre para editarlos.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(170),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: HomeContentLayout.sectionSpacing),
          _SettingsCard(
            title: 'Cuenta',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync_alt),
                title: const Text('MyAnimeList · Manga'),
                subtitle: Text(
                  profile.usesMyAnimeListIdentity
                      ? 'Cuenta conectada · Sincronizar lectura'
                      : 'Conectar tu cuenta y sincronizar lectura',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MyAnimeListScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SectionHeader(icon: Icons.download_rounded, title: 'Descargas'),
          const SizedBox(height: 10),
          const DownloadSettingsPanel(),
          const SizedBox(height: 14),
          _SettingsCard(
            title: 'Biblioteca',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: library.autoRescanEnabled,
                onChanged: library.setAutoRescanEnabled,
                title: const Text('Detectar cambios automáticos'),
                subtitle: const Text('Vigila la carpeta y actualiza la lista.'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => unawaited(_pickFolder()),
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Agregar carpeta'),
                trailing: const Icon(Icons.chevron_right),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => unawaited(_importArchive()),
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Importar CBZ/ZIP'),
                trailing: const Icon(Icons.chevron_right),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                },
                leading: const Icon(Icons.history_rounded),
                title: const Text('Historial'),
                trailing: const Icon(Icons.chevron_right),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StatsScreen()),
                  );
                },
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('Estadísticas'),
                trailing: const Icon(Icons.chevron_right),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Automatización y copias'),
                subtitle: const Text('Novedades y lectura sin conexión'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AutomationScreen()),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage),
                title: const Text('Almacenamiento'),
                subtitle: const Text('Espacio, caché y capítulos descargados'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StorageScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: 'Apariencia',
            children: [
              const ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.view_compact_alt_outlined, size: 20),
                title: Text('Densidad'),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in UiDensity.values)
                    ChoiceChip(
                      label: Text(
                        option == UiDensity.compact ? 'Compacta' : 'Cómoda',
                      ),
                      selected:
                          context.watch<DensityProvider>().density == option,
                      onSelected: (_) => unawaited(
                        context.read<DensityProvider>().setDensity(option),
                      ),
                    ),
                ],
              ),
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined, size: 20),
                title: const Text('Color de acento'),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => unawaited(_pickThemeAccent()),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: 'Lector',
            children: const [ReaderSettingsPanel()],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            title: 'Ajustes avanzados',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Exportar copia de seguridad'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_exportBackup()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Importar copia de seguridad'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_importBackup()),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Exportar diagnóstico'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(_exportDiagnostics()),
              ),
            ],
          ),
          const SizedBox(height: 24),
          InkWell(
            onTap: () => _showAboutDialog(theme),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withAlpha(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Acerca de', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          'Versión ${HomeContentLayout.appVersion}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurface.withAlpha(128),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black.withAlpha(80),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(170),
                letterSpacing: 0.6,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
