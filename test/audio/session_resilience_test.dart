import 'package:auraboard/audio/session_resilience.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/domain/playback_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_session_gateways.dart';

const SoundPad _battleDrumsPad = SoundPad(
  id: 'pad_battle_drums',
  folderId: 'folder_combat',
  label: 'Battle Drums',
  colorValue: 0xFFB84A39,
  audioPath: 'assets/demo_audio/battle_drums.wav',
  isAsset: true,
  type: PadType.music,
  order: 0,
);

const SoundPad _steadyRainPad = SoundPad(
  id: 'pad_steady_rain',
  folderId: 'folder_tavern',
  label: 'Steady Rain',
  colorValue: 0xFF3E6D8C,
  audioPath: 'assets/demo_audio/steady_rain.wav',
  isAsset: true,
  type: PadType.ambience,
  order: 1,
);

const SoundPad _brokenHornPad = SoundPad(
  id: 'pad_broken_horn',
  folderId: 'folder_combat',
  label: 'Broken Horn',
  colorValue: 0xFF6A4C93,
  audioPath: '/private/audio/broken_horn.wav',
  isAsset: false,
  type: PadType.effect,
  order: 2,
);

final Map<String, SoundPad> _testPadsById = <String, SoundPad>{
  _battleDrumsPad.id: _battleDrumsPad,
  _steadyRainPad.id: _steadyRainPad,
  _brokenHornPad.id: _brokenHornPad,
};

