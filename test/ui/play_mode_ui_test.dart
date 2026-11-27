import 'package:auraboard/app.dart';
import 'package:auraboard/data/demo_board.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';

/// Pumps [AuraBoardApp] inside a [ProviderScope] wired with deterministic
/// fakes and waits for the initial library load.
Future<void> _pumpAuraBoard(
  WidgetTester tester, {
  required FakeAudioEngine audioEngine,
  required FakeClock clock,
  required InMemoryLibraryRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
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

/// Finds the pad tile container for [padLabel] inside the soundboard
/// [GridView].
Finder _findPadTileInGrid(String padLabel) {
  final labelInGrid = find.descendant(
    of: find.byType(GridView),
    matching: find.text(padLabel),
  );
  return find.ancestor(of: labelInGrid, matching: find.byType(Card)).first;
}

/// Matches a loop indicator icon (`Icons.repeat` / `Icons.loop`) or `Loop` text
/// badge inside [scope].
Finder _findLoopIndicatorIn(Finder scope) {
  return find.descendant(
    of: scope,
    matching: find.byWidgetPredicate((widget) {
      if (widget is Icon) {
        return widget.icon == Icons.repeat || widget.icon == Icons.loop;
      }
      if (widget is Text) {
        final data = widget.data ?? '';
        return RegExp(r'\bLoop\b', caseSensitive: false).hasMatch(data);
      }
      return false;
    }),
  );
}

/// Matches any of [icons] inside [scope].
Finder _findAnyIconIn(Finder scope, Set<IconData> icons) {
  return find.descendant(
    of: scope,
    matching: find.byWidgetPredicate(
      (widget) => widget is Icon && icons.contains(widget.icon),
    ),
  );
}

/// Finds the persistent `Stop All` button by key or visible label.
Finder _findStopAllButton() {
  final byKey = find.byKey(const Key('stop_all_button'));
  if (byKey.evaluate().isNotEmpty) {
    return byKey;
  }
  final byText = find.text('Stop All');
  if (byText.evaluate().isNotEmpty) {
    final buttonAncestor = find.ancestor(
      of: byText,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ButtonStyleButton ||
            widget is InkWell ||
            widget is IconButton,
      ),
    );
    if (buttonAncestor.evaluate().isNotEmpty) {
      return buttonAncestor.first;
    }
    return byText;
  }
  return byKey;
}

/// Finds the Master volume [Slider] by key.
Finder _findMasterVolumeSlider() {
  return find.byKey(const Key('master_volume_slider'));
}

/// Finds the per-item Stop button in the Now-Playing area.
Finder _findNowPlayingStopButton(String padId, String padLabel) {
  final byKey = find.byKey(Key('now_playing_stop_$padId'));
  if (byKey.evaluate().isNotEmpty) {
    return byKey;
  }
  final bySemantics = find.bySemanticsLabel(
    RegExp('Stop.*$padLabel', caseSensitive: false, dotAll: true),
  );
  if (bySemantics.evaluate().isNotEmpty) {
    return bySemantics.first;
  }
  return byKey;
}

/// Finds the per-item volume [Slider] in the Now-Playing area.
Finder _findNowPlayingVolumeSlider(String padId, String padLabel) {
  final byKey = find.byKey(Key('now_playing_volume_$padId'));
  if (byKey.evaluate().isNotEmpty) {
    return byKey;
  }
  final bySemantics = find.bySemanticsLabel(
    RegExp(
      '($padLabel.*volume|volume.*$padLabel)',
      caseSensitive: false,
      dotAll: true,
    ),
  );
  if (bySemantics.evaluate().isNotEmpty) {
    final nestedSlider = find.descendant(
      of: bySemantics.first,
      matching: find.byType(Slider),
    );
    if (nestedSlider.evaluate().isNotEmpty) {
      return nestedSlider.first;
    }
  }
  return byKey;
}

/// Finds the Settings entry button in the app bar.
Finder _findSettingsButton() {
  final byKey = find.byKey(const Key('settings_button'));
  if (byKey.evaluate().isNotEmpty) {
    return byKey;
  }
  final byIcon = find.byIcon(Icons.settings);
  if (byIcon.evaluate().isNotEmpty) {
    return byIcon;
  }
  final byTooltip = find.byTooltip('Settings');
  if (byTooltip.evaluate().isNotEmpty) {
    return byTooltip;
  }
  return find.bySemanticsLabel(RegExp('Settings', caseSensitive: false));
}

void main() {
  group('Unmistakable pad visual and semantic states', () {
    testWidgets(
      'music pad transitions idle, fading in, playing, fading out, and idle '
      'with distinct icons, text, loop indicator, and semantics',
      (WidgetTester tester) async {
        final semanticsHandle = tester.ensureSemantics();
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

          final padTile = _findPadTileInGrid('Battle Drums');
          expect(padTile, findsOneWidget);

          // Idle: displays loop indicator and Idle semantics.
          expect(_findLoopIndicatorIn(padTile), findsWidgets);
          expect(
            find.bySemanticsLabel(
              RegExp(r'Battle Drums.*Idle', caseSensitive: false, dotAll: true),
            ),
            findsOneWidget,
          );

          // Tap -> Fading in: distinct fading-in icon, visible text, semantics.
          await tester.tap(padTile);
          await tester.pump();

          expect(
            _findAnyIconIn(padTile, const <IconData>{
              Icons.trending_up,
              Icons.north_east,
            }),
            findsWidgets,
          );
          expect(
            find.descendant(of: padTile, matching: find.text('Fading in')),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              RegExp(
                r'Battle Drums.*Fading in',
                caseSensitive: false,
                dotAll: true,
              ),
            ),
            findsOneWidget,
          );

          // Advance clock past default 500ms fade-in -> Playing.
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();

          expect(
            _findAnyIconIn(padTile, const <IconData>{
              Icons.graphic_eq,
              Icons.volume_up,
            }),
            findsWidgets,
          );
          expect(
            find.descendant(of: padTile, matching: find.text('Playing')),
            findsOneWidget,
          );
          expect(_findLoopIndicatorIn(padTile), findsWidgets);
          // Visually distinct from Fading in.
          expect(
            _findAnyIconIn(padTile, const <IconData>{
              Icons.trending_up,
              Icons.north_east,
            }),
            findsNothing,
          );
          expect(
            find.descendant(of: padTile, matching: find.text('Fading in')),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(
              RegExp(
                r'Battle Drums.*Playing',
                caseSensitive: false,
                dotAll: true,
              ),
            ),
            findsOneWidget,
          );

          // Tap again -> Fading out: distinct fading-out icon, text, semantics.
          await tester.tap(padTile);
          await tester.pump();

          expect(
            _findAnyIconIn(padTile, const <IconData>{
              Icons.trending_down,
              Icons.south_east,
            }),
            findsWidgets,
          );
          expect(
            find.descendant(of: padTile, matching: find.text('Fading out')),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              RegExp(
                r'Battle Drums.*Fading out',
                caseSensitive: false,
                dotAll: true,
              ),
            ),
            findsOneWidget,
          );

          // Advance clock past default 1000ms fade-out -> returns to Idle.
          fakeClock.advance(const Duration(milliseconds: 1100));
          await tester.pump();

          expect(
            find.bySemanticsLabel(
              RegExp(r'Battle Drums.*Idle', caseSensitive: false, dotAll: true),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: padTile, matching: find.text('Fading out')),
            findsNothing,
          );
          expect(_findLoopIndicatorIn(padTile), findsWidgets);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets('effect pad enters Playing immediately and renders determinate '
        'LinearProgressIndicator that advances with FakeClock', (
      WidgetTester tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();
      try {
        final fakeEngine = FakeAudioEngine(
          defaultDuration: const Duration(seconds: 2),
        );
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        final swordTile = _findPadTileInGrid('Sword Clash');
        expect(swordTile, findsOneWidget);

        await tester.tap(swordTile);
        await tester.pump();

        expect(
          find.bySemanticsLabel(
            RegExp(r'Sword Clash.*Playing', caseSensitive: false, dotAll: true),
          ),
          findsOneWidget,
        );

        final progressFinder = find.descendant(
          of: swordTile,
          matching: find.byType(LinearProgressIndicator),
        );
        expect(progressFinder, findsOneWidget);

        // Advance clock halfway through the 2s effect.
        fakeClock.advance(const Duration(seconds: 1));
        await tester.pump();

        final indicator = tester.widget<LinearProgressIndicator>(
          progressFinder,
        );
        expect(indicator.value, isNotNull);
        expect(indicator.value!, greaterThan(0.0));
        expect(indicator.value!, lessThan(1.0));

        // Advance past completion -> returns to Idle without progress bar.
        fakeClock.advance(const Duration(seconds: 2));
        await tester.pump();

        expect(
          find.bySemanticsLabel(
            RegExp(r'Sword Clash.*Idle', caseSensitive: false, dotAll: true),
          ),
          findsOneWidget,
        );
        expect(progressFinder, findsNothing);
      } finally {
        semanticsHandle.dispose();
      }
    });

    testWidgets(
      'effect pad with RetriggerMode.layer shows layer count badge when '
      'tapped twice',
      (WidgetTester tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fakeEngine = FakeAudioEngine(
            defaultDuration: const Duration(seconds: 2),
          );
          final fakeClock = FakeClock();
          final repository = InMemoryLibraryRepository();
          final demo = createDemoLibrary();
          final layeredLibrary = demo.copyWith(
            pads: demo.pads
                .map(
                  (pad) => pad.id == 'pad_sword_clash'
                      ? pad.copyWith(retriggerMode: RetriggerMode.layer)
                      : pad,
                )
                .toList(),
          );
          await repository.save(layeredLibrary);

          await _pumpAuraBoard(
            tester,
            audioEngine: fakeEngine,
            clock: fakeClock,
            repository: repository,
          );

          final swordTile = _findPadTileInGrid('Sword Clash');
          await tester.tap(swordTile);
          await tester.pump();

          fakeClock.advance(const Duration(milliseconds: 200));
          await tester.pump();

          await tester.tap(swordTile);
          await tester.pump();

          expect(fakeEngine.activeHandles, hasLength(2));
          expect(
            find.descendant(
              of: swordTile,
              matching: find.textContaining(
                RegExp(r'[×x]\s*2', caseSensitive: false),
              ),
            ),
            findsOneWidget,
          );

          // Advance past both layers completing.
          fakeClock.advance(const Duration(seconds: 3));
          await tester.pump();
          expect(
            find.descendant(
              of: swordTile,
              matching: find.textContaining(
                RegExp(r'[×x]\s*2', caseSensitive: false),
              ),
            ),
            findsNothing,
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'error pad displays unmistakable error icon, error text, and semantics '
      'without crashing when audio fails to load',
      (WidgetTester tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fakeEngine = FakeAudioEngine(
            failingPaths: <String>{'assets/demo_audio/sword_clash.wav'},
          );
          final fakeClock = FakeClock();
          final repository = InMemoryLibraryRepository();

          await _pumpAuraBoard(
            tester,
            audioEngine: fakeEngine,
            clock: fakeClock,
            repository: repository,
          );

          final swordTile = _findPadTileInGrid('Sword Clash');
          await tester.tap(swordTile);
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(
            find.descendant(
              of: swordTile,
              matching: find.byIcon(Icons.error_outline),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: swordTile,
              matching: find.textContaining(
                RegExp(r'Error|Missing|Failed', caseSensitive: false),
              ),
            ),
            findsWidgets,
          );
          expect(
            find.bySemanticsLabel(
              RegExp(r'Sword Clash.*Error', caseSensitive: false, dotAll: true),
            ),
            findsOneWidget,
          );
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  });

  group('Persistent now-playing area', () {
    testWidgets(
      'is always reachable at the bottom when idle with Stop All and Master '
      'volume slider adjusting FakeAudioEngine.masterVolume',
      (WidgetTester tester) async {
        final semanticsHandle = tester.ensureSemantics();
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

          final stopAll = _findStopAllButton();
          final masterSlider = _findMasterVolumeSlider();

          expect(stopAll, findsOneWidget);
          expect(masterSlider, findsOneWidget);

          // Positioned below the pad grid in the bottom area of the screen.
          final gridTop = tester.getTopLeft(find.byType(GridView)).dy;
          expect(tester.getTopLeft(stopAll).dy, greaterThan(gridTop));
          expect(tester.getTopLeft(masterSlider).dy, greaterThan(gridTop));

          // Adjusting the Master volume slider updates fakeEngine.masterVolume.
          expect(fakeEngine.masterVolume, 1.0);
          await tester.tap(masterSlider);
          await tester.pump();

          expect(fakeEngine.masterVolume, lessThan(0.9));
          expect(fakeEngine.masterVolume, greaterThan(0.1));
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'keeps multiple active sounds visible across folder switches with '
      'per-item stop and volume controls',
      (WidgetTester tester) async {
        final semanticsHandle = tester.ensureSemantics();
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

          // Start Battle Drums in Combat folder.
          await tester.tap(_findPadTileInGrid('Battle Drums'));
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();
          final drumsHandle = fakeEngine.playedHandles.last;

          // Switch to Tavern folder and start Steady Rain.
          await tester.tap(find.text('Tavern'));
          await tester.pump();
          await tester.tap(_findPadTileInGrid('Steady Rain'));
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();
          final rainHandle = fakeEngine.playedHandles.last;

          // Switch to Dungeon folder — neither active pad belongs to Dungeon.
          await tester.tap(find.text('Dungeon'));
          await tester.pump();

          expect(
            find.descendant(
              of: find.byType(GridView),
              matching: find.text('Dungeon Wind'),
            ),
            findsOneWidget,
          );

          // Both active sounds remain visible in the Now-Playing area.
          expect(find.text('Battle Drums'), findsOneWidget);
          expect(find.text('Steady Rain'), findsOneWidget);

          // Adjust Steady Rain's per-item volume slider.
          final rainSlider = _findNowPlayingVolumeSlider(
            'pad_steady_rain',
            'Steady Rain',
          );
          expect(rainSlider, findsOneWidget);
          await tester.tap(rainSlider);
          await tester.pump();

          expect(fakeEngine.volumeFor(rainHandle), isNotNull);
          expect(fakeEngine.volumeFor(rainHandle)!, lessThan(0.9));
          expect(fakeEngine.volumeFor(rainHandle)!, greaterThan(0.1));

          // Stop only Battle Drums via its per-item Stop button.
          final stopDrums = _findNowPlayingStopButton(
            'pad_battle_drums',
            'Battle Drums',
          );
          expect(stopDrums, findsOneWidget);
          await tester.tap(stopDrums);
          await tester.pump();

          // Smooth fade-out initiated, not hard-cut.
          expect(fakeEngine.stoppedHandles, isNot(contains(drumsHandle)));
          expect(
            fakeEngine.fades.any(
              (fade) =>
                  fade.handle == drumsHandle &&
                  fade.targetVolume == 0.0 &&
                  fade.duration > Duration.zero,
            ),
            isTrue,
          );

          // Complete Battle Drums fade-out; Steady Rain keeps playing.
          fakeClock.advance(const Duration(milliseconds: 1100));
          await tester.pump();

          expect(fakeEngine.stoppedHandles, contains(drumsHandle));
          expect(find.text('Battle Drums'), findsNothing);
          expect(find.text('Steady Rain'), findsOneWidget);
          expect(fakeEngine.activeHandles, contains(rainHandle));
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'Stop All fades all active sounds smoothly and clears active handles '
      'after fade-out completes',
      (WidgetTester tester) async {
        final semanticsHandle = tester.ensureSemantics();
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

          // Start Battle Drums (Combat) and Steady Rain (Tavern).
          await tester.tap(_findPadTileInGrid('Battle Drums'));
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();
          final drumsHandle = fakeEngine.playedHandles.last;

          await tester.tap(find.text('Tavern'));
          await tester.pump();
          await tester.tap(_findPadTileInGrid('Steady Rain'));
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();
          final rainHandle = fakeEngine.playedHandles.last;

          // Switch to Dungeon so active labels only come from Now Playing.
          await tester.tap(find.text('Dungeon'));
          await tester.pump();

          expect(find.text('Battle Drums'), findsOneWidget);
          expect(find.text('Steady Rain'), findsOneWidget);

          final stopAll = _findStopAllButton();
          expect(stopAll, findsOneWidget);
          await tester.tap(stopAll);
          await tester.pump();

          // Both voices transition to Fading out instead of hard stopping.
          final container = ProviderScope.containerOf(
            tester.element(find.byType(AuraBoardApp)),
          );
          final playbackState = container.read(playbackControllerProvider);
          expect(
            playbackState.phaseForPad('pad_battle_drums'),
            PadPlaybackPhase.fadingOut,
          );
          expect(
            playbackState.phaseForPad('pad_steady_rain'),
            PadPlaybackPhase.fadingOut,
          );
          expect(fakeEngine.stoppedHandles, isNot(contains(drumsHandle)));
          expect(fakeEngine.stoppedHandles, isNot(contains(rainHandle)));

          // Advance past fade-out -> all handles stopped & active list empty.
          fakeClock.advance(const Duration(milliseconds: 1100));
          await tester.pump();

          expect(fakeEngine.stoppedHandles, contains(drumsHandle));
          expect(fakeEngine.stoppedHandles, contains(rainHandle));
          expect(fakeEngine.activeHandles, isEmpty);
          expect(find.text('Battle Drums'), findsNothing);
          expect(find.text('Steady Rain'), findsNothing);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  });

  group('Responsive grid, density, theme toggle, and accessibility', () {
    testWidgets(
      'switching GridDensity in settings updates BoardSettings and renders '
      'cleanly without overflow',
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

        final container = ProviderScope.containerOf(
          tester.element(find.byType(AuraBoardApp)),
        );
        expect(
          container.read(libraryControllerProvider).requireValue.settings,
          isA<BoardSettings>().having(
            (s) => s.gridDensity,
            'gridDensity',
            GridDensity.standard,
          ),
        );

        final settingsButton = _findSettingsButton();
        expect(settingsButton, findsOneWidget);
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();

        // Switch to Compact density.
        final compactOption = find.text('Compact');
        expect(compactOption, findsOneWidget);
        await tester.tap(compactOption);
        await tester.pumpAndSettle();

        expect(
          container
              .read(libraryControllerProvider)
              .requireValue
              .settings
              .gridDensity,
          GridDensity.compact,
        );

        // Switch to Comfortable density.
        final comfortableOption = find.text('Comfortable');
        expect(comfortableOption, findsOneWidget);
        await tester.tap(comfortableOption);
        await tester.pumpAndSettle();

        expect(
          container
              .read(libraryControllerProvider)
              .requireValue
              .settings
              .gridDensity,
          GridDensity.comfortable,
        );

        // Close settings if pushed as a route or modal sheet.
        final navigator = Navigator.of(
          tester.element(find.byType(Scaffold).last),
        );
        if (navigator.canPop()) {
          navigator.pop();
          await tester.pumpAndSettle();
        }

        expect(find.byType(GridView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'defaults to Dark theme and switches to Light theme from settings',
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

        // Default theme is Dark.
        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.themeMode, ThemeMode.dark);
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );

        // Open Settings and switch to Light theme.
        final settingsButton = _findSettingsButton();
        expect(settingsButton, findsOneWidget);
        await tester.tap(settingsButton);
        await tester.pumpAndSettle();

        final lightOption = find.text('Light');
        expect(lightOption, findsOneWidget);
        await tester.tap(lightOption);
        await tester.pumpAndSettle();

        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.light,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AuraBoardApp)),
        );
        expect(
          container
              .read(libraryControllerProvider)
              .requireValue
              .settings
              .themeMode,
          AppThemeMode.light,
        );
      },
    );

    testWidgets(
      'renders without RenderFlex overflow on phone portrait 360x740 at '
      '2.0x text scale with active sounds in Now Playing',
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
            ),
            const TextScaler.linear(2.0),
          );

          // Activate two sounds across folders to stress Now Playing at 2.0x.
          final drumsTile = _findPadTileInGrid('Battle Drums');
          await tester.ensureVisible(drumsTile);
          await tester.pump();
          await tester.tap(drumsTile);
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();

          await tester.tap(find.text('Tavern'));
          await tester.pump();
          final rainTile = _findPadTileInGrid('Steady Rain');
          await tester.ensureVisible(rainTile);
          await tester.pump();
          await tester.tap(rainTile);
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();

          expect(_findStopAllButton(), findsOneWidget);
          expect(_findMasterVolumeSlider(), findsOneWidget);
          expect(flutterErrors, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );

    testWidgets(
      'renders without RenderFlex overflow on phone landscape 800x360 at '
      '1.5x text scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 360);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
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
            ),
            const TextScaler.linear(1.5),
          );

          final drumsTile = _findPadTileInGrid('Battle Drums');
          await tester.ensureVisible(drumsTile);
          await tester.pump();
          await tester.tap(drumsTile);
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();

          expect(_findStopAllButton(), findsOneWidget);
          expect(_findMasterVolumeSlider(), findsOneWidget);
          expect(flutterErrors, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );

    testWidgets(
      'renders without RenderFlex overflow on tablet landscape 1280x800 at '
      '2.0x text scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
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
            ),
            const TextScaler.linear(2.0),
          );

          final drumsTile = _findPadTileInGrid('Battle Drums');
          await tester.ensureVisible(drumsTile);
          await tester.pump();
          await tester.tap(drumsTile);
          await tester.pump();
          fakeClock.advance(const Duration(milliseconds: 600));
          await tester.pump();

          expect(_findStopAllButton(), findsOneWidget);
          expect(_findMasterVolumeSlider(), findsOneWidget);
          expect(flutterErrors, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          FlutterError.onError = previousOnError;
        }
      },
    );

    testWidgets(
      'interactive pad tiles, Stop All button, and folder chips meet >= 48dp '
      'touch target size',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
        );

        // Audit interactive pad tiles.
        for (final label in const <String>[
          'Sword Clash',
          'Fireball',
          'Battle Drums',
        ]) {
          final tileSize = tester.getSize(_findPadTileInGrid(label));
          expect(
            tileSize.width,
            greaterThanOrEqualTo(48.0),
            reason: 'Pad "$label" width must be >= 48dp',
          );
          expect(
            tileSize.height,
            greaterThanOrEqualTo(48.0),
            reason: 'Pad "$label" height must be >= 48dp',
          );
        }

        // Audit Stop All button.
        final stopAll = _findStopAllButton();
        expect(stopAll, findsOneWidget);
        final stopAllSize = tester.getSize(stopAll);
        expect(
          stopAllSize.width,
          greaterThanOrEqualTo(48.0),
          reason: 'Stop All button width must be >= 48dp',
        );
        expect(
          stopAllSize.height,
          greaterThanOrEqualTo(48.0),
          reason: 'Stop All button height must be >= 48dp',
        );

        // Audit folder chips.
        for (final folderName in const <String>[
          'Combat',
          'Tavern',
          'Dungeon',
        ]) {
          final chipFinder = find
              .ancestor(
                of: find.text(folderName),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is ChoiceChip ||
                      widget is FilterChip ||
                      widget is RawChip ||
                      widget is ButtonStyleButton ||
                      widget is InkWell,
                ),
              )
              .first;
          final chipSize = tester.getSize(chipFinder);
          expect(
            chipSize.width,
            greaterThanOrEqualTo(48.0),
            reason: 'Folder chip "$folderName" width must be >= 48dp',
          );
          expect(
            chipSize.height,
            greaterThanOrEqualTo(48.0),
            reason: 'Folder chip "$folderName" height must be >= 48dp',
          );
        }
      },
    );
  });
}
