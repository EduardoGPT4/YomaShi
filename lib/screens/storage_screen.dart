import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/library_provider.dart';
import '../providers/download_queue_provider.dart';
import '../services/image_repository.dart';
import '../services/storage_maintenance.dart';
import '../services/storage_metrics.dart';
import '../utils/thumbnail_service.dart';
import '../services/repair_service.dart';
import '../services/reader_crop_service.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, int> _sizes = {};
  int _cache = 0, _thumbnails = 0;
  int? _free;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final library = context.read<LibraryProvider>();
    final root = context.read<DownloadQueueProvider>().downloadRoot;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final sizes = await StorageMaintenance.measure(library.mangas);
      final cache = await ImageRepository.shared.cacheSize();
      final thumbnails = await ThumbnailService.cacheSize();
      final free = root == null ? null : await StorageMetrics.freeBytes(root);
      if (mounted) {
        setState(() {
          _sizes = sizes;
          _cache = cache;
          _thumbnails = thumbnails;
          _free = free;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) await _refresh();
    }
  }

  Future<void> _delete(Manga manga, String path) async {
    final downloader = context.read<DownloadQueueProvider>();
    final library = context.read<LibraryProvider>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar capítulo'),
        content: const Text(
          'Se pausarán las descargas de esta obra y se eliminarán los archivos del capítulo. El historial de lectura se conserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      await downloader.pauseForManga(manga.sourceUrl ?? manga.path);
      await StorageMaintenance.deleteChapter(manga, path);
      await library.refreshMangaFolder(manga.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mangas = context.select<LibraryProvider, List<Manga>>(
      (p) => p.mangas,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Almacenamiento')),
      body: ListView.builder(
        itemCount: mangas.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  Text(
                    'Biblioteca: ${StorageMetrics.format(_sizes.values.fold(0, (a, b) => a + b))}',
                  ),
                  if (_free != null)
                    Text('Espacio libre: ${StorageMetrics.format(_free!)}'),
                  Text('Imágenes temporales: ${StorageMetrics.format(_cache)}'),
                  Text('Miniaturas: ${StorageMetrics.format(_thumbnails)}'),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await ImageRepository.shared.trim(clear: true);
                                await ThumbnailService.clearCache();
                                final crops =
                                    await ReaderCropService.directory();
                                if (await crops.exists()) {
                                  await crops.delete(recursive: true);
                                }
                                PaintingBinding.instance.imageCache.clear();
                              }),
                        child: const Text('Limpiar caché'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await StorageMaintenance.cleanParts(
                                  context.read<LibraryProvider>().libraryPaths,
                                );
                              }),
                        child: const Text('Limpiar parciales antiguos'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                final library = context.read<LibraryProvider>();
                                await StorageMaintenance.migrateLegacy(
                                  library.mangas,
                                );
                                await library.rescan();
                              }),
                        child: const Text('Actualizar biblioteca antigua'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          final manga = mangas[index - 1];
          return ExpansionTile(
            title: Text(manga.title),
            subtitle: Text(StorageMetrics.format(_sizes[manga.path] ?? 0)),
            children: [
              ListTile(
                leading: const Icon(Icons.healing),
                title: const Text('Revisar y reparar descarga'),
                subtitle: const Text(
                  'Conserva las páginas válidas y recupera solo las ausentes o dañadas.',
                ),
                onTap: _busy
                    ? null
                    : () => _run(() async {
                        final queue = context.read<DownloadQueueProvider>();
                        final report = await RepairService.inspect(manga.path);
                        if (!context.mounted) return;
                        if (report.damaged.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${report.checkedPages} páginas verificadas. No hay daños.',
                              ),
                            ),
                          );
                          return;
                        }
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Reparar descarga'),
                            content: Text(
                              '${report.missingPages} páginas ausentes o dañadas en ${report.damaged.length} capítulos. Se conservarán las páginas válidas y el progreso.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Reparar'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true) await queue.repair(manga.path);
                      }),
              ),
              for (final chapter in manga.chapters)
                ListTile(
                  title: Text(chapter.title),
                  subtitle: Text(chapter.complete ? 'Completo' : 'Parcial'),
                  trailing: IconButton(
                    tooltip: 'Eliminar capítulo',
                    onPressed: _busy
                        ? null
                        : () => _delete(manga, chapter.path),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
