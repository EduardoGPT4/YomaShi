import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/profile_screen.dart';
import 'myanimelist_test.dart' show FakeMal, MemoryCredential;

class OfflineProfileMal extends FakeMal {
  OfflineProfileMal(super.store);
  bool offline = false;
  @override
  Future<Map<String, dynamic>?> account() async {
    if (offline) throw const SocketException('Offline fixture');
    return credentials.load();
  }
}

class DelayedProfileCredential extends MemoryCredential {
  Future<Map<String, dynamic>?>? nextLoad;
  @override
  Future<Map<String, dynamic>?> load() {
    final pending = nextLoad;
    nextLoad = null;
    return pending ?? super.load();
  }
}

class ProfileTestLibrary extends LibraryProvider {
  @override
  Future<void> flushStats() async {}
}

Map<String, dynamic> connectedIdentity(int id, String name) => {
  'device_token': 'a' * 64,
  'connected': true,
  'profile': {'id': id, 'name': name},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DelayedProfileCredential credential;
  late OfflineProfileMal client;
  late ProfileProvider profile;
  var disposed = false;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'profile_display_name_v1': 'Local reader',
    });
    credential = DelayedProfileCredential();
    client = OfflineProfileMal(credential);
    profile = ProfileProvider(malClient: client);
    disposed = false;
  });
  tearDown(() {
    if (!disposed) profile.dispose();
    client.sessionChanges.dispose();
    client.http.close(force: true);
  });

  test(
    'cached MAL account supplies the visible name and username on load',
    () async {
      credential.value = connectedIdentity(7, '  MangaTester  ');
      await profile.load();
      expect(profile.isLoaded, isTrue);
      expect(profile.usesMyAnimeListIdentity, isTrue);
      expect(profile.displayName, 'MangaTester');
      expect(profile.myAnimeListUsername, 'MangaTester');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'profile_display_name_v1',
        ),
        'Local reader',
      );
    },
  );

  test(
    'pending and malformed accounts use the retained local identity',
    () async {
      credential.value = null;
      await profile.load();
      await profile.refreshMyAnimeList();
      for (final value in <Map<String, dynamic>>[
        {
          'connected': false,
          'profile': {'id': 7, 'name': 'Pending'},
        },
        {'connected': true, 'profile': 'invalid'},
        {
          'connected': true,
          'profile': {'id': 0, 'name': 'Invalid'},
        },
        {
          'connected': true,
          'profile': {'id': '7', 'name': 'Invalid'},
        },
        {
          'connected': true,
          'profile': {'id': 7, 'name': '  '},
        },
        {
          'connected': true,
          'profile': {'id': 7, 'name': 42},
        },
      ]) {
        credential.value = value;
        await profile.reloadMyAnimeListIdentity();
        expect(profile.displayName, 'Local reader');
        expect(profile.myAnimeListUsername, isNull);
        expect(profile.usesMyAnimeListIdentity, isFalse);
      }
    },
  );

  test('offline status refresh preserves the cached MAL name', () async {
    await profile.load();
    client.offline = true;
    await profile.refreshMyAnimeList();
    expect(profile.displayName, 'MangaTester');
    expect(profile.myAnimeListUsername, 'MangaTester');
    expect(credential.value, isNotNull);
  });

  test(
    'committed disconnect restores the local name without replacing preferences',
    () async {
      await profile.load();
      await profile.refreshMyAnimeList();
      await credential.clear();
      client.sessionChanges.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(profile.displayName, 'Local reader');
      expect(profile.myAnimeListUsername, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString(
          'profile_display_name_v1',
        ),
        'Local reader',
      );
    },
  );

  test(
    'switching accounts changes the visible identity and retains the local name',
    () async {
      await profile.load();
      await profile.refreshMyAnimeList();
      credential.value = connectedIdentity(8, 'SecondOwner');
      client.sessionChanges.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(profile.displayName, 'SecondOwner');
      expect(profile.myAnimeListUsername, 'SecondOwner');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'profile_display_name_v1',
        ),
        'Local reader',
      );
    },
  );

  test(
    'an older credential read cannot replace a newer account identity',
    () async {
      await profile.load();
      await profile.refreshMyAnimeList();
      final gate = Completer<Map<String, dynamic>?>();
      credential.nextLoad = gate.future;
      final older = profile.reloadMyAnimeListIdentity();
      credential.value = connectedIdentity(8, 'SecondOwner');
      await profile.reloadMyAnimeListIdentity();
      gate.complete(connectedIdentity(7, 'PreviousOwner'));
      await older;
      expect(profile.displayName, 'SecondOwner');
    },
  );

  test(
    'disposing during an asynchronous identity read removes the listener safely',
    () async {
      await profile.load();
      await profile.refreshMyAnimeList();
      var notifications = 0;
      profile.addListener(() => notifications++);
      final gate = Completer<Map<String, dynamic>?>();
      credential.nextLoad = gate.future;
      final pending = profile.reloadMyAnimeListIdentity();
      profile.dispose();
      disposed = true;
      gate.complete(connectedIdentity(9, 'TooLate'));
      await pending;
      client.sessionChanges.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
    },
  );

  testWidgets(
    'profile renders a long MAL name on a narrow screen and updates after disconnect',
    (tester) async {
      const username = 'MangaReaderWithAVeryLongAccountName';
      credential.value = connectedIdentity(7, username);
      await profile.load();
      await profile.refreshMyAnimeList();
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final library = ProfileTestLibrary();
      final downloads = DownloadQueueProvider(useNative: true);
      final settings = ReaderSettingsProvider();
      final density = DensityProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileProvider>.value(value: profile),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<DownloadQueueProvider>.value(
              value: downloads,
            ),
            ChangeNotifierProvider<ReaderSettingsProvider>.value(
              value: settings,
            ),
            ChangeNotifierProvider<DensityProvider>.value(value: density),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Nombre de MyAnimeList'));
      expect(find.text(username), findsOneWidget);
      expect(find.text('@$username · MyAnimeList'), findsOneWidget);
      final nameControl = find
          .ancestor(of: find.text(username), matching: find.byType(InkWell))
          .first;
      expect(tester.widget<InkWell>(nameControl).onTap, isNull);
      expect(find.text('Nombre de perfil'), findsNothing);
      expect(tester.takeException(), isNull);
      await credential.clear();
      client.sessionChanges.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Local reader'), findsOneWidget);
      expect(find.text('@$username · MyAnimeList'), findsNothing);
      final localControl = find
          .ancestor(
            of: find.text('Local reader'),
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.widget<InkWell>(localControl).onTap, isNotNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
      downloads.dispose();
      settings.dispose();
      density.dispose();
    },
  );
}
