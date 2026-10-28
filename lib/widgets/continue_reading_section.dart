import 'package:flutter/material.dart';

import '../utils/title_sanitizer.dart';
import 'app_metrics.dart';
import 'cached_thumbnail.dart';
import 'section_header.dart';

class ContinueReadingEntry {
  final String title;
  final String chapterLabel;
  final int pageNumber;
  final double progress;
  final String? timeAgo;
  final String? coverPath;
  final VoidCallback onTap;

  const ContinueReadingEntry({
    required this.title,
    required this.chapterLabel,
    required this.pageNumber,
    required this.progress,
    required this.coverPath,
    required this.onTap,
    this.timeAgo,
  });
}

class ContinueReadingSection extends StatelessWidget {
  final List<ContinueReadingEntry> entries;

  const ContinueReadingSection({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final metrics = AppMetrics.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          icon: Icons.play_circle_outline_rounded,
          title: 'Continuar leyendo',
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: metrics.continueHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              return _ContinueCard(entry: entries[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final ContinueReadingEntry entry;

  const _ContinueCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = AppMetrics.of(context);
    final title = TitleSanitizer.clean(entry.title);
    final progress = entry.progress.clamp(0.0, 1.0);
    final progressLabel = '${entry.chapterLabel} · Pág. ${entry.pageNumber}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: metrics.continueWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.onSurface.withAlpha(18),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(11),
                ),
                child: SizedBox(
                  width: metrics.continueCover,
                  height: metrics.continueHeight,
                  child: CachedThumbnail(
                    sourcePath: entry.coverPath,
                    size: 180,
                    fit: BoxFit.cover,
                    placeholderBuilder: (_) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.auto_stories_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurface.withAlpha(80),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: metrics.titleSize,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress <= 0 ? null : progress,
                          minHeight: 3,
                          backgroundColor: theme.colorScheme.onSurface
                              .withAlpha(24),
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
