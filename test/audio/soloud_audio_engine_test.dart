import 'package:auraboard/audio/soloud_audio_engine.dart';
import 'package:auraboard/domain/audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedPlay {
  const _RecordedPlay({
    required this.sourceId,
    required this.handle,
    required this.volume,
    required this.looping,
  });

  final String sourceId;
  final String handle;
  final double volume;
  final bool looping;
}

class _RecordedFade {
  const _RecordedFade({
    required this.handle,
    required this.targetVolume,
    required this.duration,
  });

  final String handle;
  final double targetVolume;
  final Duration duration;
}

class _RecordedScheduledStop {
  const _RecordedScheduledStop({required this.handle, required this.delay});

  final String handle;
  final Duration delay;
}

class _RecordedPause {
  const _RecordedPause({required this.handle, required this.pause});

  final String handle;
  final bool pause;
}

class _FakeSoLoudBridge implements SoLoudBridge {
  int initCalls = 0;
  int deinitCalls = 0;
  bool _initialized = false;

  final List<String> loadedAssets = <String>[];
  final List<String> loadedFiles = <String>[];
  final List<String> disposedSources = <String>[];
  final List<_RecordedPlay> plays = <_RecordedPlay>[];
  final List<String> stoppedHandles = <String>[];
  final Map<String, double> volumeByHandle = <String, double>{};
  final List<_RecordedFade> fades = <_RecordedFade>[];
  final List<_RecordedScheduledStop> scheduledStops =
      <_RecordedScheduledStop>[];
  final List<double> globalVolumes = <double>[];
  final List<_RecordedPause> pauseCalls = <_RecordedPause>[];

  final Set<String> failingPaths = <String>{};
  final Map<String, Duration> lengthsBySource = <String, Duration>{};
  final Map<String, Duration> positionsByHandle = <String, Duration>{};
  final Set<String> validHandles = <String>{};

  int _nextSourceId = 1;
  int _nextHandleId = 1;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> init() async {
    initCalls += 1;
    _initialized = true;
  }

  @override
  Future<void> deinit() async {
    deinitCalls += 1;
    _initialized = false;
    validHandles.clear();
  }

  @override
  Future<String> loadAsset(String assetPath) async {
    loadedAssets.add(assetPath);
    if (failingPaths.contains(assetPath)) {
      throw StateError('Failed to decode asset: $assetPath');
    }
    final sourceId = 'soloud_asset_${_nextSourceId++}';
    lengthsBySource[sourceId] = const Duration(milliseconds: 1200);
    return sourceId;
  }

  @override
  Future<String> loadFile(String filePath) async {
    loadedFiles.add(filePath);
    if (failingPaths.contains(filePath)) {
      throw StateError('Failed to decode file: $filePath');
    }
    final sourceId = 'soloud_file_${_nextSourceId++}';
    lengthsBySource[sourceId] = const Duration(milliseconds: 2500);
    return sourceId;
  }

  @override
  Future<void> disposeSource(String sourceId) async {
    disposedSources.add(sourceId);
    lengthsBySource.remove(sourceId);
  }

  @override
  Duration getLength(String sourceId) {
    return lengthsBySource[sourceId] ?? Duration.zero;
  }

  @override
  Future<String> play(
    String sourceId, {
    required double volume,
    required bool looping,
  }) async {
    final handle = 'soloud_handle_${_nextHandleId++}';
    validHandles.add(handle);
    volumeByHandle[handle] = volume;
    plays.add(
      _RecordedPlay(
        sourceId: sourceId,
        handle: handle,
        volume: volume,
        looping: looping,
      ),
    );
    return handle;
  }

  @override
  Future<void> stop(String handle) async {
    stoppedHandles.add(handle);
    validHandles.remove(handle);
  }

  @override
  void setVolume(String handle, double volume) {
    volumeByHandle[handle] = volume;
  }

  @override
  void fadeVolume(String handle, double targetVolume, Duration duration) {
    fades.add(
      _RecordedFade(
        handle: handle,
        targetVolume: targetVolume,
        duration: duration,
      ),
    );
  }

  @override
  void scheduleStop(String handle, Duration delay) {
    scheduledStops.add(_RecordedScheduledStop(handle: handle, delay: delay));
  }

  @override
  void setGlobalVolume(double volume) {
    globalVolumes.add(volume);
  }

  @override
  void setPause(String handle, bool pause) {
    pauseCalls.add(_RecordedPause(handle: handle, pause: pause));
  }

  @override
  bool isValidVoiceHandle(String handle) => validHandles.contains(handle);

  @override
  Duration getPosition(String handle) {
    return positionsByHandle[handle] ?? Duration.zero;
  }
}

