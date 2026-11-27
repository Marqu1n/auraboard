import 'package:auraboard/data/library_repository.dart';
import 'package:auraboard/domain/audio_engine.dart';
import 'package:auraboard/domain/clock.dart';
import 'package:auraboard/domain/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provides the active [AudioEngine] implementation.
///
/// Phase 1 defaults to a no-op engine; Phase 2 wires `SoLoudAudioEngine`.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  return _NoopAudioEngine();
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

/// Immutable playback state keyed by pad identifier.
class PlaybackState {
  const PlaybackState({this.activeByPad = const <String, ActiveVoiceState>{}});

  final Map<String, ActiveVoiceState> activeByPad;

  /// Returns the current [PadPlaybackPhase] for [padId], defaulting to idle.
  PadPlaybackPhase phaseForPad(String padId) {
    return activeByPad[padId]?.phase ?? PadPlaybackPhase.idle;
  }

  PlaybackState copyWith({Map<String, ActiveVoiceState>? activeByPad}) {
    return PlaybackState(
      activeByPad: activeByPad != null
          ? Map<String, ActiveVoiceState>.unmodifiable(activeByPad)
          : this.activeByPad,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaybackState && _mapEquals(other.activeByPad, activeByPad);
  }

  @override
  int get hashCode => Object.hashAllUnordered(
    activeByPad.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// Controls pad playback state transitions.
final playbackControllerProvider =
    NotifierProvider<PlaybackController, PlaybackState>(PlaybackController.new);

class PlaybackController extends Notifier<PlaybackState> {
  @override
  PlaybackState build() => const PlaybackState();

  /// Minimal Phase 1 tap handler: starts playback when idle, stops when active,
  /// and records an error phase if loading fails.
  Future<void> tapPad(SoundPad pad) async {
    final audioEngine = ref.read(audioEngineProvider);
    final clock = ref.read(clockProvider);
    final current = state.activeByPad[pad.id];

    if (current != null &&
        (current.phase == PadPlaybackPhase.playing ||
            current.phase == PadPlaybackPhase.fadingIn)) {
      final handle = current.handle;
      if (handle != null) {
        await audioEngine.stop(handle);
      }
      final updated = Map<String, ActiveVoiceState>.from(state.activeByPad)
        ..remove(pad.id);
      state = state.copyWith(activeByPad: updated);
      return;
    }

    try {
      final sourceId = await audioEngine.loadSource(
        pad.audioPath,
        isAsset: pad.isAsset,
      );
      final handle = await audioEngine.play(
        sourceId,
        volume: pad.volume,
        looping: pad.type != PadType.effect,
      );
      final updated = Map<String, ActiveVoiceState>.from(state.activeByPad)
        ..[pad.id] = ActiveVoiceState(
          padId: pad.id,
          handle: handle,
          phase: PadPlaybackPhase.playing,
          currentVolume: pad.volume,
          startedAt: clock.now(),
        );
      state = state.copyWith(activeByPad: updated);
    } on AudioLoadException catch (error) {
      final updated = Map<String, ActiveVoiceState>.from(state.activeByPad)
        ..[pad.id] = ActiveVoiceState(
          padId: pad.id,
          phase: PadPlaybackPhase.error,
          currentVolume: 0.0,
          errorMessage: error.message,
        );
      state = state.copyWith(activeByPad: updated);
    }
  }
}

class _NoopAudioEngine implements AudioEngine {
  int _nextSourceId = 1;
  int _nextHandleId = 1;
  final Set<String> _activeHandles = <String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {
    _activeHandles.clear();
  }

  @override
  Future<String> loadSource(String path, {bool isAsset = false}) async {
    return 'noop_source_${_nextSourceId++}';
  }

  @override
  Future<void> unloadSource(String sourceId) async {}

  @override
  Duration getSourceDuration(String sourceId) => Duration.zero;

  @override
  Future<String> play(
    String sourceId, {
    double volume = 1.0,
    bool looping = false,
  }) async {
    final handle = 'noop_handle_${_nextHandleId++}';
    _activeHandles.add(handle);
    return handle;
  }

  @override
  Future<void> stop(String handle) async {
    _activeHandles.remove(handle);
  }

  @override
  Future<void> setVolume(String handle, double volume) async {}

  @override
  Future<void> fadeVolume(
    String handle,
    double targetVolume,
    Duration duration,
  ) async {}

  @override
  Future<void> scheduleStop(String handle, Duration delay) async {
    _activeHandles.remove(handle);
  }

  @override
  Future<void> setMasterVolume(double volume) async {}

  @override
  Future<void> pauseAll() async {}

  @override
  Future<void> resumeAll() async {}

  @override
  bool isHandleActive(String handle) => _activeHandles.contains(handle);

  @override
  Duration getPosition(String handle) => Duration.zero;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
