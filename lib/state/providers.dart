import 'dart:async';

import 'package:auraboard/audio/soloud_audio_engine.dart';
import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/audio_engine.dart';
import 'package:auraboard/domain/clock.dart';
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/domain/playback_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:auraboard/domain/playback_engine.dart' show PlaybackState;

/// Provides the active [AudioEngine] implementation.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = SoLoudAudioEngine();
  ref.onDispose(() {
    unawaited(engine.dispose());
  });
  return engine;
});

/// Provides the [Clock] used for playback scheduling and timestamps.
final clockProvider = Provider<Clock>((ref) {
  return const SystemClock();
});

/// Provides the [LibraryRepository] for loading and persisting board data.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return InMemoryLibraryRepository();
});

/// Loads and manages the persisted [SoundLibrary].
final libraryControllerProvider =
    AsyncNotifierProvider<LibraryController, SoundLibrary>(
      LibraryController.new,
    );

class LibraryController extends AsyncNotifier<SoundLibrary> {
  @override
  Future<SoundLibrary> build() async {
    return ref.read(libraryRepositoryProvider).load();
  }
}

/// Controls pad playback state transitions via [PlaybackEngine].
final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState> {
  late PlaybackEngine _engine;
  bool _initialized = false;
  Future<void>? _pendingInit;
  bool _disposed = false;

  @override
  PlaybackState build() {
    _initialized = false;
    _pendingInit = null;
    _disposed = false;

    final audioEngine = ref.read(audioEngineProvider);
    final clock = ref.read(clockProvider);
    final initialSettings =
        ref.read(libraryControllerProvider).asData?.value.settings ??
        const BoardSettings();

    var isBuildDisposed = false;
    late final PlaybackEngine engine;
    engine = PlaybackEngine(
      audioEngine: audioEngine,
      clock: clock,
      settings: initialSettings,
      onStateChanged: (nextState) {
        if (!isBuildDisposed) {
          state = nextState;
        }
      },
    );
    _engine = engine;

    ref.listen<AsyncValue<SoundLibrary>>(libraryControllerProvider, (
      previous,
      next,
    ) {
      final nextSettings = next.asData?.value.settings;
      final prevSettings = previous?.asData?.value.settings;
      if (nextSettings != null &&
          nextSettings != prevSettings &&
          !isBuildDisposed) {
        unawaited(engine.updateSettings(nextSettings));
      }
    });

    ref.onDispose(() {
      isBuildDisposed = true;
      _disposed = true;
      unawaited(engine.dispose(disposeAudioEngine: false));
    });

    return engine.state;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized || _disposed) {
      return;
    }
    final pending = _pendingInit;
    if (pending != null) {
      await pending;
      return;
    }
    final future = _engine.initialize();
    _pendingInit = future;
    try {
      await future;
      if (!_disposed) {
        _initialized = true;
      }
    } finally {
      if (identical(_pendingInit, future)) {
        _pendingInit = null;
      }
    }
  }

  Future<void> tapPad(SoundPad pad) async {
    await _ensureInitialized();
    await _engine.tapPad(pad);
  }

  Future<void> stopPad(String padId) async {
    await _engine.stopPad(padId);
  }

  Future<void> stopAll() async {
    await _engine.stopAll();
  }

  Future<void> setPadVolume(String padId, double volume) async {
    await _engine.setPadVolume(padId, volume);
  }

  Future<void> setMasterVolume(double volume) async {
    await _ensureInitialized();
    await _engine.setMasterVolume(volume);
  }

  Future<void> pauseForInterruption() async {
    await _engine.pauseForInterruption();
  }

  Future<void> resumeAfterInterruption() async {
    await _engine.resumeAfterInterruption();
  }

  void clearPadError(String padId) {
    _engine.clearPadError(padId);
  }
}
