import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:auraboard/app.dart';
import 'package:auraboard/data/audio_file_store.dart';
import 'package:auraboard/data/demo_board.dart';
import 'package:auraboard/data/file_picker_gateway.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';

class _FakeFilePickerGateway implements FilePickerGateway {
  _FakeFilePickerGateway({
    this.pickedAudioFiles = const <PickedAudioFile>[],
    this.backupBytesToPick,
  });

  List<PickedAudioFile> pickedAudioFiles;
  Uint8List? backupBytesToPick;
  bool saveResult = true;

  String? savedFileName;
  Uint8List? savedBackupBytes;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => pickedAudioFiles;

  @override
  Future<Uint8List?> pickBackupBytes() async => backupBytesToPick;

  @override
  Future<bool> saveBackupBytes({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    savedFileName = suggestedFileName;
    savedBackupBytes = Uint8List.fromList(bytes);
    return saveResult;
  }
}

/// Pumps real `dart:io` async completions safely inside Flutter's FakeAsync
/// widget-test zone without wall-clock `Future.delayed` sleeps.
Future<void> _waitForDiskIo(
  WidgetTester tester,
  Future<bool> Function() predicate,
) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (await predicate()) {
      await tester.pumpAndSettle();
      return;
    }
    await tester.runAsync(() => Directory.systemTemp.exists());
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Directory _createTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });
  return dir;
}