void main() {
  group('SessionResilienceCoordinator', () {
    test('initialize(keepScreenAwake: true) configures media audio session, '
        'subscribes to interruptions, and enables wakelock', () async {
      final audioFocus = FakeAudioFocusGateway();
      final backgroundService = FakeBackgroundServiceGateway();
      final wakelock = FakeWakelockGateway();
      addTearDown(audioFocus.closeStream);

      final coordinator = SessionResilienceCoordinator(
        audioFocusGateway: audioFocus,
        backgroundServiceGateway: backgroundService,
        wakelockGateway: wakelock,
        onPauseForInterruption: () async {},
        onResumeAfterInterruption: () async {},
      );
      addTearDown(coordinator.dispose);

      await coordinator.initialize(keepScreenAwake: true);

      expect(audioFocus.configureCount, 1);
      expect(audioFocus.hasInterruptionListener, isTrue);
      expect(wakelock.recordedStates, <bool>[true]);
    });

    test('initialize(keepScreenAwake: false) configures media audio session, '
        'subscribes to interruptions, and disables wakelock', () async {
      final audioFocus = FakeAudioFocusGateway();
      final backgroundService = FakeBackgroundServiceGateway();
      final wakelock = FakeWakelockGateway();
      addTearDown(audioFocus.closeStream);

      final coordinator = SessionResilienceCoordinator(
        audioFocusGateway: audioFocus,
        backgroundServiceGateway: backgroundService,
        wakelockGateway: wakelock,
        onPauseForInterruption: () async {},
        onResumeAfterInterruption: () async {},
      );
      addTearDown(coordinator.dispose);

      await coordinator.initialize(keepScreenAwake: false);

      expect(audioFocus.configureCount, 1);
      expect(audioFocus.hasInterruptionListener, isTrue);
      expect(wakelock.recordedStates, <bool>[false]);
    });

    test('notification duck interruption (AudioInterruptionKind.duck) does not '
        'pause or stop playback', () async {
      final audioFocus = FakeAudioFocusGateway();
      final backgroundService = FakeBackgroundServiceGateway();
      final wakelock = FakeWakelockGateway();
      addTearDown(audioFocus.closeStream);

      var pauseCount = 0;
      var resumeCount = 0;

      final coordinator = SessionResilienceCoordinator(
        audioFocusGateway: audioFocus,
        backgroundServiceGateway: backgroundService,
        wakelockGateway: wakelock,
        onPauseForInterruption: () async => pauseCount += 1,
        onResumeAfterInterruption: () async => resumeCount += 1,
      );
      addTearDown(coordinator.dispose);

      await coordinator.initialize(keepScreenAwake: false);

      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: true,
          kind: AudioInterruptionKind.duck,
        ),
      );
      await pumpEventQueue();

      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: false,
          kind: AudioInterruptionKind.duck,
        ),
      );
      await pumpEventQueue();

      expect(pauseCount, 0);
      expect(resumeCount, 0);
    });

    test('phone call interruption (AudioInterruptionKind.pause) pauses once on '
        'begin and resumes once on end', () async {
      final audioFocus = FakeAudioFocusGateway();
      final backgroundService = FakeBackgroundServiceGateway();
      final wakelock = FakeWakelockGateway();
      addTearDown(audioFocus.closeStream);

      var pauseCount = 0;
      var resumeCount = 0;

      final coordinator = SessionResilienceCoordinator(
        audioFocusGateway: audioFocus,
        backgroundServiceGateway: backgroundService,
        wakelockGateway: wakelock,
        onPauseForInterruption: () async => pauseCount += 1,
        onResumeAfterInterruption: () async => resumeCount += 1,
      );
      addTearDown(coordinator.dispose);

      await coordinator.initialize(keepScreenAwake: false);

      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: true,
          kind: AudioInterruptionKind.pause,
        ),
      );
      await pumpEventQueue();

      expect(pauseCount, 1);
      expect(resumeCount, 0);

      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: false,
          kind: AudioInterruptionKind.pause,
        ),
      );
      await pumpEventQueue();

      expect(pauseCount, 1);
      expect(resumeCount, 1);

      // A second end event after already resuming is a safe no-op.
      audioFocus.emitInterruption(
        const SessionInterruptionEvent(
          begin: false,
          kind: AudioInterruptionKind.pause,
        ),
      );
      await pumpEventQueue();

      expect(pauseCount, 1);
      expect(resumeCount, 1);
    });

    test(
      'receiving interruption end when not interrupted is a safe no-op',
      () async {
        final audioFocus = FakeAudioFocusGateway();
        final backgroundService = FakeBackgroundServiceGateway();
        final wakelock = FakeWakelockGateway();
        addTearDown(audioFocus.closeStream);

        var pauseCount = 0;
        var resumeCount = 0;

        final coordinator = SessionResilienceCoordinator(
          audioFocusGateway: audioFocus,
          backgroundServiceGateway: backgroundService,
          wakelockGateway: wakelock,
          onPauseForInterruption: () async => pauseCount += 1,
          onResumeAfterInterruption: () async => resumeCount += 1,
        );
        addTearDown(coordinator.dispose);

        await coordinator.initialize(keepScreenAwake: false);

        audioFocus.emitInterruption(
          const SessionInterruptionEvent(
            begin: false,
            kind: AudioInterruptionKind.pause,
          ),
        );
        await pumpEventQueue();

        expect(pauseCount, 0);
        expect(resumeCount, 0);
      },
    );

    test(
      'syncPlaybackState activates audio focus and updates foreground service '
      'when voices are active, and deactivates when idle or only errors exist',
      () async {
        final audioFocus = FakeAudioFocusGateway();
        final backgroundService = FakeBackgroundServiceGateway();
        final wakelock = FakeWakelockGateway();
        addTearDown(audioFocus.closeStream);

        final coordinator = SessionResilienceCoordinator(
          audioFocusGateway: audioFocus,
          backgroundServiceGateway: backgroundService,
          wakelockGateway: wakelock,
          onPauseForInterruption: () async {},
          onResumeAfterInterruption: () async {},
        );
        addTearDown(coordinator.dispose);

        await coordinator.initialize(keepScreenAwake: false);

        // Two active pads: Battle Drums + Steady Rain.
        final activeState = PlaybackState(
          activeByPad: <String, ActiveVoiceState>{
            _battleDrumsPad.id: const ActiveVoiceState(
              padId: 'pad_battle_drums',
              handle: 'h1',
              phase: PadPlaybackPhase.playing,
            ),
            _steadyRainPad.id: const ActiveVoiceState(
              padId: 'pad_steady_rain',
              handle: 'h2',
              phase: PadPlaybackPhase.playing,
            ),
          },
        );

        await coordinator.syncPlaybackState(
          activeState,
          padsById: _testPadsById,
        );

        expect(audioFocus.activeHistory, isNotEmpty);
        expect(audioFocus.activeHistory.last, isTrue);
        expect(backgroundService.updates, isNotEmpty);
        final activeUpdate = backgroundService.updates.last;
        expect(activeUpdate.isPlaying, isTrue);
        expect(activeUpdate.activeCount, 2);
        expect(activeUpdate.summaryTitle, isNotEmpty);
        expect(
          activeUpdate.summaryTitle.contains('Battle Drums') ||
              activeUpdate.summaryTitle.contains('Steady Rain'),
          isTrue,
        );

        // All voices return to idle.
        await coordinator.syncPlaybackState(
          const PlaybackState(),
          padsById: _testPadsById,
        );

        expect(audioFocus.activeHistory.last, isFalse);
        final idleUpdate = backgroundService.updates.last;
        expect(idleUpdate.isPlaying, isFalse);
        expect(idleUpdate.activeCount, 0);

        // Re-activate with one voice so error-only transition is verified.
        await coordinator.syncPlaybackState(
          PlaybackState(
            activeByPad: <String, ActiveVoiceState>{
              _battleDrumsPad.id: const ActiveVoiceState(
                padId: 'pad_battle_drums',
                handle: 'h3',
                phase: PadPlaybackPhase.fadingIn,
              ),
            },
          ),
          padsById: _testPadsById,
        );

        expect(audioFocus.activeHistory.last, isTrue);
        expect(backgroundService.updates.last.isPlaying, isTrue);
        expect(backgroundService.updates.last.activeCount, 1);
        expect(
          backgroundService.updates.last.summaryTitle,
          contains('Battle Drums'),
        );

        // Only an errored voice remains -> treated as inactive / idle.
        await coordinator.syncPlaybackState(
          PlaybackState(
            activeByPad: <String, ActiveVoiceState>{
              _brokenHornPad.id: const ActiveVoiceState(
                padId: 'pad_broken_horn',
                phase: PadPlaybackPhase.error,
                errorMessage: 'Corrupt audio',
              ),
            },
          ),
          padsById: _testPadsById,
        );

        expect(audioFocus.activeHistory.last, isFalse);
        final errorOnlyUpdate = backgroundService.updates.last;
        expect(errorOnlyUpdate.isPlaying, isFalse);
        expect(errorOnlyUpdate.activeCount, 0);
      },
    );

    test(
      'setKeepScreenAwake forwards enabled state to WakelockGateway',
      () async {
        final audioFocus = FakeAudioFocusGateway();
        final backgroundService = FakeBackgroundServiceGateway();
        final wakelock = FakeWakelockGateway();
        addTearDown(audioFocus.closeStream);

        final coordinator = SessionResilienceCoordinator(
          audioFocusGateway: audioFocus,
          backgroundServiceGateway: backgroundService,
          wakelockGateway: wakelock,
          onPauseForInterruption: () async {},
          onResumeAfterInterruption: () async {},
        );
        addTearDown(coordinator.dispose);

        await coordinator.initialize(keepScreenAwake: false);

        await coordinator.setKeepScreenAwake(true);
        expect(wakelock.lastEnabled, isTrue);

        await coordinator.setKeepScreenAwake(false);
        expect(wakelock.lastEnabled, isFalse);
        expect(wakelock.recordedStates, <bool>[false, true, false]);
      },
    );

    test(
      'dispose cancels interruption subscription, ignores subsequent events, '
      'and disposes gateways cleanly',
      () async {
        final audioFocus = FakeAudioFocusGateway();
        final backgroundService = FakeBackgroundServiceGateway();
        final wakelock = FakeWakelockGateway();
        addTearDown(audioFocus.closeStream);

        var pauseCount = 0;
        var resumeCount = 0;

        final coordinator = SessionResilienceCoordinator(
          audioFocusGateway: audioFocus,
          backgroundServiceGateway: backgroundService,
          wakelockGateway: wakelock,
          onPauseForInterruption: () async => pauseCount += 1,
          onResumeAfterInterruption: () async => resumeCount += 1,
        );

        await coordinator.initialize(keepScreenAwake: false);
        expect(audioFocus.hasInterruptionListener, isTrue);

        await coordinator.dispose();

        expect(audioFocus.hasInterruptionListener, isFalse);
        expect(audioFocus.isDisposed, isTrue);
        expect(backgroundService.isDisposed, isTrue);

        audioFocus.emitInterruption(
          const SessionInterruptionEvent(
            begin: true,
            kind: AudioInterruptionKind.pause,
          ),
        );
        audioFocus.emitInterruption(
          const SessionInterruptionEvent(
            begin: false,
            kind: AudioInterruptionKind.pause,
          ),
        );
        await pumpEventQueue();

        expect(pauseCount, 0);
        expect(resumeCount, 0);
      },
    );
  });
}
