import 'package:auraboard/domain/audio_engine.dart';

/// Recorded invocation of [AudioEngine.fadeVolume].
class FakeFadeCall {
  const FakeFadeCall({
    required this.handle,
    required this.targetVolume,
    required this.duration,
  });

  final String handle;
  final double targetVolume;
  final Duration duration;

  @override
  bool operator ==(Object other) {
    return other is FakeFadeCall &&
        other.handle == handle &&
        other.targetVolume == targetVolume &&
        other.duration == duration;
  }

  @override
  int get hashCode => Object.hash(handle, targetVolume, duration);

  @override
  String toString() =>
      'FakeFadeCall(handle: $handle, targetVolume: $targetVolume, '
      'duration: $duration)';
}

/// Recorded invocation of [AudioEngine.scheduleStop].
class FakeScheduledStop {
  const FakeScheduledStop({required this.handle, required this.delay});

  final String handle;
  final Duration delay;

  @override
  bool operator ==(Object other) {
    return other is FakeScheduledStop &&
        other.handle == handle &&
        other.delay == delay;
  }

  @override
  int get hashCode => Object.hash(handle, delay);

  @override
  String toString() => 'FakeScheduledStop(handle: $handle, delay: $delay)';
}

/// Mutable tracking state for a single handle created by [FakeAudioEngine].
class FakeHandleState {
  FakeHandleState({
    required this.handle,
    required this.sourceId,
    required this.path,
    required this.volume,
    required this.looping,
    this.position = Duration.zero,
    this.isActive = true,
  });

  final String handle;
  final String sourceId;
  final String path;
  double volume;
  final bool looping;
  Duration position;
  bool isActive;
}

/// Deterministic in-memory [AudioEngine] spy/fake for unit and widget tests.
class FakeAudioEngine implements AudioEngine {
  FakeAudioEngine({
    this.defaultDuration = const Duration(seconds: 2),
    Set<String>? failingPaths,
    Map<String, Duration>? durationsByPath,
  }) : failingPaths = failingPaths ?? <String>{},
       durationsByPath = durationsByPath ?? <String, Duration>{};

  Duration defaultDuration;
  final Set<String> failingPaths;
  final Map<String, Duration> durationsByPath;

  final List<String> loadedPaths = <String>[];
  final List<String> playedHandles = <String>[];
  final List<FakeFadeCall> fades = <FakeFadeCall>[];
  final List<String> stoppedHandles = <String>[];
  final List<FakeScheduledStop> scheduledStops = <FakeScheduledStop>[];

  int pausedCount = 0;
  int resumedCount = 0;
  bool isInitialized = false;
  bool isDisposed = false;
  bool isPaused = false;
  double masterVolume = 1.0;

  final Map<String, String> _sourcePaths = <String, String>{};
  final Map<String, bool> _sourceIsAsset = <String, bool>{};
  final Map<String, FakeHandleState> _handles = <String, FakeHandleState>{};
  int _nextSourceId = 1;
  int _nextHandleId = 1;

  /// All currently active playback handles.
  Set<String> get activeHandles => _handles.entries
      .where((entry) => entry.value.isActive)
      .map((entry) => entry.key)
      .toSet();

  /// Returns the recorded state for [handle], or `null` if unknown.
  FakeHandleState? handleState(String handle) => _handles[handle];

  /// Returns the current tracked volume for [handle], or `null` if unknown.
  double? volumeFor(String handle) => _handles[handle]?.volume;

  /// Returns the audio path associated with [handle], or `null` if unknown.
  String? pathForHandle(String handle) => _handles[handle]?.path;

  /// Returns the audio path loaded for [sourceId], or `null` if unknown.
  String? pathForSource(String sourceId) => _sourcePaths[sourceId];

  /// Returns whether [sourceId] was loaded as a bundled Flutter asset.
  bool isAssetSource(String sourceId) => _sourceIsAsset[sourceId] ?? false;

  /// Simulates advancing a handle's playback position in tests.
  void setPosition(String handle, Duration position) {
    final state = _handles[handle];
    if (state != null) {
      state.position = position;
    }
  }

  /// Simulates natural end-of-playback for [handle] (marking it inactive).
  void completeHandle(String handle) {
    final state = _handles[handle];
    if (state != null) {
      state.isActive = false;
    }
  }

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    for (final state in _handles.values) {
      state.isActive = false;
    }
  }

  @override
  Future<String> loadSource(String path, {bool isAsset = false}) async {
    if (failingPaths.contains(path)) {
      throw AudioLoadException(path);
    }
    final sourceId = 'source_${_nextSourceId++}';
    loadedPaths.add(path);
    _sourcePaths[sourceId] = path;
    _sourceIsAsset[sourceId] = isAsset;
    return sourceId;
  }

  @override
  Future<void> unloadSource(String sourceId) async {
    _sourcePaths.remove(sourceId);
    _sourceIsAsset.remove(sourceId);
  }

  @override
  Duration getSourceDuration(String sourceId) {
    final path = _sourcePaths[sourceId];
    if (path == null) {
      return defaultDuration;
    }
    return durationsByPath[path] ?? defaultDuration;
  }

  @override
  Future<String> play(
    String sourceId, {
    double volume = 1.0,
    bool looping = false,
  }) async {
    final handle = 'handle_${_nextHandleId++}';
    final path = _sourcePaths[sourceId] ?? sourceId;
    final clampedVolume = volume.clamp(0.0, 1.0).toDouble();
    _handles[handle] = FakeHandleState(
      handle: handle,
      sourceId: sourceId,
      path: path,
      volume: clampedVolume,
      looping: looping,
    );
    playedHandles.add(handle);
    return handle;
  }

  @override
  Future<void> stop(String handle) async {
    stoppedHandles.add(handle);
    final state = _handles[handle];
    if (state != null) {
      state.isActive = false;
    }
  }

  @override
  Future<void> setVolume(String handle, double volume) async {
    final state = _handles[handle];
    if (state != null) {
      state.volume = volume.clamp(0.0, 1.0).toDouble();
    }
  }

  @override
  Future<void> fadeVolume(
    String handle,
    double targetVolume,
    Duration duration,
  ) async {
    final clampedVolume = targetVolume.clamp(0.0, 1.0).toDouble();
    fades.add(
      FakeFadeCall(
        handle: handle,
        targetVolume: clampedVolume,
        duration: duration,
      ),
    );
    final state = _handles[handle];
    if (state != null) {
      state.volume = clampedVolume;
    }
  }

  @override
  Future<void> scheduleStop(String handle, Duration delay) async {
    scheduledStops.add(FakeScheduledStop(handle: handle, delay: delay));
  }

  @override
  Future<void> setMasterVolume(double volume) async {
    masterVolume = volume.clamp(0.0, 1.0).toDouble();
  }

  @override
  Future<void> pauseAll() async {
    pausedCount += 1;
    isPaused = true;
  }

  @override
  Future<void> resumeAll() async {
    resumedCount += 1;
    isPaused = false;
  }

  @override
  bool isHandleActive(String handle) {
    return _handles[handle]?.isActive ?? false;
  }

  @override
  Duration getPosition(String handle) {
    return _handles[handle]?.position ?? Duration.zero;
  }
}
