import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:auraboard/domain/models.dart';
import 'package:auraboard/domain/playback_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Platform-agnostic classification of OS audio focus interruptions.
enum AudioInterruptionKind { duck, pause, unknown }

/// Normalized audio focus interruption event emitted by [AudioFocusGateway].
class SessionInterruptionEvent {
  const SessionInterruptionEvent({required this.begin, required this.kind});

  final bool begin;
  final AudioInterruptionKind kind;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionInterruptionEvent &&
            other.begin == begin &&
            other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(begin, kind);

  @override
  String toString() => 'SessionInterruptionEvent(begin: $begin, kind: $kind)';
}

/// Abstraction over platform audio session configuration, focus activation,
/// and interruption events (e.g. phone calls and notifications).
abstract interface class AudioFocusGateway {
  Future<void> configureForMediaPlayback();
  Future<bool> setActive(bool active);
  Stream<SessionInterruptionEvent> get interruptions;
  Future<void> dispose();
}

/// Abstraction over platform background media playback service and OS
/// lock-screen / notification controls.
abstract interface class BackgroundServiceGateway {
  Future<void> updatePlayback({
    required bool isPlaying,
    required String summaryTitle,
    required int activeCount,
  });
  Future<void> dispose();
}

/// Abstraction over platform screen wakelock control.
abstract interface class WakelockGateway {
  Future<void> setEnabled(bool enabled);
}

/// Coordinates OS audio focus, interruption pause/resume, foreground media
/// notification updates, and keep-screen-awake wakelock during live sessions.
class SessionResilienceCoordinator {
  SessionResilienceCoordinator({
    required AudioFocusGateway audioFocusGateway,
    required BackgroundServiceGateway backgroundServiceGateway,
    required WakelockGateway wakelockGateway,
    required Future<void> Function() onPauseForInterruption,
    required Future<void> Function() onResumeAfterInterruption,
  }) : _audioFocusGateway = audioFocusGateway,
       _backgroundServiceGateway = backgroundServiceGateway,
       _wakelockGateway = wakelockGateway,
       _onPauseForInterruption = onPauseForInterruption,
       _onResumeAfterInterruption = onResumeAfterInterruption;

  final AudioFocusGateway _audioFocusGateway;
  final BackgroundServiceGateway _backgroundServiceGateway;
  final WakelockGateway _wakelockGateway;
  final Future<void> Function() _onPauseForInterruption;
  final Future<void> Function() _onResumeAfterInterruption;

  StreamSubscription<SessionInterruptionEvent>? _interruptionSubscription;
  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isInterrupted = false;
  bool _isAudioFocusActive = false;
  bool? _desiredKeepScreenAwake;
  bool? _lastAppliedKeepScreenAwake;
  (bool, String, int)? _lastBackgroundUpdate;
  (PlaybackState, Map<String, SoundPad>)? _pendingSync;
  Future<void>? _activeSyncLoop;

  /// Configures the platform audio session, subscribes to audio focus
  /// interruptions, and applies the initial [keepScreenAwake] wakelock state.
  Future<void> initialize({required bool keepScreenAwake}) async {
    if (_isDisposed) {
      return;
    }
    _desiredKeepScreenAwake ??= keepScreenAwake;

    if (!_isInitialized) {
      _isInitialized = true;
      await _audioFocusGateway.configureForMediaPlayback();
      if (_isDisposed) {
        return;
      }
      _interruptionSubscription ??= _audioFocusGateway.interruptions.listen(
        _handleInterruption,
      );
    }

    final targetAwake = _desiredKeepScreenAwake ?? keepScreenAwake;
    if (_lastAppliedKeepScreenAwake != targetAwake) {
      _lastAppliedKeepScreenAwake = targetAwake;
      await _wakelockGateway.setEnabled(targetAwake);
    }
  }

  /// Updates the keep-screen-awake wakelock state.
  Future<void> setKeepScreenAwake(bool enabled) async {
    if (_isDisposed) {
      return;
    }
    _desiredKeepScreenAwake = enabled;
    _lastAppliedKeepScreenAwake = enabled;
    await _wakelockGateway.setEnabled(enabled);
  }

