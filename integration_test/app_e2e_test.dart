import 'dart:io';
import 'dart:typed_data';

import 'package:auraboard/app.dart';
import 'package:auraboard/data/audio_file_store.dart';
import 'package:auraboard/data/file_library_repository.dart';
import 'package:auraboard/data/file_picker_gateway.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class _E2EFilePickerGateway implements FilePickerGateway {
  _E2EFilePickerGateway(this.filesToPick);

  List<PickedAudioFile> filesToPick;

  @override
  Future<List<PickedAudioFile>> pickAudioFiles() async => filesToPick;

  @override
  Future<Uint8List?> pickBackupBytes() async => null;

  @override
  Future<bool> saveBackupBytes({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async => true;
}

Finder _padTileInGrid(String label) {
  final textInGrid = find.descendant(
    of: find.byType(GridView),
    matching: find.text(label),
  );
  return find.ancestor(of: textInGrid, matching: find.byType(Card)).first;
}

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AuraBoard Android End-to-End Journeys (real SoLoud & disk storage)', () {
    testWidgets(
      '1) import a sound into app-private storage, play it, see playing state, and stop it',
      (WidgetTester tester) async {
        final baseDir = await getApplicationSupportDirectory();
        final e2eRoot = Directory(
          p.join(
            baseDir.path,
            'e2e_import_${DateTime.now().millisecondsSinceEpoch}',
          ),
        )..createSync(recursive: true);
        addTearDown(() {
          if (e2eRoot.existsSync()) {
            e2eRoot.deleteSync(recursive: true);
          }
        });
        final externalDir = Directory(p.join(e2eRoot.path, 'external'))
          ..createSync(recursive: true);
        final appDir = Directory(p.join(e2eRoot.path, 'app'))
          ..createSync(recursive: true);

        // Stage a real synthesized WAV asset into external storage to simulate
        // picking a file from the Android device.
        final assetBytes = (await rootBundle.load(
          'assets/demo_audio/combat_drums_music.wav',
        )).buffer.asUint8List();
        final externalWav = File(
          p.join(externalDir.path, 'dragon_roar_sfx.wav'),
        )..writeAsBytesSync(assetBytes, flush: true);

        final repo = FileLibraryRepository(directory: appDir);
        final store = AudioFileStore(baseDirectory: appDir);
        final picker = _E2EFilePickerGateway(<PickedAudioFile>[
          PickedAudioFile(name: 'dragon_roar_sfx.wav', path: externalWav.path),
        ]);

        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey<String>('e2e_journey_1'),
            overrides: [
              libraryRepositoryProvider.overrideWithValue(repo),
              audioFileStoreProvider.overrideWithValue(store),
              filePickerGatewayProvider.overrideWithValue(picker),
            ],
            child: const AuraBoardApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Enter Edit Mode and import the WAV file.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('import_audio_button')));
        await _pumpFor(tester, const Duration(milliseconds: 600));
        await tester.pumpAndSettle();

        // Delete the external original file to prove playback uses the
        // app-private copy!
        externalWav.deleteSync();

        // Exit Edit Mode -> Play Mode.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        final importedTile = _padTileInGrid('Dragon Roar Sfx');
        await tester.ensureVisible(importedTile);
        await tester.pumpAndSettle();

        // Tap imported pad -> verify playing state appears.
        await tester.tap(importedTile);
        await _pumpFor(tester, const Duration(milliseconds: 400));

        expect(
          find.descendant(
            of: importedTile,
            matching: find.textContaining(
              RegExp(r'Playing|Fading in', caseSensitive: false),
            ),
          ),
          findsOneWidget,
        );

        // Stop it via Now Playing item stop button (for Effect pads) and
        // confirm it returns to Idle.
        final loadedLib = await repo.load();
        final importedPad = loadedLib.pads.firstWhere(
          (pad) => pad.label == 'Dragon Roar Sfx',
        );
        final stopBtn = find.byKey(Key('now_playing_stop_${importedPad.id}'));
        expect(stopBtn, findsOneWidget);
        await tester.tap(stopBtn);
        await _pumpFor(tester, const Duration(milliseconds: 400));

        expect(stopBtn, findsNothing);
        expect(
          find.descendant(
            of: importedTile,
            matching: find.textContaining(
              RegExp(r'Playing|Fading in|Fading out', caseSensitive: false),
            ),
          ),
          findsNothing,
        );
        final semanticsHandle = tester.ensureSemantics();
        try {
          expect(
            find.bySemanticsLabel(
              RegExp(
                r'Dragon Roar Sfx.*Idle',
                caseSensitive: false,
                dotAll: true,
              ),
            ),
            findsOneWidget,
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      '2) create folder, move/rename/recolor pad, restart app, and verify layout intact with no auto-resume',
      (WidgetTester tester) async {
        final baseDir = await getApplicationSupportDirectory();
        final appDir = Directory(
          p.join(
            baseDir.path,
            'e2e_persist_${DateTime.now().millisecondsSinceEpoch}',
          ),
        )..createSync(recursive: true);
        addTearDown(() {
          if (appDir.existsSync()) {
            appDir.deleteSync(recursive: true);
          }
        });

        final repo1 = FileLibraryRepository(directory: appDir);
        final store1 = AudioFileStore(baseDirectory: appDir);

        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey<String>('e2e_journey_2_run1'),
            overrides: [
              libraryRepositoryProvider.overrideWithValue(repo1),
              audioFileStoreProvider.overrideWithValue(store1),
            ],
            child: const AuraBoardApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Enter Edit Mode and create "Boss Fight" folder.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('add_folder_button')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('folder_name_input')),
          'Boss Fight',
        );
        await tester.tap(find.byKey(const Key('folder_dialog_confirm')));
        await tester.pumpAndSettle();
        expect(find.text('Boss Fight'), findsOneWidget);

        // Tap Sword Clash in Edit Mode to rename, recolor, and move to Boss Fight.
        final swordTile = _padTileInGrid('Sword Clash');
        await tester.ensureVisible(swordTile);
        await tester.tap(swordTile);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('pad_editor_label')),
          'Vorpal Blade',
        );
        final colorSwatch = find.byKey(const Key('pad_color_4'));
        await tester.ensureVisible(colorSwatch);
        await tester.tap(colorSwatch);
        await tester.pumpAndSettle();

        final folderDropdown = find.byKey(const Key('pad_editor_folder'));
        await tester.ensureVisible(folderDropdown);
        await tester.tap(folderDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Boss Fight').last);
        await tester.pumpAndSettle();

        final saveBtn = find.byKey(const Key('pad_editor_save'));
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await _pumpFor(tester, const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Exit Edit Mode and start Battle Drums so we also verify NO auto-resume
        // after restart.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();
        await tester.tap(_padTileInGrid('Battle Drums'));
        await _pumpFor(tester, const Duration(milliseconds: 400));

        // Simulate full app restart with a fresh ProviderScope & FileLibraryRepository
        // reading from the exact same disk directory.
        final repo2 = FileLibraryRepository(directory: appDir);
        final store2 = AudioFileStore(baseDirectory: appDir);

        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey<String>('e2e_journey_2_run2'),
            overrides: [
              libraryRepositoryProvider.overrideWithValue(repo2),
              audioFileStoreProvider.overrideWithValue(store2),
            ],
            child: const AuraBoardApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Playback must NOT auto-resume after restart.
        expect(
          find.textContaining(
            RegExp(r'Playing|Fading in|Fading out', caseSensitive: false),
          ),
          findsNothing,
        );

        // Verify Boss Fight folder exists and contains renamed & recolored Vorpal Blade.
        final bossChip = find.text('Boss Fight');
        await tester.ensureVisible(bossChip);
        await tester.tap(bossChip);
        await tester.pumpAndSettle();

        expect(_padTileInGrid('Vorpal Blade'), findsOneWidget);
        final persistedLib = await repo2.load();
        final movedPad = persistedLib.pads.firstWhere(
          (pad) => pad.label == 'Vorpal Blade',
        );
        final bossFolder = persistedLib.folders.firstWhere(
          (folder) => folder.name == 'Boss Fight',
        );
        expect(movedPad.folderId, bossFolder.id);
        expect(movedPad.colorValue, isNot(0xFFB84A39));
      },
    );

    testWidgets(
      '3 & 4) start Music A then Music B ending with only B playing, layer ambience, then Stop All',
      (WidgetTester tester) async {
        final baseDir = await getApplicationSupportDirectory();
        final appDir = Directory(
          p.join(
            baseDir.path,
            'e2e_music_${DateTime.now().millisecondsSinceEpoch}',
          ),
        )..createSync(recursive: true);
        addTearDown(() {
          if (appDir.existsSync()) {
            appDir.deleteSync(recursive: true);
          }
        });

        final repo = FileLibraryRepository(directory: appDir);
        // Use brisk fade durations (300ms/400ms/600ms) so real-time audio
        // crossfade & stop-all verification completes deterministically.
        final initial = await repo.load();
        await repo.save(
          initial.copyWith(
            settings: initial.settings.copyWith(
              defaultFadeInMs: 300,
              defaultFadeOutMs: 400,
              defaultCrossfadeMs: 600,
            ),
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            key: const ValueKey<String>('e2e_journey_3_4'),
            overrides: [
              libraryRepositoryProvider.overrideWithValue(repo),
              audioFileStoreProvider.overrideWithValue(
                AudioFileStore(baseDirectory: appDir),
              ),
            ],
            child: const AuraBoardApp(),
          ),
        );
        await tester.pumpAndSettle();

        // Start Music A (Battle Drums) in Combat folder.
        await tester.tap(_padTileInGrid('Battle Drums'));
        await _pumpFor(tester, const Duration(milliseconds: 600));

        expect(
          find.descendant(
            of: _padTileInGrid('Battle Drums'),
            matching: find.text('Playing'),
          ),
          findsOneWidget,
        );

        // Switch to Tavern folder and start Music B (Tavern Hearth) -> crossfades!
        final tavernChip = find.text('Tavern');
        await tester.ensureVisible(tavernChip);
        await tester.tap(tavernChip);
        await tester.pumpAndSettle();

        await tester.tap(_padTileInGrid('Tavern Hearth'));
        // Wait for 600ms crossfade + margin to complete.
        await _pumpFor(tester, const Duration(milliseconds: 1100));

        // Verify ONLY Music B (Tavern Hearth) is playing, NOT Battle Drums!
        expect(
          find.byKey(const Key('now_playing_stop_pad_tavern_hearth')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('now_playing_stop_pad_battle_drums')),
          findsNothing,
        );

        // Layer Steady Rain ambience alongside Tavern Hearth.
        await tester.tap(_padTileInGrid('Steady Rain'));
        await _pumpFor(tester, const Duration(milliseconds: 600));
        expect(
          find.byKey(const Key('now_playing_stop_pad_steady_rain')),
          findsOneWidget,
        );

        // Tap Stop All and wait for smooth 400ms fade-out to complete.
        await tester.tap(find.byKey(const Key('stop_all_button')));
        await _pumpFor(tester, const Duration(milliseconds: 900));

        expect(
          find.byKey(const Key('now_playing_stop_pad_tavern_hearth')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('now_playing_stop_pad_steady_rain')),
          findsNothing,
        );
        expect(
          find.textContaining(
            RegExp(r'Playing|Fading in|Fading out', caseSensitive: false),
          ),
          findsNothing,
        );
      },
    );
  });
}
