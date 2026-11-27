import 'dart:async';

import 'package:auraboard/domain/models.dart';
import 'package:auraboard/domain/playback_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_audio_engine.dart';
import '../helpers/fake_clock.dart';

/// Extends [FakeAudioEngine] to capture the exact initial volume passed to
/// [play] before any subsequent [fadeVolume] call mutates handle volume.
class _RecordingFakeAudioEngine extends FakeAudioEngine {
  _RecordingFakeAudioEngine({super.defaultDuration, super.durationsByPath});

  final Map<String, double> initialPlayVolumeByHandle = <String, double>{};
  Completer<void>? loadGate;
  Completer<void>? fadeGate;

  @override
  Future<String> loadSource(String path, {bool isAsset = false}) async {
    final gate = loadGate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    return super.loadSource(path, isAsset: isAsset);
  }

  @override
  Future<void> fadeVolume(
    String handle,
    double targetVolume,
    Duration duration,
  ) async {
    final gate = fadeGate;
    if (gate != null && !gate.isCompleted) {
      fadeGate = null;
      await gate.future;
    }
    return super.fadeVolume(handle, targetVolume, duration);
  }

  @override
  Future<String> play(
    String sourceId, {
    double volume = 1.0,
    bool looping = false,
  }) async {
    final handle = await super.play(sourceId, volume: volume, looping: looping);
    initialPlayVolumeByHandle[handle] = volume;
    return handle;
  }
}

SoundPad _effectPad({
  String id = 'fx_sword',
  String label = 'Sword Clash',
  String audioPath = 'sfx/sword.wav',
  bool isAsset = false,
  double volume = 0.85,
  RetriggerMode retriggerMode = RetriggerMode.restart,
  int? fadeInMsOverride,
  int? fadeOutMsOverride,
  int order = 0,
}) {
  return SoundPad(
    id: id,
    folderId: 'combat',
    label: label,
    colorValue: 0xFFB84A39,
    icon: PadIcon.sword,
    audioPath: audioPath,
    isAsset: isAsset,
    type: PadType.effect,
    volume: volume,
    retriggerMode: retriggerMode,
    fadeInMsOverride: fadeInMsOverride,
    fadeOutMsOverride: fadeOutMsOverride,
    order: order,
  );
}

SoundPad _musicPad({
  String id = 'music_a',
  String label = 'Battle Theme',
  String audioPath = 'music/battle.ogg',
  bool isAsset = false,
  double volume = 0.8,
  int? fadeInMsOverride,
  int? fadeOutMsOverride,
  int? crossfadeMsOverride,
  int order = 0,
}) {
  return SoundPad(
    id: id,
    folderId: 'combat',
    label: label,
    colorValue: 0xFFD4882A,
    icon: PadIcon.music,
    audioPath: audioPath,
    isAsset: isAsset,
    type: PadType.music,
    volume: volume,
    fadeInMsOverride: fadeInMsOverride,
    fadeOutMsOverride: fadeOutMsOverride,
    crossfadeMsOverride: crossfadeMsOverride,
    order: order,
  );
}

SoundPad _ambiencePad({
  String id = 'amb_rain',
  String label = 'Rain',
  String audioPath = 'ambience/rain.ogg',
  bool isAsset = false,
  double volume = 0.65,
  int? fadeInMsOverride,
  int? fadeOutMsOverride,
  int order = 0,
}) {
  return SoundPad(
    id: id,
    folderId: 'exploration',
    label: label,
    colorValue: 0xFF3E6B89,
    icon: PadIcon.rain,
    audioPath: audioPath,
    isAsset: isAsset,
    type: PadType.ambience,
    volume: volume,
    fadeInMsOverride: fadeInMsOverride,
    fadeOutMsOverride: fadeOutMsOverride,
    order: order,
  );
}

