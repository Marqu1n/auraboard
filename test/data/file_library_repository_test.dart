import 'dart:convert';
import 'dart:io';

import 'package:auraboard/data/demo_board.dart';
import 'package:auraboard/data/file_library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Directory _createTempDir() {
  final dir = Directory.systemTemp.createTempSync('auraboard_file_repo_test_');
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

List<File> _tmpFilesIn(Directory dir) {
  return dir
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).contains('.tmp'))
      .toList();
}

void main() {
  group('FileLibraryRepository', () {
    test(
      'first load on empty directory seeds demo library and writes library.json with no leftover .tmp',
      () async {
        final dir = _createTempDir();
        final repo = FileLibraryRepository(directory: dir);

        final loaded = await repo.load();

        expect(loaded, equals(createDemoLibrary()));
        expect(
          loaded.folders.map((f) => f.name).toList(),
          containsAll(<String>['Combat', 'Tavern', 'Dungeon']),
        );

        final libraryFile = File(p.join(dir.path, 'library.json'));
        expect(libraryFile.existsSync(), isTrue);
        expect(_tmpFilesIn(dir), isEmpty);

        final decoded =
            jsonDecode(libraryFile.readAsStringSync()) as Map<String, dynamic>;
        expect(SoundLibrary.fromJson(decoded), equals(loaded));
      },
    );

    test(
      'save writes atomically and persists all folders, pads, and settings across a fresh instance',
      () async {
        final dir = _createTempDir();
        final repo1 = FileLibraryRepository(directory: dir);
        final initial = await repo1.load();

        final updated = initial.copyWith(
          folders: <SoundFolder>[
            ...initial.folders,
            const SoundFolder(id: 'folder_boss', name: 'Boss Fight', order: 3),
          ],
          pads: <SoundPad>[
            ...initial.pads.map(
              (pad) => pad.id == 'pad_sword_clash'
                  ? pad.copyWith(
                      label: 'Vorpal Blade',
                      colorValue: 0xFF6A4C93,
                      icon: PadIcon.magic,
                      folderId: 'folder_boss',
                      volume: 0.72,
                      retriggerMode: RetriggerMode.layer,
                      fadeInMsOverride: 150,
                      fadeOutMsOverride: 300,
                      crossfadeMsOverride: 900,
                      order: 0,
                    )
                  : pad,
            ),
          ],
          settings: const BoardSettings(
            defaultFadeInMs: 400,
            defaultFadeOutMs: 1200,
            defaultCrossfadeMs: 2500,
            masterVolume: 0.65,
            keepScreenAwake: true,
            gridDensity: GridDensity.compact,
            themeMode: AppThemeMode.light,
            seedColorValue: 0xFF3A7D44,
            useDynamicColor: false,
          ),
        );

        await repo1.save(updated);

        final libraryFile = File(p.join(dir.path, 'library.json'));
        expect(libraryFile.existsSync(), isTrue);
        expect(_tmpFilesIn(dir), isEmpty);

        // Simulate full app restart with a brand-new repository instance.
        final repo2 = FileLibraryRepository(directory: dir);
        final reloaded = await repo2.load();

        expect(reloaded, equals(updated));
        expect(
          reloaded.folders.any(
            (f) => f.id == 'folder_boss' && f.name == 'Boss Fight',
          ),
          isTrue,
        );
        final vorpal = reloaded.pads.firstWhere(
          (pad) => pad.id == 'pad_sword_clash',
        );
        expect(vorpal.label, 'Vorpal Blade');
        expect(vorpal.folderId, 'folder_boss');
        expect(vorpal.icon, PadIcon.magic);
        expect(vorpal.retriggerMode, RetriggerMode.layer);
        expect(vorpal.fadeInMsOverride, 150);
        expect(vorpal.fadeOutMsOverride, 300);
        expect(vorpal.crossfadeMsOverride, 900);
        expect(reloaded.settings.masterVolume, closeTo(0.65, 1e-9));
        expect(reloaded.settings.keepScreenAwake, isTrue);
        expect(reloaded.settings.gridDensity, GridDensity.compact);
        expect(reloaded.settings.themeMode, AppThemeMode.light);
        expect(reloaded.settings.useDynamicColor, isFalse);
      },
    );

    test(
      'concurrent save calls are serialized without corruption and final saved state wins',
      () async {
        final dir = _createTempDir();
        final repo = FileLibraryRepository(directory: dir);
        final base = await repo.load();

        final snapshots = List<SoundLibrary>.generate(12, (index) {
          final volume = (index + 1) / 12.0;
          return base.copyWith(
            folders: <SoundFolder>[
              ...base.folders,
              SoundFolder(
                id: 'folder_seq_$index',
                name: 'Campaign $index',
                order: base.folders.length,
              ),
            ],
            settings: base.settings.copyWith(masterVolume: volume),
          );
        });

        await Future.wait(snapshots.map(repo.save));

        expect(_tmpFilesIn(dir), isEmpty);

        final libraryFile = File(p.join(dir.path, 'library.json'));
        expect(libraryFile.existsSync(), isTrue);
        final decoded =
            jsonDecode(libraryFile.readAsStringSync()) as Map<String, dynamic>;
        expect(SoundLibrary.fromJson(decoded), equals(snapshots.last));

        final freshRepo = FileLibraryRepository(directory: dir);
        final reloaded = await freshRepo.load();
        expect(reloaded, equals(snapshots.last));
      },
    );

    test(
      'corrupt JSON recovers gracefully by backing up corrupt file and falling back to demo library',
      () async {
        final dir = _createTempDir();
        final libraryFile = File(p.join(dir.path, 'library.json'));
        const corruptPayload = '{not valid json: [unterminated';
        libraryFile.writeAsStringSync(corruptPayload);

        final repo = FileLibraryRepository(directory: dir);
        final recovered = await repo.load();

        expect(recovered, equals(createDemoLibrary()));
        expect(_tmpFilesIn(dir), isEmpty);

        // Original corrupt payload must be backed up to a separate file.
        final backupFiles = dir
            .listSync()
            .whereType<File>()
            .where((file) => p.basename(file.path) != 'library.json')
            .toList();
        expect(backupFiles, isNotEmpty);
        expect(
          backupFiles.any((file) => file.readAsStringSync() == corruptPayload),
          isTrue,
          reason:
              'Corrupt library.json contents must be preserved in a backup file',
        );

        // library.json should now contain a valid recovered demo library.
        final decoded =
            jsonDecode(libraryFile.readAsStringSync()) as Map<String, dynamic>;
        expect(SoundLibrary.fromJson(decoded), equals(recovered));
      },
    );

    test(
      'schema-invalid JSON recovers gracefully by backing up corrupt file and falling back to demo library',
      () async {
        final dir = _createTempDir();
        final libraryFile = File(p.join(dir.path, 'library.json'));
        const badSchemaPayload = '{"schemaVersion": 1, "folders": "oops"}';
        libraryFile.writeAsStringSync(badSchemaPayload);

        final repo = FileLibraryRepository(directory: dir);
        final recovered = await repo.load();

        expect(recovered, equals(createDemoLibrary()));
        expect(_tmpFilesIn(dir), isEmpty);

        final backupFiles = dir
            .listSync()
            .whereType<File>()
            .where((file) => p.basename(file.path) != 'library.json')
            .toList();
        expect(
          backupFiles.any(
            (file) => file.readAsStringSync() == badSchemaPayload,
          ),
          isTrue,
        );
      },
    );
  });
}
