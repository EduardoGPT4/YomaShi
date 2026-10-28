import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/automation_settings.dart';
import '../data/library_store.dart';
import '../providers/download_queue_provider.dart';
import '../providers/library_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../providers/source_provider.dart';
import '../providers/theme_accent_provider.dart';
import '../providers/density_provider.dart';
import '../providers/profile_provider.dart';
import '../services/maintenance_service.dart';
import '../services/rotating_backup_service.dart';
import '../utils/backup_service.dart';

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({super.key});
  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  AutomationSettings? _settings;
  List<File> _copies = [];
  List<Map<String, dynamic>> _updates = [];
  String? _error;
  String _backupPath = '';
  bool _busy = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final settings = await AutomationSettings.load();
      final copies = await RotatingBackupService.files();
      final backupPath = (await RotatingBackupService.directory()).path;
      final updates = await (await LibraryStore.ensureInitialized())
          .readRecords('favorite_updates');
      if (mounted) {
        setState(() {
          _settings = settings;
          _copies = copies;
          _backupPath = backupPath;
          _updates = updates;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(String key, Object value) => _run(() async {
    final next = AutomationSettings.fromMap({
      ..._settings!.toMap(),
      key: value,
    });
    await next.save();
    await MaintenancePlatform.schedule(next);
  });
  Future<void> _restore(File copy) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: const Text(
          'Se combinarán el progreso, favoritos, marcadores y ajustes con esta copia. Se conservará una copia previa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final library = context.read<LibraryProvider>(),
        source = context.read<SourceProvider>(),
        accent = context.read<ThemeAccentProvider>(),
        density = context.read<DensityProvider>(),
        profile = context.read<ProfileProvider>(),
        favorites = context.read<FavoritesProvider>(),
        reads = context.read<ChapterReadProvider>(),
        categories = context.read<CategoriesProvider>(),
        settings = context.read<ReaderSettingsProvider>();
    await _run(() async {
      await BackupService.importFromFile(copy, merge: true);
      await library.load();
      await favorites.load();
      await reads.load();
      await categories.load();
      await settings.load();
      await source.load();
      await accent.load();
      await density.load();
      await profile.load();
      await MaintenancePlatform.schedule(await AutomationSettings.load());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Automatización y copias')),
      body: s == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                const Text(
                  'Favoritos y lectura sin conexión',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  title: const Text('Buscar capítulos nuevos'),
                  subtitle: const Text(
                    'Comprobación periódica; Android decide el momento de ejecución.',
                  ),
                  value: s.updates,
                  onChanged: _busy ? null : (v) => _change('updates', v),
                ),
                SwitchListTile(
                  title: const Text('Descargar novedades de favoritos'),
                  subtitle: const Text(
                    'Solo novedades posteriores a la primera comprobación.',
                  ),
                  value: s.autoDownload,
                  onChanged: _busy ? null : (v) => _change('autoDownload', v),
                ),
                SwitchListTile(
                  title: const Text('Solo Wi-Fi para tareas automáticas'),
                  value: s.wifiOnly,
                  onChanged: _busy ? null : (v) => _change('wifiOnly', v),
                ),
                SwitchListTile(
                  title: const Text('Solo mientras carga'),
                  value: s.chargingOnly,
                  onChanged: _busy ? null : (v) => _change('chargingOnly', v),
                ),
                ListTile(
                  title: const Text('Batería mínima'),
                  trailing: DropdownButton<int>(
                    value: s.batteryMinimum,
                    items: {10, 20, 30, 50, s.batteryMinimum}
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text('$n%')),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) => _change('batteryMinimum', v!),
                  ),
                ),
                ListTile(
                  title: const Text('Preparar siguientes capítulos'),
                  subtitle: const Text(
                    'Se preparan al abrir un capítulo. No se borran descargas existentes.',
                  ),
                  trailing: DropdownButton<int>(
                    value: s.aheadCount,
                    items: {0, 1, 3, 5, 10, s.aheadCount}
                        .map(
                          (n) => DropdownMenuItem(
                            value: n,
                            child: Text(n == 0 ? 'Desactivado' : '$n'),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : (v) => _change('aheadCount', v!),
                  ),
                ),
                ListTile(
                  title: const Text('Espacio para descargas automáticas'),
                  trailing: DropdownButton<int>(
                    value: s.budgetMiB,
                    items: {32, 128, 256, 512, 1024, 2048, s.budgetMiB}
                        .map(
                          (n) =>
                              DropdownMenuItem(value: n, child: Text('$n MiB')),
                        )
                        .toList(),
                    onChanged: _busy ? null : (v) => _change('budgetMiB', v!),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => context
                              .read<DownloadQueueProvider>()
                              .runMaintenance(manual: true),
                        ),
                  icon: const Icon(Icons.update),
                  label: const Text('Comprobar favoritos ahora'),
                ),
                for (final update in _updates)
                  ListTile(
                    title: Text(update['title'] as String? ?? ''),
                    subtitle: Text(
                      '${(update['new'] as List? ?? []).length} novedades · Última comprobación: ${DateTime.fromMillisecondsSinceEpoch(update['checkedAt'] as int? ?? 0).toLocal()}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Marcar novedades vistas',
                      icon: const Icon(Icons.done),
                      onPressed: () => _run(() async {
                        await (await LibraryStore.ensureInitialized())
                            .putRecord(
                              'favorite_updates',
                              update['id'] as String,
                              {...update, 'new': []},
                            );
                      }),
                    ),
                  ),
                const Divider(),
                const Text(
                  'Copias de seguridad',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SwitchListTile(
                  title: const Text('Copias automáticas diarias'),
                  subtitle: const Text(
                    'Progreso, favoritos, marcadores y ajustes. No incluye las imágenes.',
                  ),
                  value: s.backups,
                  onChanged: _busy ? null : (v) => _change('backups', v),
                ),
                ListTile(
                  title: const Text('Copias conservadas'),
                  trailing: DropdownButton<int>(
                    value: s.backupRetention,
                    items: {2, 7, 14, 30, s.backupRetention}
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text('$n')),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) => _change('backupRetention', v!),
                  ),
                ),
                Text('Carpeta de copias: $_backupPath'),
                if (!_backupPath.contains('/YomaShi/Backups'))
                  const Text(
                    'Esta carpeta privada se elimina al desinstalar. Exporta una copia para conservarla fuera de la app.',
                  ),
                Text(
                  _copies.isEmpty
                      ? 'Todavía no hay copias automáticas.'
                      : 'Última copia: ${DateTime.fromMicrosecondsSinceEpoch(int.tryParse(_copies.first.uri.pathSegments.last.replaceAll(RegExp(r'\D'), '')) ?? 0).toLocal()}',
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await RotatingBackupService.run(
                            force: true,
                            retain: s.backupRetention,
                          );
                        }),
                  icon: const Icon(Icons.save),
                  label: const Text('Crear copia ahora'),
                ),
                for (final copy in _copies)
                  ListTile(
                    title: Text(copy.uri.pathSegments.last),
                    onTap: _busy ? null : () => _restore(copy),
                    trailing: IconButton(
                      tooltip: 'Exportar copia',
                      icon: const Icon(Icons.save_alt),
                      onPressed: () => _run(() async {
                        await FilePicker.platform.saveFile(
                          dialogTitle: 'Exportar copia',
                          fileName: copy.uri.pathSegments.last,
                          bytes: await copy.readAsBytes(),
                        );
                      }),
                    ),
                  ),
              ],
            ),
    );
  }
}