  /// Synchronizes OS audio focus and background media notification state with
  /// the current [playbackState].
  ///
  /// Concurrent calls are serialized and coalesced so `setActive` and
  /// `updatePlayback` execute strictly in order and always converge to the
  /// newest playback snapshot.
  Future<void> syncPlaybackState(
    PlaybackState playbackState, {
    required Map<String, SoundPad> padsById,
  }) async {
    if (_isDisposed) {
      return;
    }

    _pendingSync = (playbackState, Map<String, SoundPad>.of(padsById));
    if (_activeSyncLoop != null) {
      await _activeSyncLoop;
      return;
    }

    final loop = _drainSyncQueue();
    _activeSyncLoop = loop;
    try {
      await loop;
    } finally {
      if (identical(_activeSyncLoop, loop)) {
        _activeSyncLoop = null;
      }
    }
  }

  Future<void> _drainSyncQueue() async {
    while (!_isDisposed) {
      final next = _pendingSync;
      if (next == null) {
        return;
      }
      _pendingSync = null;
      await _applyPlaybackSync(next.$1, padsById: next.$2);
    }
  }

  Future<void> _applyPlaybackSync(
    PlaybackState playbackState, {
    required Map<String, SoundPad> padsById,
  }) async {
    if (_isDisposed) {
      return;
    }

    final activeVoices = playbackState.activeByPad.values
        .where(_isActivePlaybackPhase)
        .toList();
    final isPlaying = activeVoices.isNotEmpty;
    final activeCount = activeVoices.length;

    // Clear stale interruption state when playback stops completely or freshly
    // re-acquires focus after a permanent focus loss (e.g. Android
    // AUDIOFOCUS_LOSS emits begin=true, unknown with no matching end event).
    if (!isPlaying || !_isAudioFocusActive) {
      _isInterrupted = false;
    }

    if (isPlaying != _isAudioFocusActive) {
      _isAudioFocusActive = isPlaying;
      await _audioFocusGateway.setActive(isPlaying);
      if (_isDisposed) {
        return;
      }
    }

    if (!isPlaying && _lastBackgroundUpdate == null) {
      return;
    }

    final summaryTitle = _buildSummaryTitle(activeVoices, padsById: padsById);
    final nextUpdate = (isPlaying, summaryTitle, activeCount);
    if (_lastBackgroundUpdate == nextUpdate) {
      return;
    }
    _lastBackgroundUpdate = nextUpdate;

    await _backgroundServiceGateway.updatePlayback(
      isPlaying: isPlaying,
      summaryTitle: summaryTitle,
      activeCount: activeCount,
    );
  }