void main() {
  late _RecordingFakeAudioEngine audio;
  late FakeClock clock;
  late List<PlaybackState> emittedStates;
  late PlaybackEngine engine;

  const defaultSettings = BoardSettings(
    defaultFadeInMs: 500,
    defaultFadeOutMs: 1000,
    defaultCrossfadeMs: 2000,
    masterVolume: 0.9,
  );

  setUp(() {
    audio = _RecordingFakeAudioEngine(
      defaultDuration: const Duration(seconds: 2),
      durationsByPath: <String, Duration>{
        'sfx/sword.wav': const Duration(milliseconds: 1000),
        'sfx/fireball.wav': const Duration(milliseconds: 1500),
        'sfx/long_horn.wav': const Duration(milliseconds: 3000),
        'music/battle.ogg': const Duration(minutes: 3),
        'music/boss.ogg': const Duration(minutes: 4),
        'music/victory.ogg': const Duration(minutes: 2),
        'ambience/rain.ogg': const Duration(minutes: 5),
        'ambience/tavern.ogg': const Duration(minutes: 5),
      },
    );
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12, 0, 0));
    emittedStates = <PlaybackState>[];
    engine = PlaybackEngine(
      audioEngine: audio,
      clock: clock,
      settings: defaultSettings,
      onStateChanged: emittedStates.add,
    );
  });

  group('Initialization, settings, and disposal', () {
    test(
      'initialize initializes audio engine and applies master volume',
      () async {
        await engine.initialize();

        expect(audio.isInitialized, isTrue);
        expect(audio.masterVolume, closeTo(0.9, 1e-9));
        expect(engine.state.activeByPad, isEmpty);
      },
    );

    test('updateSettings updates fade defaults and master volume', () async {
      await engine.initialize();
      await engine.updateSettings(
        defaultSettings.copyWith(defaultFadeInMs: 200, masterVolume: 0.6),
      );

      expect(audio.masterVolume, closeTo(0.6, 1e-9));

      final music = _musicPad();
      await engine.tapPad(music);

      expect(
        audio.fades,
        contains(
          FakeFadeCall(
            handle: audio.playedHandles.single,
            targetVolume: music.volume,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      );
      clock.advance(const Duration(milliseconds: 200));
      expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.playing);
    });

    test(
      'dispose cancels all active timers and disposes audio engine',
      () async {
        await engine.initialize();
        final music = _musicPad();
        final effect = _effectPad();

        await engine.tapPad(music);
        await engine.tapPad(effect);
        expect(clock.activeTimerCount, greaterThan(0));

        await engine.dispose();

        expect(clock.activeTimerCount, 0);
        expect(audio.isDisposed, isTrue);
      },
    );
  });

  group('Effect pads', () {
    test(
      'starts immediately with looping false, pad volume, and zero fade-in',
      () async {
        await engine.initialize();
        final sword = _effectPad(volume: 0.75, isAsset: true);

        await engine.tapPad(sword);

        expect(audio.playedHandles, hasLength(1));
        final handle = audio.playedHandles.single;
        final handleState = audio.handleState(handle)!;

        expect(handleState.looping, isFalse);
        expect(audio.initialPlayVolumeByHandle[handle], closeTo(0.75, 1e-9));
        expect(audio.volumeFor(handle), closeTo(0.75, 1e-9));
        expect(audio.fades, isEmpty);
        expect(audio.isAssetSource(handleState.sourceId), isTrue);

        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.playing);
        final voice = engine.state.activeByPad[sword.id]!;
        expect(voice.volume, closeTo(0.75, 1e-9));
        expect(voice.activeLayerCount, 1);
        expect(voice.duration, const Duration(milliseconds: 1000));
        expect(voice.position, Duration.zero);
        expect(emittedStates, isNotEmpty);
      },
    );

    test(
      'overlaps freely with music, ambience, and other effect pads',
      () async {
        await engine.initialize();
        final music = _musicPad();
        final rain = _ambiencePad();
        final sword = _effectPad(id: 'fx_1', audioPath: 'sfx/sword.wav');
        final fireball = _effectPad(
          id: 'fx_2',
          label: 'Fireball',
          audioPath: 'sfx/fireball.wav',
        );

        await engine.tapPad(music);
        await engine.tapPad(rain);
        clock.advance(const Duration(milliseconds: 500));

        await engine.tapPad(sword);
        await engine.tapPad(fireball);

        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.playing);
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.playing);
        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.playing);
        expect(engine.state.phaseForPad(fireball.id), PadPlaybackPhase.playing);
        expect(audio.activeHandles, hasLength(4));
        expect(audio.stoppedHandles, isEmpty);
      },
    );

    test(
      'advances position via FakeClock and returns to idle with zero active timers when duration elapses',
      () async {
        await engine.initialize();
        final sword = _effectPad();

        await engine.tapPad(sword);
        final initialVoice = engine.state.activeByPad[sword.id]!;
        expect(initialVoice.position, Duration.zero);
        expect(initialVoice.duration, const Duration(milliseconds: 1000));

        final stateCountAfterStart = emittedStates.length;
        clock.advance(const Duration(milliseconds: 400));

        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.playing);
        final midVoice = engine.state.activeByPad[sword.id]!;
        expect(midVoice.position, greaterThan(Duration.zero));
        expect(
          midVoice.position,
          lessThanOrEqualTo(const Duration(milliseconds: 400)),
        );
        expect(midVoice.duration, const Duration(milliseconds: 1000));
        expect(emittedStates.length, greaterThan(stateCountAfterStart));

        clock.advance(const Duration(milliseconds: 600));

        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.idle);
        expect(engine.state.activeByPad.containsKey(sword.id), isFalse);
        expect(clock.activeTimerCount, 0);
      },
    );

    test(
      'RetriggerMode.restart stops previous handle, restarts from Duration.zero, and keeps activeLayerCount at 1',
      () async {
        await engine.initialize();
        final sword = _effectPad(retriggerMode: RetriggerMode.restart);

        await engine.tapPad(sword);
        final firstHandle = audio.playedHandles.single;

        clock.advance(const Duration(milliseconds: 400));
        expect(
          engine.state.activeByPad[sword.id]!.position,
          greaterThan(Duration.zero),
        );

        await engine.tapPad(sword);
        expect(audio.playedHandles, hasLength(2));
        final secondHandle = audio.playedHandles.last;

        expect(audio.stoppedHandles, contains(firstHandle));
        expect(audio.activeHandles, equals(<String>{secondHandle}));

        final voice = engine.state.activeByPad[sword.id]!;
        expect(voice.phase, PadPlaybackPhase.playing);
        expect(voice.activeLayerCount, 1);
        expect(voice.position, Duration.zero);

        // 700ms after second tap (1100ms after first): still playing.
        clock.advance(const Duration(milliseconds: 700));
        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.playing);

        // Remaining 300ms finishes second tap cleanly.
        clock.advance(const Duration(milliseconds: 300));
        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.idle);
        expect(clock.activeTimerCount, 0);
      },
    );

    test(
      'RetriggerMode.layer keeps previous handle active, tracks activeLayerCount, and returns to idle only after all layers finish',
      () async {
        await engine.initialize();
        final sword = _effectPad(retriggerMode: RetriggerMode.layer);

        await engine.tapPad(sword);
        final firstHandle = audio.playedHandles[0];
        expect(engine.state.activeByPad[sword.id]!.activeLayerCount, 1);

        clock.advance(const Duration(milliseconds: 400));

        await engine.tapPad(sword);
        final secondHandle = audio.playedHandles[1];

        expect(audio.stoppedHandles, isEmpty);
        expect(
          audio.activeHandles,
          equals(<String>{firstHandle, secondHandle}),
        );
        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.playing);
        expect(engine.state.activeByPad[sword.id]!.activeLayerCount, 2);

        // First layer completes at 1000ms; second layer still has 400ms left.
        clock.advance(const Duration(milliseconds: 600));
        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.playing);
        expect(engine.state.activeByPad[sword.id]!.activeLayerCount, 1);

        // Second layer completes 400ms later.
        clock.advance(const Duration(milliseconds: 400));
        expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.idle);
        expect(engine.state.activeByPad.containsKey(sword.id), isFalse);
        expect(clock.activeTimerCount, 0);
      },
    );

    test('stopPad stops an active effect immediately by default', () async {
      await engine.initialize();
      final sword = _effectPad();

      await engine.tapPad(sword);
      final handle = audio.playedHandles.single;

      await engine.stopPad(sword.id);

      expect(audio.stoppedHandles, contains(handle));
      expect(audio.fades, isEmpty);
      expect(engine.state.phaseForPad(sword.id), PadPlaybackPhase.idle);
      expect(engine.state.activeByPad.containsKey(sword.id), isFalse);
      expect(clock.activeTimerCount, 0);
    });

    test(
      'stopPad fades out an active effect when fadeOutMsOverride is configured',
      () async {
        await engine.initialize();
        final horn = _effectPad(
          id: 'fx_horn',
          audioPath: 'sfx/long_horn.wav',
          fadeOutMsOverride: 300,
        );

        await engine.tapPad(horn);
        final handle = audio.playedHandles.single;

        await engine.stopPad(horn.id);

        expect(engine.state.phaseForPad(horn.id), PadPlaybackPhase.fadingOut);
        expect(audio.stoppedHandles, isEmpty);
        expect(
          audio.fades,
          contains(
            FakeFadeCall(
              handle: handle,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 300),
            ),
          ),
        );
        expect(
          audio.scheduledStops,
          contains(
            FakeScheduledStop(
              handle: handle,
              delay: const Duration(milliseconds: 300),
            ),
          ),
        );

        clock.advance(const Duration(milliseconds: 150));
        expect(engine.state.phaseForPad(horn.id), PadPlaybackPhase.fadingOut);

        clock.advance(const Duration(milliseconds: 150));
        expect(audio.stoppedHandles, contains(handle));
        expect(engine.state.phaseForPad(horn.id), PadPlaybackPhase.idle);
        expect(clock.activeTimerCount, 0);
      },
    );
  });

  group('Music pads', () {
    test(
      'loops gaplessly and fades in from 0.0 to pad volume over defaultFadeInMs',
      () async {
        await engine.initialize();
        final musicA = _musicPad(id: 'music_a', volume: 0.8);

        await engine.tapPad(musicA);

        expect(audio.playedHandles, hasLength(1));
        final handleA = audio.playedHandles.single;
        expect(audio.handleState(handleA)!.looping, isTrue);
        expect(audio.initialPlayVolumeByHandle[handleA], closeTo(0.0, 1e-9));
        expect(
          audio.fades,
          contains(
            FakeFadeCall(
              handle: handleA,
              targetVolume: 0.8,
              duration: const Duration(milliseconds: 500),
            ),
          ),
        );
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingIn);

        clock.advance(const Duration(milliseconds: 250));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingIn);

        clock.advance(const Duration(milliseconds: 250));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.playing);
      },
    );

    test(
      'crossfades from Music A to Music B over defaultCrossfadeMs leaving only Music B playing',
      () async {
        await engine.initialize();
        final musicA = _musicPad(
          id: 'music_a',
          audioPath: 'music/battle.ogg',
          volume: 0.8,
        );
        final musicB = _musicPad(
          id: 'music_b',
          label: 'Boss Theme',
          audioPath: 'music/boss.ogg',
          volume: 0.7,
        );

        await engine.tapPad(musicA);
        final handleA = audio.playedHandles.single;
        clock.advance(const Duration(milliseconds: 500));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.playing);

        await engine.tapPad(musicB);
        final handleB = audio.playedHandles.last;

        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.fadingIn);
        expect(audio.initialPlayVolumeByHandle[handleB], closeTo(0.0, 1e-9));
        expect(audio.handleState(handleB)!.looping, isTrue);
        expect(audio.stoppedHandles, isNot(contains(handleA)));

        expect(
          audio.fades,
          containsAll(<FakeFadeCall>[
            FakeFadeCall(
              handle: handleA,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 2000),
            ),
            FakeFadeCall(
              handle: handleB,
              targetVolume: 0.7,
              duration: const Duration(milliseconds: 2000),
            ),
          ]),
        );
        expect(
          audio.scheduledStops,
          contains(
            FakeScheduledStop(
              handle: handleA,
              delay: const Duration(milliseconds: 2000),
            ),
          ),
        );

        clock.advance(const Duration(milliseconds: 1000));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.fadingIn);

        clock.advance(const Duration(milliseconds: 1000));
        expect(audio.stoppedHandles, contains(handleA));
        expect(audio.isHandleActive(handleA), isFalse);
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.playing);
        expect(engine.state.activeByPad.keys, equals(<String>[musicB.id]));
        expect(audio.activeHandles, equals(<String>{handleB}));
      },
    );

    test(
      'interrupted crossfade (A -> B -> C) fades B out, fades C in, and ends with only Music C playing',
      () async {
        await engine.initialize();
        final musicA = _musicPad(
          id: 'music_a',
          audioPath: 'music/battle.ogg',
          volume: 0.8,
        );
        final musicB = _musicPad(
          id: 'music_b',
          label: 'Boss Theme',
          audioPath: 'music/boss.ogg',
          volume: 0.75,
        );
        final musicC = _musicPad(
          id: 'music_c',
          label: 'Victory Theme',
          audioPath: 'music/victory.ogg',
          volume: 0.9,
        );

        await engine.tapPad(musicA);
        final handleA = audio.playedHandles[0];
        clock.advance(const Duration(milliseconds: 500));

        // Start A -> B crossfade (2000ms).
        await engine.tapPad(musicB);
        final handleB = audio.playedHandles[1];

        // Interrupt halfway (1000ms in) by starting Music C.
        clock.advance(const Duration(milliseconds: 1000));
        await engine.tapPad(musicC);
        final handleC = audio.playedHandles[2];

        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicC.id), PadPlaybackPhase.fadingIn);
        expect(
          audio.fades,
          containsAll(<FakeFadeCall>[
            FakeFadeCall(
              handle: handleB,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 2000),
            ),
            FakeFadeCall(
              handle: handleC,
              targetVolume: 0.9,
              duration: const Duration(milliseconds: 2000),
            ),
          ]),
        );
        expect(
          audio.scheduledStops,
          contains(
            FakeScheduledStop(
              handle: handleB,
              delay: const Duration(milliseconds: 2000),
            ),
          ),
        );

        // After another 1000ms, A's fade-out finishes; B and C still crossfading.
        clock.advance(const Duration(milliseconds: 1000));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(audio.stoppedHandles, contains(handleA));
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicC.id), PadPlaybackPhase.fadingIn);

        // After final 1000ms, B is stopped and ONLY C is playing.
        clock.advance(const Duration(milliseconds: 1000));
        expect(audio.stoppedHandles, containsAll(<String>[handleA, handleB]));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(musicC.id), PadPlaybackPhase.playing);
        expect(engine.state.activeByPad.keys, equals(<String>[musicC.id]));
        expect(audio.activeHandles, equals(<String>{handleC}));
      },
    );

    test(
      'tapping active Music A fades it out smoothly (never hard-cut) and stops it on completion',
      () async {
        await engine.initialize();
        final musicA = _musicPad(id: 'music_a');

        await engine.tapPad(musicA);
        final handleA = audio.playedHandles.single;
        clock.advance(const Duration(milliseconds: 500));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.playing);

        await engine.tapPad(musicA);

        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(audio.stoppedHandles, isEmpty);
        expect(
          audio.fades,
          contains(
            FakeFadeCall(
              handle: handleA,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 1000),
            ),
          ),
        );
        expect(
          audio.scheduledStops,
          contains(
            FakeScheduledStop(
              handle: handleA,
              delay: const Duration(milliseconds: 1000),
            ),
          ),
        );

        clock.advance(const Duration(milliseconds: 500));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(audio.stoppedHandles, isEmpty);

        clock.advance(const Duration(milliseconds: 500));
        expect(audio.stoppedHandles, contains(handleA));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(engine.state.activeByPad, isEmpty);
        expect(clock.activeTimerCount, 0);
      },
    );

    test(
      'per-pad fadeInMsOverride, fadeOutMsOverride, and crossfadeMsOverride override global BoardSettings',
      () async {
        await engine.initialize();
        final musicA = _musicPad(
          id: 'music_a',
          audioPath: 'music/battle.ogg',
          volume: 0.8,
          fadeInMsOverride: 150,
          fadeOutMsOverride: 300,
        );
        final musicB = _musicPad(
          id: 'music_b',
          audioPath: 'music/boss.ogg',
          volume: 0.7,
          crossfadeMsOverride: 750,
          fadeOutMsOverride: 400,
        );

        // Fade-in override (150ms instead of 500ms).
        await engine.tapPad(musicA);
        final handleA = audio.playedHandles[0];
        expect(
          audio.fades.last,
          FakeFadeCall(
            handle: handleA,
            targetVolume: 0.8,
            duration: const Duration(milliseconds: 150),
          ),
        );
        clock.advance(const Duration(milliseconds: 150));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.playing);

        // Crossfade override on incoming Music B (750ms instead of 2000ms).
        await engine.tapPad(musicB);
        final handleB = audio.playedHandles[1];
        expect(
          audio.fades,
          containsAll(<FakeFadeCall>[
            FakeFadeCall(
              handle: handleA,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 750),
            ),
            FakeFadeCall(
              handle: handleB,
              targetVolume: 0.7,
              duration: const Duration(milliseconds: 750),
            ),
          ]),
        );
        expect(
          audio.scheduledStops,
          contains(
            FakeScheduledStop(
              handle: handleA,
              delay: const Duration(milliseconds: 750),
            ),
          ),
        );

        clock.advance(const Duration(milliseconds: 750));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.playing);

        // Fade-out override on Music B (400ms instead of 1000ms).
        await engine.tapPad(musicB);
        expect(
          audio.fades.last,
          FakeFadeCall(
            handle: handleB,
            targetVolume: 0.0,
            duration: const Duration(milliseconds: 400),
          ),
        );
        clock.advance(const Duration(milliseconds: 400));
        expect(audio.stoppedHandles, contains(handleB));
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.idle);
        expect(clock.activeTimerCount, 0);
      },
    );
  });

  group('Ambience pads', () {
    test('loops gaplessly and fades in on start and out on stop', () async {
      await engine.initialize();
      final rain = _ambiencePad(volume: 0.65);

      await engine.tapPad(rain);
      final handle = audio.playedHandles.single;

      expect(audio.handleState(handle)!.looping, isTrue);
      expect(audio.initialPlayVolumeByHandle[handle], closeTo(0.0, 1e-9));
      expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingIn);
      expect(
        audio.fades.last,
        FakeFadeCall(
          handle: handle,
          targetVolume: 0.65,
          duration: const Duration(milliseconds: 500),
        ),
      );

      clock.advance(const Duration(milliseconds: 500));
      expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.playing);

      await engine.tapPad(rain);
      expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingOut);
      expect(audio.stoppedHandles, isEmpty);
      expect(
        audio.fades.last,
        FakeFadeCall(
          handle: handle,
          targetVolume: 0.0,
          duration: const Duration(milliseconds: 1000),
        ),
      );

      clock.advance(const Duration(milliseconds: 1000));
      expect(audio.stoppedHandles, contains(handle));
      expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.idle);
      expect(clock.activeTimerCount, 0);
    });

    test(
      'layers multiple ambience pads concurrently alongside active music',
      () async {
        await engine.initialize();
        final music = _musicPad();
        final rain = _ambiencePad(
          id: 'amb_rain',
          label: 'Rain',
          audioPath: 'ambience/rain.ogg',
        );
        final tavern = _ambiencePad(
          id: 'amb_tavern',
          label: 'Tavern Chatter',
          audioPath: 'ambience/tavern.ogg',
        );

        await engine.tapPad(music);
        await engine.tapPad(rain);
        await engine.tapPad(tavern);

        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.fadingIn);
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingIn);
        expect(engine.state.phaseForPad(tavern.id), PadPlaybackPhase.fadingIn);

        clock.advance(const Duration(milliseconds: 500));

        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.playing);
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.playing);
        expect(engine.state.phaseForPad(tavern.id), PadPlaybackPhase.playing);
        expect(audio.activeHandles, hasLength(3));

        // Stopping Rain only fades out Rain; Music and Tavern stay playing.
        await engine.tapPad(rain);
        clock.advance(const Duration(milliseconds: 1000));

        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.playing);
        expect(engine.state.phaseForPad(tavern.id), PadPlaybackPhase.playing);
        expect(audio.activeHandles, hasLength(2));
      },
    );
  });

  group('Stop All', () {
    test(
      'fades all active music, ambience, and effects out smoothly and cleans up all handles and timers',
      () async {
        await engine.initialize();
        final music = _musicPad();
        final rain = _ambiencePad();
        final horn = _effectPad(id: 'fx_horn', audioPath: 'sfx/long_horn.wav');

        await engine.tapPad(music);
        await engine.tapPad(rain);
        clock.advance(const Duration(milliseconds: 500));
        await engine.tapPad(horn);

        final musicHandle = audio.playedHandles[0];
        final rainHandle = audio.playedHandles[1];
        final hornHandle = audio.playedHandles[2];

        await engine.stopAll();

        // No hard cuts on looping pads or active voices.
        expect(audio.stoppedHandles, isEmpty);
        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(horn.id), PadPlaybackPhase.fadingOut);

        expect(
          audio.fades,
          containsAll(<FakeFadeCall>[
            FakeFadeCall(
              handle: musicHandle,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 1000),
            ),
            FakeFadeCall(
              handle: rainHandle,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 1000),
            ),
            FakeFadeCall(
              handle: hornHandle,
              targetVolume: 0.0,
              duration: const Duration(milliseconds: 1000),
            ),
          ]),
        );

        clock.advance(const Duration(milliseconds: 1000));

        expect(
          audio.stoppedHandles,
          containsAll(<String>[musicHandle, rainHandle, hornHandle]),
        );
        expect(audio.activeHandles, isEmpty);
        expect(engine.state.activeByPad, isEmpty);
        expect(clock.activeTimerCount, 0);
      },
    );

    test('does not restart fade-out on a pad already fadingOut', () async {
      await engine.initialize();
      final music = _musicPad();
      final rain = _ambiencePad();

      await engine.tapPad(music);
      await engine.tapPad(rain);
      clock.advance(const Duration(milliseconds: 500));

      final musicHandle = audio.playedHandles[0];
      final rainHandle = audio.playedHandles[1];

      // Start fading out Music (1000ms).
      await engine.tapPad(music);
      expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.fadingOut);

      // Advance 600ms so Music has 400ms remaining.
      clock.advance(const Duration(milliseconds: 600));
      final musicFadeOutsBefore = audio.fades
          .where((call) => call.handle == musicHandle && call.targetVolume == 0)
          .length;
      expect(musicFadeOutsBefore, 1);

      await engine.stopAll();

      final musicFadeOutsAfter = audio.fades
          .where((call) => call.handle == musicHandle && call.targetVolume == 0)
          .length;
      expect(musicFadeOutsAfter, 1);
      expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingOut);

      // 400ms later: Music finishes on its original schedule, Rain still fading.
      clock.advance(const Duration(milliseconds: 400));
      expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.idle);
      expect(audio.stoppedHandles, contains(musicHandle));
      expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingOut);

      // 600ms later: Rain finishes too.
      clock.advance(const Duration(milliseconds: 600));
      expect(audio.stoppedHandles, contains(rainHandle));
      expect(engine.state.activeByPad, isEmpty);
      expect(clock.activeTimerCount, 0);
    });
  });

  group('Volume controls', () {
    test(
      'setMasterVolume updates audioEngine.masterVolume and clamps range',
      () async {
        await engine.initialize();

        await engine.setMasterVolume(0.5);
        expect(audio.masterVolume, closeTo(0.5, 1e-9));

        await engine.setMasterVolume(1.5);
        expect(audio.masterVolume, closeTo(1.0, 1e-9));

        await engine.setMasterVolume(-0.2);
        expect(audio.masterVolume, closeTo(0.0, 1e-9));
      },
    );

    test(
      'setPadVolume updates active handle volume and ActiveVoiceState.volume',
      () async {
        await engine.initialize();
        final music = _musicPad(volume: 0.8);

        await engine.tapPad(music);
        final handle = audio.playedHandles.single;
        clock.advance(const Duration(milliseconds: 500));

        await engine.setPadVolume(music.id, 0.4);

        expect(audio.volumeFor(handle), closeTo(0.4, 1e-9));
        expect(engine.state.activeByPad[music.id]!.volume, closeTo(0.4, 1e-9));
      },
    );

    test('setPadVolume on an idle pad is a safe no-op', () async {
      await engine.initialize();

      await engine.setPadVolume('nonexistent', 0.4);

      expect(engine.state.activeByPad, isEmpty);
    });
  });

  group('Audio interruptions (phone calls)', () {
    test(
      'pauseForInterruption pauses active voices and resumeAfterInterruption resumes them once',
      () async {
        await engine.initialize();
        final music = _musicPad();

        await engine.tapPad(music);
        clock.advance(const Duration(milliseconds: 500));

        await engine.pauseForInterruption();
        expect(audio.pausedCount, 1);
        expect(audio.isPaused, isTrue);

        // Duplicate pause while already interrupted is a no-op.
        await engine.pauseForInterruption();
        expect(audio.pausedCount, 1);

        await engine.resumeAfterInterruption();
        expect(audio.resumedCount, 1);
        expect(audio.isPaused, isFalse);

        // Second resume without another interruption does not resume again.
        await engine.resumeAfterInterruption();
        expect(audio.resumedCount, 1);
      },
    );

    test(
      'pauseForInterruption and resumeAfterInterruption are no-ops when nothing is active',
      () async {
        await engine.initialize();

        await engine.pauseForInterruption();
        expect(audio.pausedCount, 0);
        expect(audio.isPaused, isFalse);

        await engine.resumeAfterInterruption();
        expect(audio.resumedCount, 0);
      },
    );
  });

  group('Missing or corrupt audio error handling', () {
    test(
      'AudioLoadException sets pad to error phase with errorMessage without disrupting other playing pads',
      () async {
        await engine.initialize();
        audio.failingPaths.add('broken/corrupt.wav');

        final music = _musicPad();
        final broken = _effectPad(
          id: 'fx_broken',
          label: 'Broken Pad',
          audioPath: 'broken/corrupt.wav',
        );

        await engine.tapPad(music);
        final musicHandle = audio.playedHandles.single;
        clock.advance(const Duration(milliseconds: 500));

        await expectLater(engine.tapPad(broken), completes);

        expect(engine.state.phaseForPad(broken.id), PadPlaybackPhase.error);
        final errorVoice = engine.state.activeByPad[broken.id]!;
        expect(errorVoice.errorMessage, isNotNull);
        expect(errorVoice.errorMessage, isNotEmpty);

        // Active music remains undisturbed.
        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.playing);
        expect(audio.isHandleActive(musicHandle), isTrue);
      },
    );

    test(
      'clearPadError resets errored pad to idle without affecting playing pads',
      () async {
        await engine.initialize();
        audio.failingPaths.add('broken/corrupt.wav');

        final music = _musicPad();
        final broken = _effectPad(
          id: 'fx_broken',
          audioPath: 'broken/corrupt.wav',
        );

        await engine.tapPad(music);
        clock.advance(const Duration(milliseconds: 500));
        await engine.tapPad(broken);
        expect(engine.state.phaseForPad(broken.id), PadPlaybackPhase.error);

        engine.clearPadError(broken.id);
        expect(engine.state.phaseForPad(broken.id), PadPlaybackPhase.idle);
        expect(engine.state.activeByPad.containsKey(broken.id), isFalse);

        // Calling clearPadError on a playing pad does not stop or clear it.
        engine.clearPadError(music.id);
        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.playing);
      },
    );

    test(
      'error on re-tapped active pad stops prior active handles without leaking',
      () async {
        await engine.initialize();
        final fx = _effectPad(id: 'fx_flaky', audioPath: 'audio/flaky.wav');

        await engine.tapPad(fx);
        final firstHandle = audio.playedHandles.single;
        expect(audio.isHandleActive(firstHandle), isTrue);

        // Make subsequent load fail (simulating file deleted mid-session).
        audio.failingPaths.add(fx.audioPath);
        await engine.tapPad(fx);

        expect(engine.state.phaseForPad(fx.id), PadPlaybackPhase.error);
        expect(audio.stoppedHandles, contains(firstHandle));
        expect(audio.isHandleActive(firstHandle), isFalse);
      },
    );
  });

  group('Concurrency, interrupted fades, and paused timer edge cases', () {
    test(
      'rapid concurrent music taps while loadSource is pending only keep latest track',
      () async {
        await engine.initialize();
        final musicA = _musicPad(id: 'm_a', audioPath: 'audio/a.wav');
        final musicB = _musicPad(id: 'm_b', audioPath: 'audio/b.wav');

        final gate = Completer<void>();
        audio.loadGate = gate;

        final tapA = engine.tapPad(musicA);
        final tapB = engine.tapPad(musicB);

        gate.complete();
        await Future.wait<void>([tapA, tapB]);

        clock.advance(const Duration(milliseconds: 500));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.playing);
        expect(audio.activeHandles, hasLength(1));
        expect(
          audio.pathForHandle(audio.activeHandles.single),
          musicB.audioPath,
        );
      },
    );

    test(
      're-tapping music or ambience while fadingOut stops old handle and fades back in',
      () async {
        await engine.initialize();
        final rain = _ambiencePad(id: 'amb_rain');

        await engine.tapPad(rain);
        final firstHandle = audio.playedHandles.single;
        clock.advance(const Duration(milliseconds: 500));
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.playing);

        // Start fading out.
        await engine.tapPad(rain);
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingOut);
        clock.advance(const Duration(milliseconds: 300));

        // Change mind mid-fade-out: tap again to fade back in.
        await engine.tapPad(rain);
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.fadingIn);
        expect(audio.stoppedHandles, contains(firstHandle));
        expect(audio.playedHandles, hasLength(2));
        final secondHandle = audio.playedHandles.last;

        clock.advance(const Duration(milliseconds: 500));
        expect(engine.state.phaseForPad(rain.id), PadPlaybackPhase.playing);
        expect(audio.isHandleActive(secondHandle), isTrue);
      },
    );

    test(
      'stopAll during async fadeVolume does not leave pad stuck in fadingOut',
      () async {
        await engine.initialize();
        final music = _musicPad(id: 'm_race');

        final fadeGate = Completer<void>();
        audio.fadeGate = fadeGate;

        final tapFuture = engine.tapPad(music);
        await Future<void>.delayed(Duration.zero);

        // Trigger stopAll while fadeVolume is still yielding.
        final stopFuture = engine.stopAll();
        fadeGate.complete();
        await Future.wait<void>([tapFuture, stopFuture]);

        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.fadingOut);
        clock.advance(const Duration(milliseconds: 1000));
        expect(engine.state.phaseForPad(music.id), PadPlaybackPhase.idle);
        expect(engine.state.activeByPad, isEmpty);
        expect(clock.activeTimerCount, 0);
      },
    );

    test(
      'pauseForInterruption and resumeAfterInterruption preserve fade-in, fade-out, and effect timers',
      () async {
        await engine.initialize();
        final musicA = _musicPad(id: 'm_a', audioPath: 'audio/a.wav');
        final musicB = _musicPad(id: 'm_b', audioPath: 'audio/b.wav');
        final fx = _effectPad(id: 'fx_1', audioPath: 'sfx/long_horn.wav');

        // Start Music A (playing), then start 2000ms crossfade to Music B (A fadingOut, B fadingIn), plus a 3000ms Effect.
        await engine.tapPad(musicA);
        clock.advance(const Duration(milliseconds: 500));
        await engine.tapPad(musicB);
        await engine.tapPad(fx);

        // Advance 1000ms into 2000ms crossfade & 3000ms effect.
        clock.advance(const Duration(milliseconds: 1000));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.fadingIn);
        expect(engine.state.phaseForPad(fx.id), PadPlaybackPhase.playing);

        // Phone call arrives: pause everything for 10 seconds!
        await engine.pauseForInterruption();
        clock.advance(const Duration(seconds: 10));

        // Nothing should have completed while paused!
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.fadingOut);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.fadingIn);
        expect(engine.state.phaseForPad(fx.id), PadPlaybackPhase.playing);

        // Phone call ends: resume.
        await engine.resumeAfterInterruption();

        // After remaining 1000ms of crossfade, A completes fadeOut and B completes fadeIn.
        clock.advance(const Duration(milliseconds: 1000));
        expect(engine.state.phaseForPad(musicA.id), PadPlaybackPhase.idle);
        expect(engine.state.phaseForPad(musicB.id), PadPlaybackPhase.playing);
        // Effect still has 1000ms left (3000 - 1000 - 1000 = 1000).
        expect(engine.state.phaseForPad(fx.id), PadPlaybackPhase.playing);

        clock.advance(const Duration(milliseconds: 1000));
        expect(engine.state.phaseForPad(fx.id), PadPlaybackPhase.idle);
      },
    );
  });
}
