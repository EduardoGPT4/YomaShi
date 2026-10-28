import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_queue_provider.dart';
import '../utils/title_sanitizer.dart';
import '../services/storage_metrics.dart';
import '../widgets/cached_thumbnail.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/section_header.dart';

class DownloadQueueScreen extends StatelessWidget {
  const DownloadQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DownloadQueueProvider>();
    final activeJobs = provider.jobs.where((job) {
      return job.status == DownloadJobStatus.queued ||
          job.status == DownloadJobStatus.downloading ||
          job.status == DownloadJobStatus.paused ||
          job.status == DownloadJobStatus.failed;
    }).toList();

    final archive = provider.archive;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Descargas'),
        automaticallyImplyLeading: false,
      ),
      body: CustomScrollView(
        key: const PageStorageKey('downloads'),
        slivers: [
          SliverPadding(
            padding: HomeContentLayout.paddingOf(context),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (provider.persistenceError != null)
                        Text(provider.persistenceError!),
                      SectionHeader(
                        icon: Icons.download_rounded,
                        title: 'Cola de descargas',
                        trailing: activeJobs.length.toString(),
                      ),
                      if (activeJobs.isEmpty)
                        _EmptyStateCard(
                          icon: Icons.cloud_download_outlined,
                          message: 'No hay descargas en proceso.',
                        ),
                      const SizedBox(height: 14),
                    ],
                  );
                }
                if (index <= activeJobs.length) {
                  final job = activeJobs[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      children: [
                        _ActiveJobCard(
                          job: job,
                          onPause: () => provider.pauseJob(job.id),
                          onResume: () => provider.resumeJob(job.id),
                          onStop: () => provider.stopJob(job.id),
                          onMoveUp: provider.canMoveUp(job.id)
                              ? () => provider.moveJobUp(job.id)
                              : null,
                          onMoveDown: provider.canMoveDown(job.id)
                              ? () => provider.moveJobDown(job.id)
                              : null,
                          onPrioritize:
                              job.status != DownloadJobStatus.downloading
                              ? () => provider.prioritizeJob(job.id)
                              : null,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.drive_file_move_outline),
                          label: const Text('Copiar a otro destino'),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await provider.chooseJobDestination(job.id);
                            } catch (error) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(error.toString())),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }
                if (index == activeJobs.length + 1) {
                  return Column(
                    children: [
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: SectionHeader(
                              icon: Icons.history_rounded,
                              title: 'Historial',
                              trailing: archive.length.toString(),
                            ),
                          ),
                          TextButton(
                            onPressed: archive.isEmpty
                                ? null
                                : provider.clearArchive,
                            child: const Text('Limpiar'),
                          ),
                        ],
                      ),
                      if (archive.isEmpty)
                        _EmptyStateCard(
                          icon: Icons.inventory_2_outlined,
                          message: 'Sin descargas archivadas.',
                        ),
                      const SizedBox(height: 14),
                    ],
                  );
                }
                final entry = archive[index - activeJobs.length - 2];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ArchiveCard(
                    entry: entry,
                    onRemove: () => provider.removeArchiveEntry(entry.id),
                  ),
                );
              }, childCount: activeJobs.length + archive.length + 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final DownloadJobStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, background) = switch (status) {
      DownloadJobStatus.queued => (
        'En cola',
        theme.colorScheme.onSurface.withAlpha(200),
        theme.colorScheme.onSurface.withAlpha(24),
      ),
      DownloadJobStatus.downloading => (
        'Descargando',
        theme.colorScheme.primary,
        theme.colorScheme.primary.withAlpha(36),
      ),
      DownloadJobStatus.paused => (
        'Pausada',
        const Color(0xFFF59E0B),
        const Color(0x33F59E0B),
      ),
      DownloadJobStatus.completed => (
        'Completada',
        const Color(0xFF34D399),
        const Color(0x3334D399),
      ),
      DownloadJobStatus.stopped => (
        'Detenida',
        theme.colorScheme.onSurface.withAlpha(170),
        theme.colorScheme.onSurface.withAlpha(20),
      ),
      DownloadJobStatus.failed => (
        'Error',
        theme.colorScheme.error,
        theme.colorScheme.error.withAlpha(36),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ActiveJobCard extends StatelessWidget {
  final DownloadJob job;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onPrioritize;

  const _ActiveJobCard({
    required this.job,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    this.onMoveUp,
    this.onMoveDown,
    this.onPrioritize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloading = job.status == DownloadJobStatus.downloading;
    final isPaused =
        job.status == DownloadJobStatus.paused ||
        job.status == DownloadJobStatus.failed;
    final title = TitleSanitizer.clean(job.manga.title);
    // Progreso por capítulos completados (30/100 → 30%).
    final progress = job.progress.clamp(0.0, 1.0);
    final progressPercent = (progress * 100).round();
    final hasChapterTotal = job.totalChapters > 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDownloading
              ? theme.colorScheme.primary.withAlpha(100)
              : theme.colorScheme.onSurface.withAlpha(18),
          width: isDownloading ? 1.5 : 1,
        ),
        boxShadow: isDownloading
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withAlpha(40),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(50),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 56,
                  height: 80,
                  child: CachedThumbnail(
                    sourcePath: job.manga.coverUrl,
                    size: 360,
                    fit: BoxFit.cover,
                    placeholderBuilder: (_) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.auto_stories_outlined,
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StatusBadge(status: job.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: hasChapterTotal ? progress : null,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.onSurface.withAlpha(20),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                job.etaLabel == null
                    ? (hasChapterTotal
                          ? '${job.completedChapters}/${job.totalChapters} · $progressPercent%'
                          : '$progressPercent%')
                    : '${job.completedChapters}/${job.totalChapters} · $progressPercent% · ${job.etaLabel}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _StatChip(
                icon: Icons.menu_book_outlined,
                label: 'Caps ${job.completedChapters}/${job.totalChapters}',
              ),
              _StatChip(
                icon: Icons.layers_outlined,
                label: 'Pags ${job.completedPages}/${job.totalPages}',
              ),
              _StatChip(
                icon: Icons.network_check,
                label:
                    '${StorageMetrics.format(job.receivedBytes)}${job.status == DownloadJobStatus.downloading ? ' · ${StorageMetrics.format(job.bytesPerSecond.round())}/s' : ''}${job.etaLabel == null ? '' : ' · ${job.etaLabel!}'}',
              ),
            ],
          ),
          if (job.currentChapter != null) ...[
            const SizedBox(height: 10),
            Text(
              'Actual: ${TitleSanitizer.clean(job.currentChapter!)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(180),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (job.error != null) ...[
            const SizedBox(height: 10),
            Text(
              job.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (onMoveUp != null ||
              onMoveDown != null ||
              onPrioritize != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Subir en la cola',
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Bajar en la cola',
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPrioritize,
                    icon: const Icon(
                      Icons.vertical_align_top_rounded,
                      size: 18,
                    ),
                    label: const Text('Priorizar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isPaused ? onResume : onPause,
                  icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 22,
                  ),
                  label: Text(isPaused ? 'Reanudar' : 'Pausar'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onStop,
                  icon: const Icon(Icons.stop_rounded, size: 22),
                  label: const Text('Cancelar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(
                      color: theme.colorScheme.error.withAlpha(120),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  final DownloadArchiveEntry entry;
  final VoidCallback onRemove;

  const _ArchiveCard({required this.entry, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = TitleSanitizer.clean(entry.title);
    final isCompleted = entry.reason.toLowerCase().contains('descarg');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 62,
              height: 88,
              child: CachedThumbnail(
                sourcePath: entry.coverUrl,
                size: 360,
                fit: BoxFit.cover,
                placeholderBuilder: (_) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.auto_stories_outlined,
                    color: theme.colorScheme.onSurface.withAlpha(100),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? const Color(0x3334D399)
                        : theme.colorScheme.onSurface.withAlpha(20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    entry.reason,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isCompleted
                          ? const Color(0xFF34D399)
                          : theme.colorScheme.onSurface.withAlpha(180),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${entry.completedChapters} caps · ${entry.completedPages}/${entry.totalPages} pags\n${entry.rangeLabel}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 20),
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: theme.colorScheme.onSurface.withAlpha(18),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyStateCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: theme.colorScheme.onSurface.withAlpha(100),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(170),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
