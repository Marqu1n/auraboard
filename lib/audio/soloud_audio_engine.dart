import 'dart:io';

import 'package:auraboard/domain/audio_engine.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Thin abstraction over native `flutter_soloud` calls so [SoLoudAudioEngine]
/// can be unit-tested deterministically without loading native FFI libraries.
abstract interface class SoLoudBridge {
  bool get isInitialized;
  Future<void> init();
  Future<void> deinit();
  Future<String> loadAsset(String assetPath);
  Future<String> loadFile(String filePath);
  Future<void> disposeSource(String sourceId);
  Duration getLength(String sourceId);
  Future<String> play(
    String sourceId, {
    required double volume,
    required bool looping,
  });
  Future<void> stop(String handle);
  void setVolume(String handle, double volume);
  void fadeVolume(String handle, double targetVolume, Duration duration);
  void scheduleStop(String handle, Duration delay);
  void setGlobalVolume(double volume);
  void setPause(String handle, bool pause);
  bool isValidVoiceHandle(String handle);
  Duration getPosition(String handle);
}

/// Production [SoLoudBridge] backed by [SoLoud.instance].
class FlutterSoLoudBridge implements SoLoudBridge {
  FlutterSoLoudBridge({SoLoud? soloud}) : _soloud = soloud ?? SoLoud.instance;

  final SoLoud _soloud;
  final Map<String, AudioSource> _sources = <String, AudioSource>{};
  final Map<String, SoundHandle> _handles = <String, SoundHandle>{};
  int _nextSourceId = 1;
  int _nextHandleId = 1;

  @override
  bool get isInitialized => _soloud.isInitialized;

  @override
  Future<void> init() async {
    if (!_soloud.isInitialized) {
      await _soloud.init();
    }
  }

  @override
  Future<void> deinit() async {
    if (_soloud.isInitialized) {
      await _soloud.deinitAsync();
    }
    _sources.clear();
    _handles.clear();
  }

  @override
  Future<String> loadAsset(String assetPath) async {
    final source = await _soloud.loadAsset(assetPath);
    final sourceId = 'soloud_asset_${_nextSourceId++}';
    _sources[sourceId] = source;
    return sourceId;
  }

  @override
  Future<String> loadFile(String filePath) async {
    final source = await _soloud.loadFile(filePath);
    final sourceId = 'soloud_file_${_nextSourceId++}';
    _sources[sourceId] = source;
    return sourceId;
  }

  @override
  Future<void> disposeSource(String sourceId) async {
    final source = _sources.remove(sourceId);
    if (source != null && _soloud.isInitialized) {
      await _soloud.disposeSource(source);
    }
  }

  @override
  Duration getLength(String sourceId) {
    final source = _sources[sourceId];
    if (source == null || !_soloud.isInitialized) {
      return Duration.zero;
    }
    return _soloud.getLength(source);
  }

  @override
  Future<String> play(
    String sourceId, {
    required double volume,
    required bool looping,
  }) async {
    final source = _sources[sourceId];
    if (source == null) {
      throw StateError('Unknown audio source: $sourceId');
    }
    final soundHandle = _soloud.play(source, volume: volume, looping: looping);
    final handleId = 'soloud_handle_${_nextHandleId++}';
    _handles[handleId] = soundHandle;
    return handleId;
  }

  @override
  Future<void> stop(String handle) async {
    final soundHandle = _handles.remove(handle);
    if (soundHandle != null && _soloud.isInitialized) {
      await _soloud.stop(soundHandle);
    }
  }

  @override
  void setVolume(String handle, double volume) {
    final soundHandle = _handles[handle];
    if (soundHandle != null &&
        _soloud.isInitialized &&
        _soloud.getIsValidVoiceHandle(soundHandle)) {
      _soloud.setVolume(soundHandle, volume);
    }
  }

  @override
  void fadeVolume(String handle, double targetVolume, Duration duration) {
    final soundHandle = _handles[handle];
    if (soundHandle != null &&
        _soloud.isInitialized &&
        _soloud.getIsValidVoiceHandle(soundHandle)) {
      _soloud.fadeVolume(soundHandle, targetVolume, duration);
    }
  }

