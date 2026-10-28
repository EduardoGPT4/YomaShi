import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/preferences.dart';

/// Perfil local: nombre y foto (sin cuenta remota).
class ProfileProvider extends ChangeNotifier {
  static const defaultDisplayName = 'Lector';

  String _displayName = defaultDisplayName;
  String? _avatarPath;
  bool _loaded = false;

  String get displayName => _displayName;
  String? get avatarPath => _avatarPath;
  bool get isLoaded => _loaded;

  bool get hasAvatar {
    final path = _avatarPath;
    if (path == null || path.isEmpty) {
      return false;
    }
    return File(path).existsSync();
  }

  Future<void> load() async {
    final name = await PreferencesService.getProfileDisplayName();
    final avatar = await PreferencesService.getProfileAvatarPath();
    _displayName = (name == null || name.trim().isEmpty)
        ? defaultDisplayName
        : name.trim();
    _avatarPath = avatar;
    if (_avatarPath != null && !File(_avatarPath!).existsSync()) {
      _avatarPath = null;
      await PreferencesService.setProfileAvatarPath(null);
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setDisplayName(String name) async {
    final cleaned = name.trim();
    final next = cleaned.isEmpty ? defaultDisplayName : cleaned;
    if (next == _displayName) {
      return;
    }
    _displayName = next;
    notifyListeners();
    await PreferencesService.setProfileDisplayName(
      next == defaultDisplayName ? null : next,
    );
  }

  /// Copia la imagen elegida a almacenamiento de la app y la guarda.
  Future<void> setAvatarFromFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      return;
    }

    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'profile'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ext = p.extension(sourcePath).toLowerCase();
    final safeExt =
        (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.webp')
        ? ext
        : '.jpg';
    final target = File(p.join(dir.path, 'avatar$safeExt'));
    await source.copy(target.path);

    // Limpia avatar anterior con otra extensión.
    if (_avatarPath != null &&
        _avatarPath != target.path &&
        File(_avatarPath!).existsSync()) {
      try {
        await File(_avatarPath!).delete();
      } catch (_) {}
    }

    _avatarPath = target.path;
    notifyListeners();
    await PreferencesService.setProfileAvatarPath(target.path);
  }

  Future<void> clearAvatar() async {
    if (_avatarPath != null) {
      try {
        final file = File(_avatarPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    _avatarPath = null;
    notifyListeners();
    await PreferencesService.setProfileAvatarPath(null);
  }
}
