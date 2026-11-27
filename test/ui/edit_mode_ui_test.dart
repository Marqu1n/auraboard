import 'package:auraboard/app.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';

Future<void> _pumpAuraBoard(
  WidgetTester tester, {
  required FakeAudioEngine audioEngine,
  required FakeClock clock,
  required LibraryRepository repository,
  Key? scopeKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: scopeKey,
      overrides: [
        audioEngineProvider.overrideWithValue(audioEngine),
        clockProvider.overrideWithValue(clock),
        libraryRepositoryProvider.overrideWithValue(repository),
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

Finder _findFolderNameInput() {
  final byKey = find.byKey(const Key('folder_name_input'));
  if (byKey.evaluate().isNotEmpty) {
    return byKey;
  }
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
}

Finder _findDialogConfirmButton({
  required Key primaryKey,
  required List<String> fallbackLabels,
}) {
  final byKey = find.byKey(primaryKey);
  if (byKey.evaluate().isNotEmpty) {
    return byKey;
  }
  final dialog = find.byType(AlertDialog);
  for (final label in fallbackLabels) {
    final match = find.descendant(of: dialog, matching: find.text(label));
    if (match.evaluate().isNotEmpty) {
      return match.last;
    }
  }
  return byKey;
}

Future<void> _scrollIntoViewAndTap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('Play Mode safety (default)', () {
    testWidgets(
      'hides edit controls by default and tapping a pad plays audio instead of opening editor',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        expect(find.byKey(const Key('add_folder_button')), findsNothing);
        expect(find.byKey(const Key('manage_folders_button')), findsNothing);
        expect(find.byKey(const Key('pad_editor_save')), findsNothing);
        expect(find.byKey(const Key('pad_editor_delete')), findsNothing);
        expect(find.byIcon(Icons.delete), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);

        final swordTile = _findPadTileInGrid('Sword Clash');
        expect(swordTile, findsOneWidget);

        await tester.tap(swordTile);
        await tester.pump();

        expect(fakeEngine.playedHandles, hasLength(1));
        expect(find.byKey(const Key('pad_editor_label')), findsNothing);
        expect(find.byKey(const Key('pad_editor_save')), findsNothing);
      },
    );

    testWidgets(
      'dragging a pad in Play Mode does not reorder pads or mutate the library',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        final initialLibrary = await repository.load();
        final start = tester.getCenter(_findPadTileInGrid('Sword Clash'));
        final end = tester.getCenter(_findPadTileInGrid('Battle Drums'));

        // Attempt immediate drag in Play Mode.
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 60));
        await gesture.moveTo(end);
        await tester.pump(const Duration(milliseconds: 60));
        await gesture.up();
        await tester.pumpAndSettle();

        // Attempt long-press drag in Play Mode.
        final longGesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 600));
        await longGesture.moveTo(end);
        await tester.pump(const Duration(milliseconds: 60));
        await longGesture.up();
        await tester.pumpAndSettle();

        final afterLibrary = await repository.load();
        expect(afterLibrary, equals(initialLibrary));

        final combatPads =
            afterLibrary.pads
                .where((pad) => pad.folderId == 'folder_combat')
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));
        expect(combatPads.map((p) => p.label).toList(), <String>[
          'Sword Clash',
          'Fireball',
          'Battle Drums',
        ]);
      },
    );
  });

  group('Entering and exiting Edit Mode', () {
    testWidgets(
      'tapping edit_mode_toggle enters Edit Mode with unmistakable banner and returns to Play Mode on second tap',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        final toggle = find.byKey(const Key('edit_mode_toggle'));
        expect(toggle, findsOneWidget);

        // Enter Edit Mode.
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(
          find.textContaining(RegExp(r'edit mode', caseSensitive: false)),
          findsWidgets,
        );
        expect(find.byKey(const Key('add_folder_button')), findsOneWidget);
        expect(find.byKey(const Key('manage_folders_button')), findsOneWidget);

        // Exit Edit Mode back to Play Mode.
        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(
          find.textContaining(RegExp(r'edit mode', caseSensitive: false)),
          findsNothing,
        );
        expect(find.byKey(const Key('add_folder_button')), findsNothing);
        expect(find.byKey(const Key('manage_folders_button')), findsNothing);
      },
    );

    testWidgets(
      'tapping a pad in Edit Mode opens Pad Editor without triggering audio playback',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        await tester.tap(_findPadTileInGrid('Sword Clash'));
        await tester.pumpAndSettle();

        expect(fakeEngine.playedHandles, isEmpty);
        expect(fakeEngine.activeHandles, isEmpty);
        expect(find.byKey(const Key('pad_editor_label')), findsOneWidget);
        expect(find.byKey(const Key('pad_editor_save')), findsOneWidget);
      },
    );
  });

  group('Folder CRUD in Edit Mode', () {
    testWidgets(
      'creating a new folder via add_folder_button displays it in the folder bar and persists it',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('add_folder_button')));
        await tester.pumpAndSettle();

        final nameInput = _findFolderNameInput();
        expect(nameInput, findsOneWidget);
        await tester.enterText(nameInput, 'Boss Fight');
        await tester.pump();

        final confirm = _findDialogConfirmButton(
          primaryKey: const Key('folder_dialog_confirm'),
          fallbackLabels: const <String>['Create', 'Add', 'Save'],
        );
        expect(confirm, findsOneWidget);
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        expect(find.text('Boss Fight'), findsOneWidget);

        final persisted = await repository.load();
        expect(
          persisted.folders.map((folder) => folder.name).toList(),
          contains('Boss Fight'),
        );
      },
    );

    testWidgets(
      'manage_folders_button supports renaming, reordering, and deleting folders with persistence',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        // Create "Boss Fight" first.
        await tester.tap(find.byKey(const Key('add_folder_button')));
        await tester.pumpAndSettle();
        await tester.enterText(_findFolderNameInput(), 'Boss Fight');
        await tester.pump();
        await tester.tap(
          _findDialogConfirmButton(
            primaryKey: const Key('folder_dialog_confirm'),
            fallbackLabels: const <String>['Create', 'Add', 'Save'],
          ),
        );
        await tester.pumpAndSettle();

        final afterCreate = await repository.load();
        final bossFolder = afterCreate.folders.firstWhere(
          (folder) => folder.name == 'Boss Fight',
        );

        // Open Manage Folders sheet/dialog.
        await tester.tap(find.byKey(const Key('manage_folders_button')));
        await tester.pumpAndSettle();

        // 1) Rename "Boss Fight" -> "Dragon Lair".
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(Key('rename_folder_${bossFolder.id}')),
        );
        final renameInput = _findFolderNameInput();
        expect(renameInput, findsOneWidget);
        await tester.enterText(renameInput, 'Dragon Lair');
        await tester.pump();
        await tester.tap(
          _findDialogConfirmButton(
            primaryKey: const Key('folder_dialog_confirm'),
            fallbackLabels: const <String>['Save', 'Rename', 'OK'],
          ),
        );
        await tester.pumpAndSettle();

        var persisted = await repository.load();
        expect(
          persisted.folders.any(
            (f) => f.id == bossFolder.id && f.name == 'Dragon Lair',
          ),
          isTrue,
        );
        expect(persisted.folders.any((f) => f.name == 'Boss Fight'), isFalse);

        // 2) Reorder: move "Dragon Lair" up from index 3 to index 2.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(Key('move_folder_up_${bossFolder.id}')),
        );

        persisted = await repository.load();
        final sortedAfterReorder = List<SoundFolder>.from(persisted.folders)
          ..sort((a, b) => a.order.compareTo(b.order));
        expect(sortedAfterReorder.map((f) => f.name).toList(), <String>[
          'Combat',
          'Tavern',
          'Dragon Lair',
          'Dungeon',
        ]);

        // 3) Delete "Dungeon" folder.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(const Key('delete_folder_folder_dungeon')),
        );
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          await tester.tap(
            _findDialogConfirmButton(
              primaryKey: const Key('confirm_delete_folder'),
              fallbackLabels: const <String>['Delete', 'Confirm'],
            ),
          );
          await tester.pumpAndSettle();
        }

        persisted = await repository.load();
        final finalFolders = List<SoundFolder>.from(persisted.folders)
          ..sort((a, b) => a.order.compareTo(b.order));
        expect(finalFolders.map((f) => f.name).toList(), <String>[
          'Combat',
          'Tavern',
          'Dragon Lair',
        ]);
        expect(finalFolders.map((f) => f.order).toList(), <int>[0, 1, 2]);
      },
    );
  });

  group('Pad editing, moving, reordering, and deletion', () {
    testWidgets(
      'editing pad label, color, icon, and folder updates board and persists across fresh app restart without auto-resuming playback',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
          scopeKey: const ValueKey<String>('session_1'),
        );

        final initialSword = (await repository.load()).pads.firstWhere(
          (pad) => pad.id == 'pad_sword_clash',
        );

        // Enter Edit Mode and open Sword Clash editor.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();
        await tester.tap(_findPadTileInGrid('Sword Clash'));
        await tester.pumpAndSettle();

        // Edit label.
        final labelField = find.byKey(const Key('pad_editor_label'));
        expect(labelField, findsOneWidget);
        await tester.enterText(labelField, 'Vorpal Blade');
        await tester.pump();

        // Select a different color swatch.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(const Key('pad_color_3')),
        );

        // Select magic icon.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(const Key('pad_icon_magic')),
        );

        // Change folder to Tavern.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(const Key('pad_editor_folder')),
        );
        await tester.tap(find.text('Tavern').last);
        await tester.pumpAndSettle();

        // Save pad changes.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(const Key('pad_editor_save')),
        );

        // Gone from Combat grid.
        expect(
          find.descendant(
            of: find.byType(GridView),
            matching: find.text('Sword Clash'),
          ),
          findsNothing,
        );

        // Switch to Tavern -> Vorpal Blade appears with updated magic icon.
        await tester.tap(find.text('Tavern'));
        await tester.pumpAndSettle();
        final vorpalTile = _findPadTileInGrid('Vorpal Blade');
        expect(vorpalTile, findsOneWidget);
        expect(
          find.descendant(
            of: vorpalTile,
            matching: find.byIcon(Icons.auto_awesome),
          ),
          findsOneWidget,
        );

        // Verify persisted repository state.
        final persisted = await repository.load();
        final savedPad = persisted.pads.firstWhere(
          (pad) => pad.id == 'pad_sword_clash',
        );
        expect(savedPad.label, 'Vorpal Blade');
        expect(savedPad.folderId, 'folder_tavern');
        expect(savedPad.icon, PadIcon.magic);
        expect(savedPad.colorValue, isNot(initialSword.colorValue));

        // Simulate full app restart with a brand-new AuraBoardApp and fresh fakes.
        final restartedEngine = FakeAudioEngine();
        final restartedClock = FakeClock();
        await _pumpAuraBoard(
          tester,
          audioEngine: restartedEngine,
          clock: restartedClock,
          repository: repository,
          scopeKey: const ValueKey<String>('session_2'),
        );

        // Combat no longer contains Sword Clash.
        expect(
          find.descendant(
            of: find.byType(GridView),
            matching: find.text('Sword Clash'),
          ),
          findsNothing,
        );

        // Tavern still shows Vorpal Blade with magic icon.
        await tester.tap(find.text('Tavern'));
        await tester.pumpAndSettle();
        final restartedVorpalTile = _findPadTileInGrid('Vorpal Blade');
        expect(restartedVorpalTile, findsOneWidget);
        expect(
          find.descendant(
            of: restartedVorpalTile,
            matching: find.byIcon(Icons.auto_awesome),
          ),
          findsOneWidget,
        );

        // Playback must NOT auto-resume on restart.
        expect(restartedEngine.playedHandles, isEmpty);
        expect(restartedEngine.activeHandles, isEmpty);
      },
    );

    testWidgets(
      'drag-and-drop in Edit Mode reorders pads in Combat and persists new order',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();

        final start = tester.getCenter(_findPadTileInGrid('Sword Clash'));
        final end = tester.getCenter(_findPadTileInGrid('Battle Drums'));

        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 50));
        const steps = 6;
        for (var i = 1; i <= steps; i++) {
          await gesture.moveTo(Offset.lerp(start, end, i / steps)!);
          await tester.pump(const Duration(milliseconds: 50));
        }
        await gesture.up();
        await tester.pumpAndSettle();

        final persisted = await repository.load();
        final combatPads =
            persisted.pads
                .where((pad) => pad.folderId == 'folder_combat')
                .toList()
              ..sort((a, b) => a.order.compareTo(b.order));

        expect(combatPads.map((p) => p.label).toList(), <String>[
          'Fireball',
          'Battle Drums',
          'Sword Clash',
        ]);
        expect(combatPads.map((p) => p.order).toList(), <int>[0, 1, 2]);
      },
    );

    testWidgets(
      'deleting a currently playing pad removes it from board and stops its active audio handle',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        // Start Battle Drums playing in Play Mode.
        await tester.tap(_findPadTileInGrid('Battle Drums'));
        await tester.pump();
        fakeClock.advance(const Duration(milliseconds: 600));
        await tester.pump();

        expect(fakeEngine.playedHandles, isNotEmpty);
        final drumsHandle = fakeEngine.playedHandles.last;
        expect(fakeEngine.activeHandles, contains(drumsHandle));

        // Enter Edit Mode and open Battle Drums editor.
        await tester.tap(find.byKey(const Key('edit_mode_toggle')));
        await tester.pumpAndSettle();
        await tester.tap(_findPadTileInGrid('Battle Drums'));
        await tester.pumpAndSettle();

        // Tap Delete and confirm.
        await _scrollIntoViewAndTap(
          tester,
          find.byKey(const Key('pad_editor_delete')),
        );
        if (find.byType(AlertDialog).evaluate().isNotEmpty) {
          await tester.tap(
            _findDialogConfirmButton(
              primaryKey: const Key('confirm_delete_pad'),
              fallbackLabels: const <String>['Delete', 'Confirm'],
            ),
          );
          await tester.pumpAndSettle();
        }

        // Advance clock past fade-out window so smooth stop completes.
        fakeClock.advance(const Duration(milliseconds: 1100));
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(GridView),
            matching: find.text('Battle Drums'),
          ),
          findsNothing,
        );
        final persisted = await repository.load();
        expect(
          persisted.pads.any((pad) => pad.id == 'pad_battle_drums'),
          isFalse,
        );
        expect(fakeEngine.stoppedHandles, contains(drumsHandle));
        expect(fakeEngine.activeHandles, isEmpty);
      },
    );
  });

  group('Edit Mode accessibility', () {
    testWidgets(
      'renders cleanly without overflow on phone 360x740 at 2.0x text scale and edit_mode_toggle meets >= 48dp touch target',
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
          final fakeEngine = FakeAudioEngine();
          final fakeClock = FakeClock();
          final repository = InMemoryLibraryRepository();

          await _pumpAuraBoard(
            tester,
            audioEngine: fakeEngine,
            clock: fakeClock,
            repository: repository,
          );

          expect(
            MediaQuery.textScalerOf(
              tester.element(find.byType(Scaffold).first),
            ).scale(14.0),
            closeTo(28.0, 0.01),
          );

          final toggle = find.byKey(const Key('edit_mode_toggle'));
          expect(toggle, findsOneWidget);
          final toggleSize = tester.getSize(toggle);
          expect(
            toggleSize.width,
            greaterThanOrEqualTo(48.0),
            reason: 'edit_mode_toggle width must be >= 48dp',
          );
          expect(
            toggleSize.height,
            greaterThanOrEqualTo(48.0),
            reason: 'edit_mode_toggle height must be >= 48dp',
          );

          // Enter Edit Mode at 360x740 with 2.0x text scaling.
          await tester.tap(toggle);
          await tester.pumpAndSettle();

          final addFolder = find.byKey(const Key('add_folder_button'));
          final manageFolders = find.byKey(const Key('manage_folders_button'));
          expect(addFolder, findsOneWidget);
          expect(manageFolders, findsOneWidget);

          expect(tester.getSize(addFolder).width, greaterThanOrEqualTo(48.0));
          expect(tester.getSize(addFolder).height, greaterThanOrEqualTo(48.0));
          expect(
            tester.getSize(manageFolders).width,
            greaterThanOrEqualTo(48.0),
          );
          expect(
            tester.getSize(manageFolders).height,
            greaterThanOrEqualTo(48.0),
          );

          // Open Pad Editor at 360x740 & 2.0x text scale to verify zero overflow.
          final swordTile = _findPadTileInGrid('Sword Clash');
          await tester.ensureVisible(swordTile);
          await tester.pump();
          await tester.tap(swordTile);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('pad_editor_folder')), findsOneWidget);
          Navigator.of(
            tester.element(find.byKey(const Key('pad_editor_save'))),
          ).pop();
          await tester.pumpAndSettle();

          // Open Folder Manager & Delete Folder dialog (with DropdownButtonFormField)
          // at 360x740 & 2.0x text scale to verify zero horizontal overflow.
          await tester.tap(manageFolders);
          await tester.pumpAndSettle();
          final combatFolder = (await repository.load()).folders.firstWhere(
            (f) => f.name == 'Combat',
          );
          final deleteCombatBtn = find.byKey(
            Key('delete_folder_${combatFolder.id}'),
          );
          await tester.ensureVisible(deleteCombatBtn);
          await tester.pump();
          await tester.tap(deleteCombatBtn);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('delete_folder_move_target')),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();

          expect(flutterErrors, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );
  });
}
