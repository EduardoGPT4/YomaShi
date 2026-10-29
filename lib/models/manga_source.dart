import 'package:flutter/material.dart';

/// Tipo de integración de una fuente de manga.
enum MangaSourceKind { api, scraping }

/// Fuente modular de catálogo online (scraping o API).
class MangaSource {
  final String id;
  final String name;
  final String subtitle;
  final MangaSourceKind kind;
  final String languageLabel;
  final bool implemented;
  final IconData icon;

  const MangaSource({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.kind,
    required this.languageLabel,
    required this.implemented,
    required this.icon,
  });

  String get kindLabel => switch (kind) {
    MangaSourceKind.api => 'API oficial',
    MangaSourceKind.scraping => 'Scraping',
  };

  String get detailLine => languageLabel;
}

/// Catálogo de fuentes conocidas por la app (v2.0).
class MangaSources {
  static const String defaultId = 'lectortmo';

  static const List<MangaSource> all = <MangaSource>[
    MangaSource(
      id: 'mangadex',
      name: 'MangaDex',
      subtitle: 'Catálogo global con API oficial',
      kind: MangaSourceKind.api,
      languageLabel: 'Español (España / Latino)',
      implemented: true,
      icon: Icons.menu_book_rounded,
    ),
    MangaSource(
      id: 'inmanga',
      name: 'InManga',
      subtitle: 'Catálogo en español (inmanga.com)',
      kind: MangaSourceKind.scraping,
      languageLabel: 'Español',
      implemented: true,
      icon: Icons.language_rounded,
    ),
    MangaSource(
      id: 'lectortmo',
      name: 'TuMangaOnline / Lectortmo',
      subtitle: 'Catálogo en español (zonatmo.org)',
      kind: MangaSourceKind.scraping,
      languageLabel: 'Español',
      implemented: true,
      icon: Icons.public_rounded,
    ),
    MangaSource(
      id: 'zonatmo_to',
      name: 'ZonaTMO',
      subtitle: 'Catálogo en español (zonatmo.to)',
      kind: MangaSourceKind.scraping,
      languageLabel: 'Español',
      implemented: true,
      icon: Icons.language_rounded,
    ),
    MangaSource(
      id: 'manhwaweb',
      name: 'ManhwaWeb',
      subtitle: 'Catálogo en español (manhwaweb.com)',
      kind: MangaSourceKind.scraping,
      languageLabel: 'Español',
      implemented: true,
      icon: Icons.travel_explore_rounded,
    ),
  ];

  static String shortLabel(String id) {
    switch (id) {
      case 'lectortmo':
      case 'tmo':
        return 'TMO';
      case 'zonatmo_to':
        return 'ZonaTMO';
      case 'mangadex':
        return 'MangaDex';
      case 'inmanga':
        return 'InManga';
      case 'manhwaweb':
      case 'yupmanga':
        return 'ManhwaWeb';
      default:
        return id;
    }
  }

  static MangaSource byId(String id) {
    final normalized = id == 'yupmanga' ? 'manhwaweb' : id;
    for (final source in all) {
      if (source.id == normalized) {
        return source;
      }
    }
    return all.firstWhere((s) => s.id == defaultId);
  }
}