  /// Cancels interruption subscriptions and disposes platform gateways.
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _isInterrupted = false;
    _pendingSync = null;
    await _interruptionSubscription?.cancel();
    _interruptionSubscription = null;
    await _audioFocusGateway.dispose();
    await _backgroundServiceGateway.dispose();
  }

  void _handleInterruption(SessionInterruptionEvent event) {
    if (_isDisposed) {
      return;
    }

    switch (event.kind) {
      case AudioInterruptionKind.duck:
        // Never pause or stop tabletop music/ambience for transient ducks.
        return;
      case AudioInterruptionKind.pause:
        if (event.begin) {
          if (!_isInterrupted) {
            _isInterrupted = true;
            unawaited(_onPauseForInterruption());
          }
        } else if (_isInterrupted) {
          _isInterrupted = false;
          unawaited(_onResumeAfterInterruption());
        }
      case AudioInterruptionKind.unknown:
        if (event.begin) {
          if (!_isInterrupted) {
            _isInterrupted = true;
            unawaited(_onPauseForInterruption());
          }
        } else {
          // Do not auto-resume after an indefinite/unknown interruption end.
          _isInterrupted = false;
        }
    }
  }

  static bool _isActivePlaybackPhase(ActiveVoiceState voice) {
    return voice.phase == PadPlaybackPhase.fadingIn ||
        voice.phase == PadPlaybackPhase.playing ||
        voice.phase == PadPlaybackPhase.fadingOut;
  }

  static String _buildSummaryTitle(
    List<ActiveVoiceState> activeVoices, {
    required Map<String, SoundPad> padsById,
  }) {
    if (activeVoices.isEmpty) {
      return 'AuraBoard';
    }

    final activePads = <SoundPad>[];
    for (final voice in activeVoices) {
      final pad = padsById[voice.padId];
      if (pad != null) {
        activePads.add(pad);
      }
    }

    if (activePads.isEmpty) {
      return activeVoices.length == 1
          ? '1 active sound'
          : '${activeVoices.length} active sounds';
    }

    activePads.sort((a, b) {
      final typeCompare = _summaryTypePriority(
        a.type,
      ).compareTo(_summaryTypePriority(b.type));
      if (typeCompare != 0) {
        return typeCompare;
      }
      return a.label.compareTo(b.label);
    });

    final primaryLabel = activePads.first.label;
    final remaining = activeVoices.length - 1;
    if (remaining <= 0) {
      return primaryLabel;
    }
    return '$primaryLabel + $remaining more';
  }

  static int _summaryTypePriority(PadType type) {
    return switch (type) {
      PadType.music => 0,
      PadType.ambience => 1,
      PadType.effect => 2,
    };
  }
}

/// Production [AudioFocusGateway] backed by `package:audio_session`.
class PlatformAudioFocusGateway implements AudioFocusGateway {
  PlatformAudioFocusGateway();

  final StreamController<SessionInterruptionEvent> _controller =
      StreamController<SessionInterruptionEvent>.broadcast();
  audio_session.AudioSession? _session;
  StreamSubscription<audio_session.AudioInterruptionEvent>? _subscription;
  bool _disposed = false;