Future<void> _pumpAuraBoard(
  WidgetTester tester, {
  required FakeAudioEngine audioEngine,
  required FakeClock clock,
  required LibraryRepository repository,
  required AudioFileStore audioFileStore,
  required FilePickerGateway filePickerGateway,
  Key? scopeKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: scopeKey,
      overrides: [
        audioEngineProvider.overrideWithValue(audioEngine),
        clockProvider.overrideWithValue(clock),
        libraryRepositoryProvider.overrideWithValue(repository),
        audioFileStoreProvider.overrideWithValue(audioFileStore),
        filePickerGatewayProvider.overrideWithValue(filePickerGateway),
      ],
      child: const AuraBoardApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _findPadTileInGrid(String padLabel) {
  final labelInGrid = find.descendant(
    of: find.byType(GridView),
    matching: find.text(padLabel),
  );
  return find.ancestor(of: labelInGrid, matching: find.byType(Card)).first;
}

void main() {
  group('Audio import UI flows', () {
    testWidgets(
      'Edit Mode multi-file import copies supported files to private storage, skips unsupported gracefully, and imported pad plays in Play Mode',
      (WidgetTester tester) async {
        final appDir = _createTempDir('auraboard_ui_import_app_');
        final externalDir = _createTempDir('auraboard_ui_import_ext_');
        final audioStore = AudioFileStore(baseDirectory: appDir);

        final wavBytes = File(
          'test/fixtures/sample_effect.wav',
        ).readAsBytesSync();
        final oggBytes = Uint8List.fromList(<int>[
          0x4F,
          0x67,
          0x67,
          0x53,
          0x00,
          0x02,
          0x01,
          0x02,
        ]);
        final txtBytes = File(
          'test/fixtures/unsupported.txt',
        ).readAsBytesSync();

        final goblinFile = File(p.join(externalDir.path, 'goblin_laugh.wav'))
          ..writeAsBytesSync(wavBytes);
        final luteFile = File(p.join(externalDir.path, 'tavern_lute.ogg'))
          ..writeAsBytesSync(oggBytes);
        final notesFile = File(p.join(externalDir.path, 'notes.txt'))
          ..writeAsBytesSync(txtBytes);

        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();
        final fakePicker = _FakeFilePickerGateway(
          pickedAudioFiles: <PickedAudioFile>[
            PickedAudioFile(name: 'goblin_laugh.wav', path: goblinFile.path),
            PickedAudioFile(name: 'tavern_lute.ogg', path: luteFile.path),
            PickedAudioFile(name: 'notes.txt', path: notesFile.path),
          ],
        );

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
          audioFileStore: audioStore,
          filePickerGateway: fakePicker,
        );

        // Import button must be hidden in Play Mode.
        expect(find.byKey(const Key('import_audio_button')), findsNothing);

        // Enter Edit Mode and trigger multi-file import.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        final importBtn = find.byKey(const Key('import_audio_button'));
        expect(importBtn, findsOneWidget);

        await tester.tap(importBtn);
        await _waitForDiskIo(
          tester,
          () async => (await repository.load()).pads.any(
            (p) => p.label == 'Goblin Laugh',
          ),
        );

        // Feedback SnackBar should be presented to the GM.
        expect(find.byType(SnackBar), findsOneWidget);

        // Persisted library contains both imported pads in the active folder,
        // and gracefully skipped notes.txt.
        final updatedLibrary = await repository.load();
        final activeFolderId = updatedLibrary.folders.first.id;
        final goblinPad = updatedLibrary.pads.firstWhere(
          (pad) => pad.label == 'Goblin Laugh',
        );
        final lutePad = updatedLibrary.pads.firstWhere(
          (pad) => pad.label == 'Tavern Lute',
        );

        expect(goblinPad.folderId, activeFolderId);
        expect(lutePad.folderId, activeFolderId);
        expect(goblinPad.isAsset, isFalse);
        expect(lutePad.isAsset, isFalse);
        expect(
          p.isWithin(audioStore.audioDirectory.path, goblinPad.audioPath),
          isTrue,
        );
        expect(
          p.isWithin(audioStore.audioDirectory.path, lutePad.audioPath),
          isTrue,
        );
        expect(File(goblinPad.audioPath).readAsBytesSync(), equals(wavBytes));
        expect(File(lutePad.audioPath).readAsBytesSync(), equals(oggBytes));
        expect(
          updatedLibrary.pads.any(
            (pad) => pad.label.toLowerCase().contains('notes'),
          ),
          isFalse,
        );

        // Delete original external files to prove playback uses private copy.
        goblinFile.deleteSync();
        luteFile.deleteSync();

        // Exit Edit Mode back to Play Mode and tap the imported pad.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.descendant(
            of: find.byType(GridView),
            matching: find.text('Goblin Laugh'),
          ),
          200,
          scrollable: find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();

        final goblinTile = _findPadTileInGrid('Goblin Laugh');
        expect(goblinTile, findsOneWidget);
        await tester.tap(goblinTile);
        await tester.pump();

        expect(fakeEngine.playedHandles, hasLength(1));
        expect(
          fakeEngine.pathForHandle(fakeEngine.playedHandles.single),
          equals(goblinPad.audioPath),
        );
      },
    );

    testWidgets(
      'importing a corrupt audio file adds pad and tapping it in Play Mode shows Error state without crashing',
      (WidgetTester tester) async {
        final appDir = _createTempDir('auraboard_ui_corrupt_app_');
        final audioStore = AudioFileStore(baseDirectory: appDir);
        final corruptBytes = File(
          'test/fixtures/corrupt.wav',
        ).readAsBytesSync();

        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();
        final fakePicker = _FakeFilePickerGateway(
          pickedAudioFiles: <PickedAudioFile>[
            PickedAudioFile(name: 'broken_horn.wav', bytes: corruptBytes),
          ],
        );

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
          audioFileStore: audioStore,
          filePickerGateway: fakePicker,
        );

        // Enter Edit Mode and import corrupt file (bytes-only SAF path).
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('import_audio_button')));
        await _waitForDiskIo(
          tester,
          () async => (await repository.load()).pads.any(
            (p) => p.label == 'Broken Horn',
          ),
        );

        final library = await repository.load();
        final brokenPad = library.pads.firstWhere(
          (pad) => pad.label == 'Broken Horn',
        );
        expect(
          p.isWithin(audioStore.audioDirectory.path, brokenPad.audioPath),
          isTrue,
        );

        // Simulate audio engine failing to decode the corrupt file.
        fakeEngine.failingPaths.add(brokenPad.audioPath);

        // Return to Play Mode and tap the corrupt pad.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.descendant(
            of: find.byType(GridView),
            matching: find.text('Broken Horn'),
          ),
          200,
          scrollable: find.descendant(
            of: find.byType(GridView),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pumpAndSettle();

        final brokenTile = _findPadTileInGrid('Broken Horn');
        await tester.tap(brokenTile);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: brokenTile,
            matching: find.byIcon(Icons.error_outline),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp('Broken Horn.*Error', caseSensitive: false),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('Backup export & import UI flows', () {
    testWidgets(
      'Settings export creates valid ZIP and Settings import restores library while stopping active playback',
      (WidgetTester tester) async {
        final deviceADir = _createTempDir('auraboard_ui_backup_a_');
        final deviceBDir = _createTempDir('auraboard_ui_backup_b_');

        final storeA = AudioFileStore(baseDirectory: deviceADir);
        final dragonBytes = File(
          'test/fixtures/sample_effect.wav',
        ).readAsBytesSync();
        final dragonPathA = (await tester.runAsync(
          () => storeA.writeBytesToPrivateStorage(
            bytes: dragonBytes,
            originalFileName: 'dragon_breath.wav',
          ),
        ))!;

        final demoBase = createDemoLibrary();
        final customLibraryA = demoBase.copyWith(
          folders: <SoundFolder>[
            ...demoBase.folders,
            const SoundFolder(
              id: 'folder_vault',
              name: 'Campaign Vault',
              order: 3,
            ),
          ],
          pads: <SoundPad>[
            ...demoBase.pads,
            SoundPad(
              id: 'pad_dragon_breath',
              folderId: 'folder_vault',
              label: 'Dragon Breath',
              colorValue: 0xFFC43B3B,
              icon: PadIcon.fire,
              audioPath: dragonPathA,
              isAsset: false,
              type: PadType.effect,
              order: 0,
            ),
          ],
        );

        final repositoryA = InMemoryLibraryRepository(
          initialLibrary: customLibraryA,
        );
        final pickerA = _FakeFilePickerGateway();

        await _pumpAuraBoard(
          tester,
          scopeKey: const ValueKey<String>('device_a_scope'),
          audioEngine: FakeAudioEngine(),
          clock: FakeClock(),
          repository: repositoryA,
          audioFileStore: storeA,
          filePickerGateway: pickerA,
        );

        // Open Settings and export backup.
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        final exportBtn = find.byKey(const Key('export_backup_button'));
        await tester.ensureVisible(exportBtn);
        await tester.pumpAndSettle();
        await tester.tap(exportBtn);
        await _waitForDiskIo(
          tester,
          () async => pickerA.savedBackupBytes != null,
        );

        expect(pickerA.savedBackupBytes, isNotNull);
        expect(pickerA.savedBackupBytes!, isNotEmpty);
        expect(pickerA.savedFileName, isNotNull);
        expect(pickerA.savedFileName!, isNotEmpty);

        final exportedZip = ZipDecoder().decodeBytes(pickerA.savedBackupBytes!);
        expect(exportedZip.findFile('manifest.json'), isNotNull);

        // Switch to a fresh simulated Device B with active playback running.
        final storeB = AudioFileStore(baseDirectory: deviceBDir);
        final repositoryB = InMemoryLibraryRepository();
        final fakeEngineB = FakeAudioEngine();
        final fakeClockB = FakeClock();
        final pickerB = _FakeFilePickerGateway(
          backupBytesToPick: pickerA.savedBackupBytes,
        );

        await _pumpAuraBoard(
          tester,
          scopeKey: const ValueKey<String>('device_b_scope'),
          audioEngine: fakeEngineB,
          clock: fakeClockB,
          repository: repositoryB,
          audioFileStore: storeB,
          filePickerGateway: pickerB,
        );

        // Start playback on Device B before importing backup.
        final swordTile = _findPadTileInGrid('Sword Clash');
        await tester.tap(swordTile);
        await tester.pump();
        expect(fakeEngineB.activeHandles, isNotEmpty);
        expect(fakeClockB.activeTimerCount, greaterThan(0));

        // Open Settings, tap Import Backup, and confirm overwrite.
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        final importBackupBtn = find.byKey(const Key('import_backup_button'));
        await tester.ensureVisible(importBackupBtn);
        await tester.pumpAndSettle();
        await tester.tap(importBackupBtn);
        await tester.pumpAndSettle();

        final confirmBtn = find.byKey(const Key('confirm_import_backup'));
        expect(confirmBtn, findsOneWidget);
        await tester.tap(confirmBtn);
        await _waitForDiskIo(
          tester,
          () async => (await repositoryB.load()).folders.any(
            (f) => f.name == 'Campaign Vault',
          ),
        );

        // Complete smooth stopAll fade-out on FakeClock and verify active
        // playback has stopped.
        fakeClockB.advance(const Duration(seconds: 3));
        await tester.pump();
        expect(fakeEngineB.activeHandles, isEmpty);

        // Verify restored library on Device B includes custom folder & audio file.
        final restoredLibrary = await repositoryB.load();
        expect(
          restoredLibrary.folders.any((f) => f.name == 'Campaign Vault'),
          isTrue,
        );
        final restoredDragonPad = restoredLibrary.pads.firstWhere(
          (pad) => pad.id == 'pad_dragon_breath',
        );
        expect(
          p.isWithin(storeB.audioDirectory.path, restoredDragonPad.audioPath),
          isTrue,
        );
        expect(
          File(restoredDragonPad.audioPath).readAsBytesSync(),
          equals(dragonBytes),
        );

        // Close settings if still open so we can verify restored folder in UI.
        if (find
            .byKey(const Key('import_backup_button'))
            .evaluate()
            .isNotEmpty) {
          Navigator.of(
            tester.element(find.byKey(const Key('import_backup_button'))),
          ).pop();
          await tester.pumpAndSettle();
        }

        final vaultChip = find.text('Campaign Vault');
        await tester.ensureVisible(vaultChip);
        await tester.pumpAndSettle();
        await tester.tap(vaultChip);
        await tester.pumpAndSettle();

        expect(_findPadTileInGrid('Dragon Breath'), findsOneWidget);
      },
    );
  });

  group('Import & Backup accessibility and scaling', () {
    testWidgets(
      'import_audio_button, export_backup_button, and import_backup_button meet >= 48dp touch targets and render overflow-free at 2.0x text scale on 360x740',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });

        final flutterErrors = <FlutterErrorDetails>[];
        final previousOnError = FlutterError.onError;
        FlutterError.onError = flutterErrors.add;
        try {
          final appDir = _createTempDir('auraboard_ui_a11y_');
          final audioStore = AudioFileStore(baseDirectory: appDir);

          await _pumpAuraBoard(
            tester,
            audioEngine: FakeAudioEngine(),
            clock: FakeClock(),
            repository: InMemoryLibraryRepository(),
            audioFileStore: audioStore,
            filePickerGateway: _FakeFilePickerGateway(),
          );

          // Verify import_audio_button in Edit Mode at 2.0x scale on 360x740.
          await tester.tap(find.byKey(const Key('edit_mode_toggle')));
          await tester.pumpAndSettle();

          final importAudioBtn = find.byKey(const Key('import_audio_button'));
          expect(importAudioBtn, findsOneWidget);
          final importAudioSize = tester.getSize(importAudioBtn);
          expect(importAudioSize.width, greaterThanOrEqualTo(48.0));
          expect(importAudioSize.height, greaterThanOrEqualTo(48.0));

          // Open Settings and verify backup buttons at 2.0x scale on 360x740.
          await tester.tap(find.byKey(const Key('settings_button')));
          await tester.pumpAndSettle();

          final exportBackupBtn = find.byKey(const Key('export_backup_button'));
          await tester.ensureVisible(exportBackupBtn);
          await tester.pumpAndSettle();
          expect(exportBackupBtn, findsOneWidget);
          final exportSize = tester.getSize(exportBackupBtn);
          expect(exportSize.width, greaterThanOrEqualTo(48.0));
          expect(exportSize.height, greaterThanOrEqualTo(48.0));

          final importBackupBtn = find.byKey(const Key('import_backup_button'));
          await tester.ensureVisible(importBackupBtn);
          await tester.pumpAndSettle();
          expect(importBackupBtn, findsOneWidget);
          final importBackupSize = tester.getSize(importBackupBtn);
          expect(importBackupSize.width, greaterThanOrEqualTo(48.0));
          expect(importBackupSize.height, greaterThanOrEqualTo(48.0));

          expect(flutterErrors, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );
  });
}