void main() {
  late _FakeSoLoudBridge bridge;
  late SoLoudAudioEngine engine;

  setUp(() {
    bridge = _FakeSoLoudBridge();
    engine = SoLoudAudioEngine(bridge: bridge);
  });

  group('Initialization and disposal', () {
    test('initialize initializes bridge once and is idempotent', () async {
      await engine.initialize();
      await engine.initialize();

      expect(bridge.initCalls, 1);
      expect(bridge.isInitialized, isTrue);
    });

    test(
      'initializes lazily on first loadSource if initialize was not called',
      () async {
        expect(bridge.isInitialized, isFalse);

        await engine.loadSource(
          'assets/demo_audio/sword_clash.wav',
          isAsset: true,
        );

        expect(bridge.initCalls, 1);
        expect(bridge.isInitialized, isTrue);
      },
    );

    test('dispose deinitializes bridge and clears cached sources', () async {
      final firstId = await engine.loadSource(
        'assets/demo_audio/sword_clash.wav',
        isAsset: true,
      );

      await engine.dispose();
      expect(bridge.deinitCalls, 1);
      expect(bridge.isInitialized, isFalse);

      // Loading again after dispose re-initializes and loads fresh source.
      final secondId = await engine.loadSource(
        'assets/demo_audio/sword_clash.wav',
        isAsset: true,
      );
      expect(bridge.initCalls, 2);
      expect(secondId, isNot(equals(firstId)));
    });
  });

  group('Source loading, caching, validation, and error wrapping', () {
    test(
      'caches loaded sourceId per (path, isAsset) without duplicating native loads',
      () async {
        const assetPath = 'assets/demo_audio/sword_clash.wav';
        const filePath = 'test/fixtures/sample_effect.wav';

        final assetId1 = await engine.loadSource(assetPath, isAsset: true);
        final assetId2 = await engine.loadSource(assetPath, isAsset: true);
        expect(assetId2, equals(assetId1));
        expect(bridge.loadedAssets, equals(<String>[assetPath]));
        expect(bridge.loadedFiles, isEmpty);

        final fileId1 = await engine.loadSource(filePath, isAsset: false);
        final fileId2 = await engine.loadSource(filePath, isAsset: false);
        expect(fileId2, equals(fileId1));
        expect(bridge.loadedFiles, equals(<String>[filePath]));

        // Unloading evicts from cache so a subsequent load re-loads cleanly.
        await engine.unloadSource(fileId1);
        expect(bridge.disposedSources, contains(fileId1));

        final fileId3 = await engine.loadSource(filePath, isAsset: false);
        expect(fileId3, isNot(equals(fileId1)));
        expect(bridge.loadedFiles, hasLength(2));
      },
    );

    test(
      'distinguishes asset cache keys from file cache keys for identical paths',
      () async {
        const sharedPath = 'test/fixtures/sample_effect.wav';

        final assetId = await engine.loadSource(sharedPath, isAsset: true);
        final fileId = await engine.loadSource(sharedPath, isAsset: false);

        expect(assetId, isNot(equals(fileId)));
        expect(bridge.loadedAssets, equals(<String>[sharedPath]));
        expect(bridge.loadedFiles, equals(<String>[sharedPath]));
      },
    );

    test(
      'throws AudioLoadException without calling bridge when local file does not exist',
      () async {
        const missingPath = 'test/fixtures/does_not_exist.wav';

        await expectLater(
          engine.loadSource(missingPath, isAsset: false),
          throwsA(
            isA<AudioLoadException>().having(
              (error) => error.path,
              'path',
              missingPath,
            ),
          ),
        );
        expect(bridge.loadedFiles, isEmpty);
      },
    );

    test(
      'wraps native file load failures into AudioLoadException and does not cache failures',
      () async {
        const corruptPath = 'test/fixtures/corrupt.wav';
        bridge.failingPaths.add(corruptPath);

        await expectLater(
          engine.loadSource(corruptPath, isAsset: false),
          throwsA(
            isA<AudioLoadException>().having(
              (error) => error.path,
              'path',
              corruptPath,
            ),
          ),
        );

        // Removing failure allows a subsequent retry to succeed.
        bridge.failingPaths.remove(corruptPath);
        final loadedId = await engine.loadSource(corruptPath, isAsset: false);
        expect(loadedId, isNotEmpty);
      },
    );

    test('wraps native asset load failures into AudioLoadException', () async {
      const badAsset = 'assets/demo_audio/missing.wav';
      bridge.failingPaths.add(badAsset);

      await expectLater(
        engine.loadSource(badAsset, isAsset: true),
        throwsA(
          isA<AudioLoadException>().having(
            (error) => error.path,
            'path',
            badAsset,
          ),
        ),
      );
    });

    test('getSourceDuration delegates to bridge.getLength', () async {
      final sourceId = await engine.loadSource(
        'test/fixtures/sample_loop.wav',
        isAsset: false,
      );

      expect(
        engine.getSourceDuration(sourceId),
        const Duration(milliseconds: 2500),
      );
    });
  });

  group('Volume clamping and playback delegation', () {
    test(
      'clamps play, setVolume, fadeVolume, and setMasterVolume to [0.0, 1.0]',
      () async {
        final sourceId = await engine.loadSource(
          'test/fixtures/sample_effect.wav',
          isAsset: false,
        );

        final highHandle = await engine.play(
          sourceId,
          volume: 1.7,
          looping: true,
        );
        final lowHandle = await engine.play(
          sourceId,
          volume: -0.4,
          looping: false,
        );

        expect(bridge.plays[0].volume, closeTo(1.0, 1e-9));
        expect(bridge.plays[0].looping, isTrue);
        expect(bridge.plays[1].volume, closeTo(0.0, 1e-9));
        expect(bridge.plays[1].looping, isFalse);

        await engine.setVolume(highHandle, 2.5);
        expect(bridge.volumeByHandle[highHandle], closeTo(1.0, 1e-9));

        await engine.setVolume(lowHandle, -0.8);
        expect(bridge.volumeByHandle[lowHandle], closeTo(0.0, 1e-9));

        await engine.fadeVolume(
          highHandle,
          1.5,
          const Duration(milliseconds: 400),
        );
        await engine.fadeVolume(
          lowHandle,
          -0.2,
          const Duration(milliseconds: 400),
        );
        expect(bridge.fades[0].targetVolume, closeTo(1.0, 1e-9));
        expect(bridge.fades[1].targetVolume, closeTo(0.0, 1e-9));

        await engine.setMasterVolume(1.3);
        await engine.setMasterVolume(-0.5);
        await engine.setMasterVolume(0.65);
        expect(bridge.globalVolumes, equals(<double>[1.0, 0.0, 0.65]));
      },
    );

    test(
      'delegates play, stop, fadeVolume, scheduleStop, isHandleActive, and getPosition',
      () async {
        final sourceId = await engine.loadSource(
          'test/fixtures/sample_loop.wav',
          isAsset: false,
        );

        final handle = await engine.play(sourceId, volume: 0.75, looping: true);
        expect(engine.isHandleActive(handle), isTrue);

        bridge.positionsByHandle[handle] = const Duration(milliseconds: 900);
        expect(engine.getPosition(handle), const Duration(milliseconds: 900));

        await engine.fadeVolume(
          handle,
          0.25,
          const Duration(milliseconds: 600),
        );
        expect(bridge.fades.single.handle, handle);
        expect(bridge.fades.single.targetVolume, closeTo(0.25, 1e-9));
        expect(bridge.fades.single.duration, const Duration(milliseconds: 600));

        await engine.scheduleStop(handle, const Duration(milliseconds: 600));
        expect(bridge.scheduledStops.single.handle, handle);
        expect(
          bridge.scheduledStops.single.delay,
          const Duration(milliseconds: 600),
        );

        await engine.stop(handle);
        expect(bridge.stoppedHandles, contains(handle));
        expect(engine.isHandleActive(handle), isFalse);
      },
    );
  });

  group('pauseAll and resumeAll', () {
    test(
      'pauses only currently active handles and resumes only handles paused by pauseAll',
      () async {
        final sourceId = await engine.loadSource(
          'test/fixtures/sample_loop.wav',
          isAsset: false,
        );

        final handle1 = await engine.play(sourceId, volume: 0.8, looping: true);
        final handle2 = await engine.play(sourceId, volume: 0.6, looping: true);
        final handle3 = await engine.play(sourceId, volume: 0.5, looping: true);

        // Stop handle1 explicitly, and simulate natural completion for handle3.
        await engine.stop(handle1);
        bridge.validHandles.remove(handle3);

        await engine.pauseAll();
        expect(bridge.pauseCalls, hasLength(1));
        expect(bridge.pauseCalls.single.handle, handle2);
        expect(bridge.pauseCalls.single.pause, isTrue);

        bridge.pauseCalls.clear();
        await engine.resumeAll();
        expect(bridge.pauseCalls, hasLength(1));
        expect(bridge.pauseCalls.single.handle, handle2);
        expect(bridge.pauseCalls.single.pause, isFalse);

        // Calling resumeAll again when nothing is paused is a no-op.
        bridge.pauseCalls.clear();
        await engine.resumeAll();
        expect(bridge.pauseCalls, isEmpty);
      },
    );
  });
}
