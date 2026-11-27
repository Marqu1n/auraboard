import 'package:auraboard/app.dart';
import 'package:auraboard/audio/session_resilience.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';
import '../helpers/fake_session_gateways.dart';

Future<void> _pumpAuraBoard(
  WidgetTester tester, {
  required FakeAudioEngine audioEngine,
  required FakeClock clock,
  required LibraryRepository repository,
  required FakeAudioFocusGateway audioFocusGateway,
  required FakeBackgroundServiceGateway backgroundServiceGateway,
  required FakeWakelockGateway wakelockGateway,
  Key? scopeKey,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      key: scopeKey,
      overrides: [
        audioEngineProvider.overrideWithValue(audioEngine),
        clockProvider.overrideWithValue(clock),
        libraryRepositoryProvider.overrideWithValue(repository),
        audioFocusGatewayProvider.overrideWithValue(audioFocusGateway),
        backgroundServiceGatewayProvider.overrideWithValue(
          backgroundServiceGateway,
        ),
        wakelockGatewayProvider.overrideWithValue(wakelockGateway),
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

bool _readSwitchValue(WidgetTester tester, Finder switchFinder) {
  final widget = tester.widget(switchFinder);
  if (widget is SwitchListTile) {
    return widget.value;
  }
  if (widget is Switch) {
    return widget.value;
  }
  final descendantSwitch = find.descendant(
    of: switchFinder,
    matching: find.byType(Switch),
  );
  return tester.widget<Switch>(descendantSwitch).value;
}

void main() {
  group('Keep-screen-awake settings and cold-start safety', () {
    testWidgets(
      'Settings shows keep_screen_awake_switch (>= 48dp height), off by '
      'default, toggles WakelockGateway and persists to LibraryRepository',
      (WidgetTester tester) async {
        final fakeEngine = FakeAudioEngine();
        final fakeClock = FakeClock();
        final repository = InMemoryLibraryRepository();
        final audioFocus = FakeAudioFocusGateway();
        final backgroundService = FakeBackgroundServiceGateway();
        final wakelock = FakeWakelockGateway();
        addTearDown(audioFocus.closeStream);

        await _pumpAuraBoard(
          tester,
          audioEngine: fakeEngine,
          clock: fakeClock,
          repository: repository,
          audioFocusGateway: audioFocus,
          backgroundServiceGateway: backgroundService,
          wakelockGateway: wakelock,
        );

        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        final keepAwakeSwitch = find.byKey(
          const Key('keep_screen_awake_switch'),
        );
        await tester.ensureVisible(keepAwakeSwitch);
        await tester.pumpAndSettle();

        expect(keepAwakeSwitch, findsOneWidget);
        expect(
          tester.getSize(keepAwakeSwitch).height,
          greaterThanOrEqualTo(48.0),
        );
        expect(_readSwitchValue(tester, keepAwakeSwitch), isFalse);

        // Toggle ON -> enables wakelock and persists setting.
        await tester.tap(keepAwakeSwitch);
        await tester.pumpAndSettle();

        expect(_readSwitchValue(tester, keepAwakeSwitch), isTrue);
        expect(wakelock.lastEnabled, isTrue);

        final persisted = await repository.load();
        expect(persisted.settings.keepScreenAwake, isTrue);
      },
    );

    testWidgets(
      'cold restart restores keepScreenAwake == true via WakelockGateway '
      'and does NOT auto-resume playback',
      (WidgetTester tester) async {
        final sharedRepository = InMemoryLibraryRepository();

        // First app session: enable Keep Screen Awake and start Battle Drums.
        final engine1 = FakeAudioEngine();
        final clock1 = FakeClock();
        final audioFocus1 = FakeAudioFocusGateway();
        final backgroundService1 = FakeBackgroundServiceGateway();
        final wakelock1 = FakeWakelockGateway();
        addTearDown(audioFocus1.closeStream);

        await _pumpAuraBoard(
          tester,
          scopeKey: const ValueKey<String>('cold_start_session_1'),
          audioEngine: engine1,
          clock: clock1,
          repository: sharedRepository,
          audioFocusGateway: audioFocus1,
          backgroundServiceGateway: backgroundService1,
          wakelockGateway: wakelock1,
        );

        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        final keepAwakeSwitch1 = find.byKey(
          const Key('keep_screen_awake_switch'),
        );
        await tester.ensureVisible(keepAwakeSwitch1);
        await tester.pumpAndSettle();
        await tester.tap(keepAwakeSwitch1);
        await tester.pumpAndSettle();

        expect(
          (await sharedRepository.load()).settings.keepScreenAwake,
          isTrue,
        );

        // Close Settings and start playback so audio was active before kill.
        Navigator.of(tester.element(keepAwakeSwitch1)).pop();
        await tester.pumpAndSettle();

        await tester.tap(_findPadTileInGrid('Battle Drums'));
        await tester.pump();
        clock1.advance(const Duration(milliseconds: 600));
        await tester.pump();
        expect(engine1.activeHandles, hasLength(1));

        // Second app session (simulated cold restart after OS kill).
        final engine2 = FakeAudioEngine();
        final clock2 = FakeClock();
        final audioFocus2 = FakeAudioFocusGateway();
        final backgroundService2 = FakeBackgroundServiceGateway();
        final wakelock2 = FakeWakelockGateway();
        addTearDown(audioFocus2.closeStream);

        await _pumpAuraBoard(
          tester,
          scopeKey: const ValueKey<String>('cold_start_session_2'),
          audioEngine: engine2,
          clock: clock2,
          repository: sharedRepository,
          audioFocusGateway: audioFocus2,
          backgroundServiceGateway: backgroundService2,
          wakelockGateway: wakelock2,
        );

        // Restores keepScreenAwake == true and applies wakelock on startup.
        expect(wakelock2.recordedStates, isNotEmpty);
        expect(wakelock2.lastEnabled, isTrue);

        // Cold-start safety: playback MUST NOT auto-resume.
        expect(engine2.playedHandles, isEmpty);
        expect(engine2.activeHandles, isEmpty);

        // Verify persisted toggle state in Settings after restart.
        await tester.tap(find.byKey(const Key('settings_button')));
        await tester.pumpAndSettle();

        final keepAwakeSwitch2 = find.byKey(
          const Key('keep_screen_awake_switch'),
        );
        await tester.ensureVisible(keepAwakeSwitch2);
        await tester.pumpAndSettle();
        expect(_readSwitchValue(tester, keepAwakeSwitch2), isTrue);
      },
    );
  });

  group('Audio focus & phone call interruption resilience in UI', () {
    testWidgets('phone call interruption pauses and resumes Battle Drums while '
        'notification duck does not pause or stop playback', (
      WidgetTester tester,
    ) async {
      final fakeEngine = FakeAudioEngine();
      final fakeClock = FakeClock();
      final repository = InMemoryLibraryRepository();
      final audioFocus = FakeAudioFocusGateway();
      final backgroundService = FakeBackgroundServiceGateway();
      final wakelock = FakeWakelockGateway();
      addTearDown(audioFocus.closeStream);

      await _pumpAuraBoard(
        tester,
        audioEngine: fakeEngine,
        clock: fakeClock,
        repository: repository,
        audioFocusGateway: audioFocus,
        backgroundServiceGateway: backgroundService,
        wakelockGateway: wakelock,
      );

      // Start Battle Drums and complete fade-in.
      await tester.tap(_findPadTileInGrid('Battle Drums'));
      await tester.pump();
      fakeClock.advance(const Duration(milliseconds: 600));
      await tester.pump();

      expect(fakeEngine.activeHandles, hasLength(1));
      expect(fakeEngine.pausedCount, 0);
      expect(fakeEngine.resumedCount, 0);

      // Notification sound (duck) must NOT pause or stop playback.
      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: true,
          kind: AudioInterruptionKind.duck,
        ),
      );
      await tester.pump();
      await tester.pump();
      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: false,
          kind: AudioInterruptionKind.duck,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(fakeEngine.pausedCount, 0);
      expect(fakeEngine.resumedCount, 0);
      expect(fakeEngine.stoppedHandles, isEmpty);
      expect(fakeEngine.activeHandles, hasLength(1));

      // Incoming phone call (pause) pauses active playback.
      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: true,
          kind: AudioInterruptionKind.pause,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(fakeEngine.pausedCount, 1);
      expect(fakeEngine.resumedCount, 0);
      expect(fakeEngine.isPaused, isTrue);

      // Ending phone call resumes active playback.
      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: false,
          kind: AudioInterruptionKind.pause,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(fakeEngine.pausedCount, 1);
      expect(fakeEngine.resumedCount, 1);
      expect(fakeEngine.isPaused, isFalse);
      expect(fakeEngine.activeHandles, hasLength(1));
    });
  });
}