  Future<audio_session.AudioSession?> _getSession() async {
    if (_disposed) {
      return null;
    }
    if (_session != null) {
      return _session;
    }
    try {
      final session = await audio_session.AudioSession.instance;
      if (_disposed) {
        return null;
      }
      _session = session;
      _subscription ??= session.interruptionEventStream.listen((event) {
        if (!_disposed && !_controller.isClosed) {
          _controller.add(
            SessionInterruptionEvent(
              begin: event.begin,
              kind: _mapInterruptionType(event.type),
            ),
          );
        }
      });
      return session;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> configureForMediaPlayback() async {
    final session = await _getSession();
    if (session == null || _disposed) {
      return;
    }
    try {
      await session.configure(
        const audio_session.AudioSessionConfiguration.music().copyWith(
          androidWillPauseWhenDucked: false,
        ),
      );
    } on MissingPluginException {
      // Safe no-op in headless test environments.
    } on PlatformException {
      // Safe no-op if platform audio session cannot be configured.
    }
  }

  @override
  Future<bool> setActive(bool active) async {
    final session = await _getSession();
    if (session == null || _disposed) {
      return false;
    }
    try {
      return await session.setActive(active);
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Stream<SessionInterruptionEvent> get interruptions => _controller.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  static AudioInterruptionKind _mapInterruptionType(
    audio_session.AudioInterruptionType type,
  ) {
    return switch (type) {
      audio_session.AudioInterruptionType.duck => AudioInterruptionKind.duck,
      audio_session.AudioInterruptionType.pause => AudioInterruptionKind.pause,
      audio_session.AudioInterruptionType.unknown =>
        AudioInterruptionKind.unknown,
    };
  }
}

class _AuraBoardAudioHandler extends audio_service.BaseAudioHandler {
  Future<void> Function()? onStopAll;

  @override
  Future<void> stop() async {
    final callback = onStopAll;
    if (callback != null) {
      await callback();
    }
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: audio_service.AudioProcessingState.idle,
        controls: const <audio_service.MediaControl>[
          audio_service.MediaControl.stop,
        ],
      ),
    );
    await super.stop();
  }
}

/// Production [BackgroundServiceGateway] backed by `package:audio_service`.
///
/// Lazily initializes `AudioService` only when playback first becomes active
/// so idle startup and headless widget tests never spawn platform services.
class PlatformBackgroundServiceGateway implements BackgroundServiceGateway {
  PlatformBackgroundServiceGateway({Future<void> Function()? onStopAll})
    : _onStopAll = onStopAll;

  static _AuraBoardAudioHandler? _sharedHandler;
  static Future<_AuraBoardAudioHandler?>? _pendingInit;
  static bool _platformUnsupported = false;

  final Future<void> Function()? _onStopAll;
  bool _disposed = false;
  int _updateSequence = 0;

  Future<_AuraBoardAudioHandler?> _ensureInitialized() async {
    if (_platformUnsupported || _disposed) {
      return null;
    }
    if (_sharedHandler != null) {
      return _sharedHandler;
    }
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      _platformUnsupported = true;
      return null;
    }
    final pending = _pendingInit;
    if (pending != null) {
      return pending;
    }

    final future = _initAudioService();
    _pendingInit = future;
    try {
      return await future;
    } finally {
      if (identical(_pendingInit, future)) {
        _pendingInit = null;
      }
    }
  }

  Future<_AuraBoardAudioHandler?> _initAudioService() async {
    try {
      final handler = await audio_service.AudioService.init(
        builder: _AuraBoardAudioHandler.new,
        config: const audio_service.AudioServiceConfig(
          androidNotificationChannelId: 'com.auraboard.auraboard.playback',
          androidNotificationChannelName: 'AuraBoard Playback',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
      _sharedHandler = handler;
      return handler;
    } on MissingPluginException {
      _platformUnsupported = true;
      return null;
    } on PlatformException {
      _platformUnsupported = true;
      return null;
    } on StateError {
      _platformUnsupported = true;
      return null;
    } on AssertionError {
      return _sharedHandler;
    }
  }

  @override
  Future<void> updatePlayback({
    required bool isPlaying,
    required String summaryTitle,
    required int activeCount,
  }) async {
    if (_disposed) {
      return;
    }
    final mySeq = ++_updateSequence;
    if (!isPlaying && _sharedHandler == null && _pendingInit == null) {
      return;
    }

    final handler = await _ensureInitialized();
    if (handler == null || _disposed || mySeq != _updateSequence) {
      return;
    }
    handler.onStopAll = _onStopAll;

    try {
      final subtitle = activeCount == 1
          ? '1 active sound'
          : (activeCount > 1 ? '$activeCount active sounds' : 'Idle');
      handler.mediaItem.add(
        audio_service.MediaItem(
          id: 'auraboard_session',
          album: 'AuraBoard',
          title: summaryTitle.isNotEmpty ? summaryTitle : 'AuraBoard',
          artist: subtitle,
        ),
      );
      handler.playbackState.add(
        audio_service.PlaybackState(
          controls: const <audio_service.MediaControl>[
            audio_service.MediaControl.stop,
          ],
          systemActions: const <audio_service.MediaAction>{
            audio_service.MediaAction.stop,
          },
          androidCompactActionIndices: const <int>[0],
          processingState: isPlaying
              ? audio_service.AudioProcessingState.ready
              : audio_service.AudioProcessingState.idle,
          playing: isPlaying,
        ),
      );
    } on MissingPluginException {
      // Safe no-op in headless/unsupported environments.
    } on PlatformException {
      // Safe no-op on transient platform channel failures.
    } on StateError {
      // Safe no-op if handler stream is unavailable.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final handler = _sharedHandler;
    if (handler != null && identical(handler.onStopAll, _onStopAll)) {
      handler.onStopAll = null;
    }
  }
}

/// Production [WakelockGateway] backed by `package:wakelock_plus`.
class PlatformWakelockGateway implements WakelockGateway {
  const PlatformWakelockGateway();

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } on MissingPluginException {
      // Safe no-op in headless test environments.
    } on PlatformException {
      // Safe no-op if platform wakelock cannot be toggled.
    } on UnsupportedError {
      // Safe no-op on unsupported platforms.
    }
  }
}
