/// Thrown when an audio source cannot be loaded or decoded.
class AudioLoadException implements Exception {
  const AudioLoadException(this.path, [this.message = 'Failed to load audio']);

  final String path;
  final String message;

  @override
  String toString() => 'AudioLoadException($path): $message';
}

/// Pure Dart audio playback interface implemented by native and test engines.
abstract interface class AudioEngine {
  Future<void> initialize();
  Future<void> dispose();
  Future<String> loadSource(String path, {bool isAsset = false});
  Future<void> unloadSource(String sourceId);
  Duration getSourceDuration(String sourceId);
  Future<String> play(
    String sourceId, {
    double volume = 1.0,
    bool looping = false,
  });
  Future<void> stop(String handle);
  Future<void> setVolume(String handle, double volume);
  Future<void> fadeVolume(
    String handle,
    double targetVolume,
    Duration duration,
  );
  Future<void> scheduleStop(String handle, Duration delay);
  Future<void> setMasterVolume(double volume);
  Future<void> pauseAll();
  Future<void> resumeAll();
  bool isHandleActive(String handle);
  Duration getPosition(String handle);
}