  @override
  void scheduleStop(String handle, Duration delay) {
    final soundHandle = _handles[handle];
    if (soundHandle != null &&
        _soloud.isInitialized &&
        _soloud.getIsValidVoiceHandle(soundHandle)) {
      _soloud.scheduleStop(soundHandle, delay);
    }
  }

  @override
  void setGlobalVolume(double volume) {
    if (_soloud.isInitialized) {
      _soloud.setGlobalVolume(volume);
    }
  }

  @override
  void setPause(String handle, bool pause) {
    final soundHandle = _handles[handle];
    if (soundHandle != null &&
        _soloud.isInitialized &&
        _soloud.getIsValidVoiceHandle(soundHandle)) {
      _soloud.setPause(soundHandle, pause);
    }
  }

  @override
  bool isValidVoiceHandle(String handle) {
    final soundHandle = _handles[handle];
    if (soundHandle == null || !_soloud.isInitialized) {
      return false;
    }
    final valid = _soloud.getIsValidVoiceHandle(soundHandle);
    if (!valid) {
      _handles.remove(handle);
    }
    return valid;
  }

  @override
  Duration getPosition(String handle) {
    final soundHandle = _handles[handle];
    if (soundHandle == null ||
        !_soloud.isInitialized ||
        !_soloud.getIsValidVoiceHandle(soundHandle)) {
      return Duration.zero;
    }
    return _soloud.getPosition(soundHandle);
  }
}

/// Concrete [AudioEngine] backed by `flutter_soloud` via [SoLoudBridge].
class SoLoudAudioEngine implements AudioEngine {
  SoLoudAudioEngine({
    SoLoudBridge? bridge,
    bool Function(String path)? fileExists,
  }) : _bridge = bridge ?? FlutterSoLoudBridge(),
       _fileExists = fileExists ?? _defaultFileExists;

  final SoLoudBridge _bridge;
  final bool Function(String path) _fileExists;

  final Map<(String, bool), String> _sourceCache = <(String, bool), String>{};
  final Map<String, (String, bool)> _sourceKeyById = <String, (String, bool)>{};
  final Map<(String, bool), Future<String>> _inFlightLoads =
      <(String, bool), Future<String>>{};
  final Set<String> _trackedHandles = <String>{};
  final Set<String> _pausedHandles = <String>{};

  Future<void>? _pendingInit;

  static bool _defaultFileExists(String path) => File(path).existsSync();

  @override
  Future<void> initialize() async {
    if (_bridge.isInitialized) {
      return;
    }
    final pending = _pendingInit;
    if (pending != null) {
      await pending;
      return;
    }
    final initFuture = _bridge.init();
    _pendingInit = initFuture;
    try {
      await initFuture;
    } finally {
      if (identical(_pendingInit, initFuture)) {
        _pendingInit = null;
      }
    }
  }

  @override
  Future<void> dispose() async {
    _sourceCache.clear();
    _sourceKeyById.clear();
    _inFlightLoads.clear();
    _trackedHandles.clear();
    _pausedHandles.clear();
    if (_bridge.isInitialized) {
      await _bridge.deinit();
    }
  }

  @override
  Future<String> loadSource(String path, {bool isAsset = false}) async {
    if (!isAsset && !_fileExists(path)) {
      throw AudioLoadException(path, 'Audio file does not exist: $path');
    }

    await initialize();

    final cacheKey = (path, isAsset);
    final cached = _sourceCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final inFlight = _inFlightLoads[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final loadFuture = _loadUncached(path: path, isAsset: isAsset);
    _inFlightLoads[cacheKey] = loadFuture;
    try {
      final sourceId = await loadFuture;
      if (identical(_inFlightLoads[cacheKey], loadFuture)) {
        _sourceCache[cacheKey] = sourceId;
        _sourceKeyById[sourceId] = cacheKey;
      }
      return sourceId;
    } finally {
      if (identical(_inFlightLoads[cacheKey], loadFuture)) {
        _inFlightLoads.remove(cacheKey);
      }
    }
  }

  Future<String> _loadUncached({
    required String path,
    required bool isAsset,
  }) async {
    try {
      return isAsset
          ? await _bridge.loadAsset(path)
          : await _bridge.loadFile(path);
    } on AudioLoadException {
      rethrow;
    } catch (error) {
      throw AudioLoadException(path, error.toString());
    }
  }

  @override
  Future<void> unloadSource(String sourceId) async {
    final cacheKey = _sourceKeyById.remove(sourceId);
    if (cacheKey != null) {
      _sourceCache.remove(cacheKey);
    }
    if (_bridge.isInitialized) {
      await _bridge.disposeSource(sourceId);
    }
  }

  @override
  Duration getSourceDuration(String sourceId) {
    if (!_bridge.isInitialized) {
      return Duration.zero;
    }
    return _bridge.getLength(sourceId);
  }

  @override
  Future<String> play(
    String sourceId, {
    double volume = 1.0,
    bool looping = false,
  }) async {
    await initialize();
    if (_trackedHandles.length > 32) {
      _trackedHandles.removeWhere((h) => !_bridge.isValidVoiceHandle(h));
    }
    try {
      final handle = await _bridge.play(
        sourceId,
        volume: _clampVolume(volume),
        looping: looping,
      );
      _trackedHandles.add(handle);
      return handle;
    } on AudioLoadException {
      rethrow;
    } catch (error) {
      final path = _sourceKeyById[sourceId]?.$1 ?? sourceId;
      throw AudioLoadException(path, error.toString());
    }
  }

  @override
  Future<void> stop(String handle) async {
    _trackedHandles.remove(handle);
    _pausedHandles.remove(handle);
    if (_bridge.isInitialized) {
      await _bridge.stop(handle);
    }
  }

  @override
  Future<void> setVolume(String handle, double volume) async {
    if (!_bridge.isInitialized) {
      return;
    }
    _bridge.setVolume(handle, _clampVolume(volume));
  }

  @override
  Future<void> fadeVolume(
    String handle,
    double targetVolume,
    Duration duration,
  ) async {
    if (!_bridge.isInitialized) {
      return;
    }
    final effectiveDuration = duration.isNegative ? Duration.zero : duration;
    _bridge.fadeVolume(handle, _clampVolume(targetVolume), effectiveDuration);
  }

  @override
  Future<void> scheduleStop(String handle, Duration delay) async {
    if (!_bridge.isInitialized) {
      return;
    }
    final effectiveDelay = delay.isNegative ? Duration.zero : delay;
    _bridge.scheduleStop(handle, effectiveDelay);
  }

  @override
  Future<void> setMasterVolume(double volume) async {
    await initialize();
    _bridge.setGlobalVolume(_clampVolume(volume));
  }

  @override
  Future<void> pauseAll() async {
    if (!_bridge.isInitialized) {
      return;
    }
    for (final handle in _trackedHandles.toList()) {
      if (_bridge.isValidVoiceHandle(handle)) {
        if (_pausedHandles.add(handle)) {
          _bridge.setPause(handle, true);
        }
      } else {
        _trackedHandles.remove(handle);
        _pausedHandles.remove(handle);
      }
    }
  }

  @override
  Future<void> resumeAll() async {
    if (!_bridge.isInitialized || _pausedHandles.isEmpty) {
      return;
    }
    final handlesToResume = _pausedHandles.toList();
    _pausedHandles.clear();
    for (final handle in handlesToResume) {
      if (_bridge.isValidVoiceHandle(handle)) {
        _bridge.setPause(handle, false);
      } else {
        _trackedHandles.remove(handle);
      }
    }
  }

  @override
  bool isHandleActive(String handle) {
    if (!_bridge.isInitialized) {
      return false;
    }
    final valid = _bridge.isValidVoiceHandle(handle);
    if (!valid) {
      _trackedHandles.remove(handle);
      _pausedHandles.remove(handle);
    }
    return valid;
  }

  @override
  Duration getPosition(String handle) {
    if (!_bridge.isInitialized) {
      return Duration.zero;
    }
    return _bridge.getPosition(handle);
  }
}

double _clampVolume(double volume) => volume.clamp(0.0, 1.0).toDouble();
