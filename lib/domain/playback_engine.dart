import 'dart:async';

import 'package:auraboard/domain/audio_engine.dart';
import 'package:auraboard/domain/clock.dart';
import 'package:auraboard/domain/models.dart';

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

/// Pure Dart playback state machine coordinating Effects, Music crossfades,
/// Ambience layering, fades, progress updates, and audio interruptions.
class PlaybackEngine {
  PlaybackEngine({
    required AudioEngine audioEngine,
    required Clock clock,
    BoardSettings settings = const BoardSettings(),
    void Function(PlaybackState state)? onStateChanged,
    Duration progressTickInterval = const Duration(milliseconds: 50),
  }) : _audioEngine = audioEngine,
       _clock = clock,
       _settings = settings,
       _onStateChanged = onStateChanged,
       _progressTickInterval = progressTickInterval;

  final AudioEngine _audioEngine;
  final Clock _clock;
  final void Function(PlaybackState state)? _onStateChanged;
  final Duration _progressTickInterval;

  BoardSettings _settings;
  PlaybackState _state = const PlaybackState();

  final Map<String, _VoiceRecord> _voices = <String, _VoiceRecord>{};
  final Map<String, int> _padOpTokens = <String, int>{};
  final Map<String, int> _padStopTokens = <String, int>{};

  ClockTimer? _progressTimer;
  int _globalStopToken = 0;
  int _musicGeneration = 0;
  bool _isInterrupted = false;
  DateTime? _interruptedAt;
  bool _isDisposed = false;

  /// Current immutable snapshot of active voices and error states.
  PlaybackState get state => _state;

  /// Current [BoardSettings] governing default fade/crossfade durations and
  /// master volume.
  BoardSettings get settings => _settings;

  /// Initializes the backing [AudioEngine] and applies the configured master
  /// volume.
  Future<void> initialize() async {
    if (_isDisposed) {
      return;
    }
    await _audioEngine.initialize();
    await _audioEngine.setMasterVolume(_clampVolume(_settings.masterVolume));
  }

  /// Updates fade defaults and master volume from [settings].
  Future<void> updateSettings(BoardSettings settings) async {
    if (_isDisposed) {
      return;
    }
    _settings = settings;
    await _audioEngine.setMasterVolume(_clampVolume(settings.masterVolume));
  }

  /// Cancels all scheduled timers and optionally disposes the backing
  /// [AudioEngine].
  Future<void> dispose({bool disposeAudioEngine = true}) async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _globalStopToken++;
    _musicGeneration++;
    _progressTimer?.cancel();
    _progressTimer = null;

    for (final voice in _voices.values) {
      voice.cancelTimers();
    }
    _voices.clear();
    _isInterrupted = false;
    _interruptedAt = null;

    if (disposeAudioEngine) {
      await _audioEngine.dispose();
    }
  }

  /// Handles a play-mode tap on [pad] according to its [PadType].
  Future<void> tapPad(SoundPad pad) async {
    if (_isDisposed) {
      return;
    }
    switch (pad.type) {
      case PadType.effect:
        await _tapEffectPad(pad);
      case PadType.music:
        await _tapMusicPad(pad);
      case PadType.ambience:
        await _tapAmbiencePad(pad);
    }
  }

  /// Explicitly stops [padId].
  ///
  /// Effects stop immediately by default unless [SoundPad.fadeOutMsOverride]
  /// is positive. Music and Ambience fade out smoothly over
  /// `fadeOutMsOverride ?? settings.defaultFadeOutMs`.
  Future<void> stopPad(String padId) async {
    if (_isDisposed) {
      return;
    }
    _nextPadStopToken(padId);
    _nextPadOpToken(padId);

    final voice = _voices[padId];
    if (voice == null ||
        voice.phase == PadPlaybackPhase.error ||
        voice.phase == PadPlaybackPhase.fadingOut) {
      return;
    }

    final fadeOutMs = switch (voice.pad.type) {
      PadType.effect => voice.pad.fadeOutMsOverride ?? 0,
      PadType.music || PadType.ambience =>
        voice.pad.fadeOutMsOverride ?? _settings.defaultFadeOutMs,
    };

    await _fadeOutVoice(voice, _nonNegativeMs(fadeOutMs));
  }

  /// Smoothly fades out all currently playing or fading-in voices (music,
  /// ambience, and effects) without restarting pads already fading out.
  Future<void> stopAll() async {
    if (_isDisposed) {
      return;
    }
    _globalStopToken++;
    _musicGeneration++;

    final voicesToFade = _voices.values
        .where(
          (voice) =>
              voice.phase == PadPlaybackPhase.playing ||
              voice.phase == PadPlaybackPhase.fadingIn,
        )
        .toList();

    for (final voice in voicesToFade) {
      final fadeOutMs =
          voice.pad.fadeOutMsOverride ?? _settings.defaultFadeOutMs;
      await _fadeOutVoice(voice, _nonNegativeMs(fadeOutMs));
    }

    if (!_hasActiveAudioVoices) {
      _isInterrupted = false;
      _interruptedAt = null;
    }
  }

  /// Sets master volume clamped to `[0.0, 1.0]`.
  Future<void> setMasterVolume(double volume) async {
    if (_isDisposed) {
      return;
    }
    final clamped = _clampVolume(volume);
    _settings = _settings.copyWith(masterVolume: clamped);
    await _audioEngine.setMasterVolume(clamped);
  }

  /// Sets per-pad volume clamped to `[0.0, 1.0]` for any active handles of
  /// [padId]. No-op if [padId] is idle or in error.
  Future<void> setPadVolume(String padId, double volume) async {
    if (_isDisposed) {
      return;
    }
    final voice = _voices[padId];
    if (voice == null ||
        voice.phase == PadPlaybackPhase.error ||
        voice.layers.isEmpty) {
      return;
    }

    final clamped = _clampVolume(volume);
    voice.volume = clamped;
    for (final layer in voice.layers.toList()) {
      await _audioEngine.setVolume(layer.handle, clamped);
    }
    _emitState();
  }

  /// Pauses all active voices and timers when interrupted by the OS (e.g. a
  /// phone call). Safe no-op when idle or already interrupted.
  Future<void> pauseForInterruption() async {
    if (_isDisposed || _isInterrupted || !_hasActiveAudioVoices) {
      return;
    }

    _isInterrupted = true;
    final now = _clock.now();
    _interruptedAt = now;

    _progressTimer?.cancel();
    _progressTimer = null;

    for (final voice in _voices.values) {
      voice.pauseTimers(now);
    }

    await _audioEngine.pauseAll();
  }

  /// Resumes voices and timers paused by [pauseForInterruption]. Safe no-op
  /// when not currently interrupted.
  Future<void> resumeAfterInterruption() async {
    if (_isDisposed || !_isInterrupted) {
      return;
    }

    _isInterrupted = false;
    final now = _clock.now();
    final interruptedAt = _interruptedAt;
    _interruptedAt = null;
    final pauseDelta = interruptedAt != null
        ? now.difference(interruptedAt)
        : Duration.zero;

    if (!_hasActiveAudioVoices) {
      return;
    }

    await _audioEngine.resumeAll();

    for (final entry in _voices.entries.toList()) {
      final padId = entry.key;
      final voice = entry.value;
      if (!identical(_voices[padId], voice)) {
        continue;
      }
      _resumeVoiceTimers(padId, voice, now, pauseDelta);
    }

    _syncProgressTimer();
  }

  /// Resets an errored pad back to [PadPlaybackPhase.idle]. No-op for pads
  /// that are not in [PadPlaybackPhase.error].
  void clearPadError(String padId) {
    if (_isDisposed) {
      return;
    }
    final voice = _voices[padId];
    if (voice == null || voice.phase != PadPlaybackPhase.error) {
      return;
    }
    _voices.remove(padId);
    _emitState();
  }

  Future<void> _tapEffectPad(SoundPad pad) async {
    final isRestart = pad.retriggerMode == RetriggerMode.restart;
    final myGlobalStop = _globalStopToken;
    final myPadStop = _padStopToken(pad.id);
    final myOpToken = isRestart ? _nextPadOpToken(pad.id) : null;

    final String sourceId;
    try {
      sourceId = await _audioEngine.loadSource(
        pad.audioPath,
        isAsset: pad.isAsset,
      );
    } on AudioLoadException catch (error) {
      if (_isEffectRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
      )) {
        return;
      }
      _recordPadError(pad, error);
      return;
    }

    if (_isEffectRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
    )) {
      return;
    }

    final targetVolume = _clampVolume(pad.volume);
    final fadeInDuration = _nonNegativeMs(pad.fadeInMsOverride ?? 0);
    final initialVolume = fadeInDuration > Duration.zero ? 0.0 : targetVolume;
    final duration = _audioEngine.getSourceDuration(sourceId);

    final String handle;
    try {
      handle = await _audioEngine.play(
        sourceId,
        volume: initialVolume,
        looping: false,
      );
    } on AudioLoadException catch (error) {
      if (_isEffectRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
      )) {
        return;
      }
      _recordPadError(pad, error);
      return;
    }

    if (_isEffectRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
    )) {
      await _audioEngine.stop(handle);
      return;
    }

    final existing = _voices[pad.id];
    if (isRestart ||
        existing == null ||
        existing.phase == PadPlaybackPhase.error ||
        existing.phase == PadPlaybackPhase.fadingOut) {
      if (existing != null) {
        existing.cancelTimers();
        for (final oldLayer in existing.layers.toList()) {
          await _audioEngine.stop(oldLayer.handle);
        }
        if (_isEffectRequestStale(
          padId: pad.id,
          globalStop: myGlobalStop,
          padStop: myPadStop,
          opToken: myOpToken,
        )) {
          await _audioEngine.stop(handle);
          return;
        }
      }

      final now = _clock.now();
      final layer = _LayerInstance(
        handle: handle,
        startedAt: now,
        duration: duration,
      );
      final record = _VoiceRecord(
        pad: pad,
        phase: fadeInDuration > Duration.zero
            ? PadPlaybackPhase.fadingIn
            : PadPlaybackPhase.playing,
        volume: targetVolume,
        layers: <_LayerInstance>[layer],
      );
      _voices[pad.id] = record;

      if (fadeInDuration > Duration.zero) {
        await _audioEngine.fadeVolume(handle, targetVolume, fadeInDuration);
        if (_isDisposed ||
            !identical(_voices[pad.id], record) ||
            record.phase != PadPlaybackPhase.fadingIn) {
          return;
        }
        _scheduleFadeIn(pad.id, record, fadeInDuration);
      }
      if (_isDisposed ||
          !identical(_voices[pad.id], record) ||
          !record.layers.contains(layer) ||
          record.phase == PadPlaybackPhase.fadingOut) {
        return;
      }
      _scheduleEffectCompletion(pad.id, record, layer, duration);
      _syncProgressTimer();
      _emitState();
      return;
    }

    // RetriggerMode.layer on an already active effect pad.
    final now = _clock.now();
    final layer = _LayerInstance(
      handle: handle,
      startedAt: now,
      duration: duration,
    );
    existing.pad = pad;
    existing.volume = targetVolume;
    existing.layers.add(layer);

    if (fadeInDuration > Duration.zero) {
      await _audioEngine.fadeVolume(handle, targetVolume, fadeInDuration);
    }
    if (_isDisposed ||
        !identical(_voices[pad.id], existing) ||
        !existing.layers.contains(layer) ||
        existing.phase == PadPlaybackPhase.fadingOut) {
      return;
    }
    _scheduleEffectCompletion(pad.id, existing, layer, duration);
    _syncProgressTimer();
    _emitState();
  }

  Future<void> _tapMusicPad(SoundPad pad) async {
    final existing = _voices[pad.id];
    if (existing != null &&
        (existing.phase == PadPlaybackPhase.playing ||
            existing.phase == PadPlaybackPhase.fadingIn)) {
      final fadeOutMs = pad.fadeOutMsOverride ?? _settings.defaultFadeOutMs;
      await _fadeOutVoice(existing, _nonNegativeMs(fadeOutMs));
      return;
    }

    final myGlobalStop = _globalStopToken;
    final myPadStop = _padStopToken(pad.id);
    final myOpToken = _nextPadOpToken(pad.id);
    final myMusicGen = ++_musicGeneration;

    final String sourceId;
    try {
      sourceId = await _audioEngine.loadSource(
        pad.audioPath,
        isAsset: pad.isAsset,
      );
    } on AudioLoadException catch (error) {
      if (_isMusicRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
        musicGen: myMusicGen,
      )) {
        return;
      }
      _recordPadError(pad, error);
      return;
    }

    if (_isMusicRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
      musicGen: myMusicGen,
    )) {
      return;
    }

    final outgoingMusic = _activeOutgoingMusic(excludingPadId: pad.id);
    final isCrossfade = outgoingMusic.isNotEmpty;
    final fadeMs = isCrossfade
        ? (pad.crossfadeMsOverride ?? _settings.defaultCrossfadeMs)
        : (pad.fadeInMsOverride ?? _settings.defaultFadeInMs);
    final fadeDuration = _nonNegativeMs(fadeMs);
    final targetVolume = _clampVolume(pad.volume);
    final initialVolume = fadeDuration > Duration.zero ? 0.0 : targetVolume;
    final duration = _audioEngine.getSourceDuration(sourceId);

    final String handle;
    try {
      handle = await _audioEngine.play(
        sourceId,
        volume: initialVolume,
        looping: true,
      );
    } on AudioLoadException catch (error) {
      if (_isMusicRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
        musicGen: myMusicGen,
      )) {
        return;
      }
      _recordPadError(pad, error);
      return;
    }

    if (_isMusicRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
      musicGen: myMusicGen,
    )) {
      await _audioEngine.stop(handle);
      return;
    }

    // If this same pad was fading out, stop its old handle cleanly before
    // replacing it with the freshly started handle.
    final priorSelf = _voices[pad.id];
    if (priorSelf != null && priorSelf.phase == PadPlaybackPhase.fadingOut) {
      priorSelf.cancelTimers();
      for (final oldLayer in priorSelf.layers.toList()) {
        await _audioEngine.stop(oldLayer.handle);
      }
      if (_isMusicRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
        musicGen: myMusicGen,
      )) {
        await _audioEngine.stop(handle);
        return;
      }
    }

    // Fade out any currently active (playing/fadingIn) music track(s).
    final currentOutgoing = _activeOutgoingMusic(excludingPadId: pad.id);
    for (final outgoing in currentOutgoing) {
      await _fadeOutVoice(outgoing, fadeDuration);
    }

    if (_isMusicRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
      musicGen: myMusicGen,
    )) {
      await _audioEngine.stop(handle);
      return;
    }

    final now = _clock.now();
    final record = _VoiceRecord(
      pad: pad,
      phase: fadeDuration > Duration.zero
          ? PadPlaybackPhase.fadingIn
          : PadPlaybackPhase.playing,
      volume: targetVolume,
      layers: <_LayerInstance>[
        _LayerInstance(handle: handle, startedAt: now, duration: duration),
      ],
    );
    _voices[pad.id] = record;

    if (fadeDuration > Duration.zero) {
      await _audioEngine.fadeVolume(handle, targetVolume, fadeDuration);
      if (_isDisposed ||
          !identical(_voices[pad.id], record) ||
          record.phase != PadPlaybackPhase.fadingIn) {
        return;
      }
      _scheduleFadeIn(pad.id, record, fadeDuration);
    }

    _emitState();
  }

  Future<void> _tapAmbiencePad(SoundPad pad) async {
    final existing = _voices[pad.id];
    if (existing != null &&
        (existing.phase == PadPlaybackPhase.playing ||
            existing.phase == PadPlaybackPhase.fadingIn)) {
      final fadeOutMs = pad.fadeOutMsOverride ?? _settings.defaultFadeOutMs;
      await _fadeOutVoice(existing, _nonNegativeMs(fadeOutMs));
      return;
    }

    final myGlobalStop = _globalStopToken;
    final myPadStop = _padStopToken(pad.id);
    final myOpToken = _nextPadOpToken(pad.id);

    final String sourceId;
    try {
      sourceId = await _audioEngine.loadSource(
        pad.audioPath,
        isAsset: pad.isAsset,
      );
    } on AudioLoadException catch (error) {
      if (_isAmbienceRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
      )) {
        return;
      }
      _recordPadError(pad, error);
      return;
    }

    if (_isAmbienceRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
    )) {
      return;
    }

    final fadeInMs = pad.fadeInMsOverride ?? _settings.defaultFadeInMs;
    final fadeDuration = _nonNegativeMs(fadeInMs);
    final targetVolume = _clampVolume(pad.volume);
    final initialVolume = fadeDuration > Duration.zero ? 0.0 : targetVolume;
    final duration = _audioEngine.getSourceDuration(sourceId);

    final String handle;
    try {
      handle = await _audioEngine.play(
        sourceId,
        volume: initialVolume,
        looping: true,
      );
    } on AudioLoadException catch (error) {
      if (_isAmbienceRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
      )) {
        return;
      }
      _recordPadError(pad, error);
      return;
    }

    if (_isAmbienceRequestStale(
      padId: pad.id,
      globalStop: myGlobalStop,
      padStop: myPadStop,
      opToken: myOpToken,
    )) {
      await _audioEngine.stop(handle);
      return;
    }

    final priorSelf = _voices[pad.id];
    if (priorSelf != null && priorSelf.phase == PadPlaybackPhase.fadingOut) {
      priorSelf.cancelTimers();
      for (final oldLayer in priorSelf.layers.toList()) {
        await _audioEngine.stop(oldLayer.handle);
      }
      if (_isAmbienceRequestStale(
        padId: pad.id,
        globalStop: myGlobalStop,
        padStop: myPadStop,
        opToken: myOpToken,
      )) {
        await _audioEngine.stop(handle);
        return;
      }
    }

    final now = _clock.now();
    final record = _VoiceRecord(
      pad: pad,
      phase: fadeDuration > Duration.zero
          ? PadPlaybackPhase.fadingIn
          : PadPlaybackPhase.playing,
      volume: targetVolume,
      layers: <_LayerInstance>[
        _LayerInstance(handle: handle, startedAt: now, duration: duration),
      ],
    );
    _voices[pad.id] = record;

    if (fadeDuration > Duration.zero) {
      await _audioEngine.fadeVolume(handle, targetVolume, fadeDuration);
      if (_isDisposed ||
          !identical(_voices[pad.id], record) ||
          record.phase != PadPlaybackPhase.fadingIn) {
        return;
      }
      _scheduleFadeIn(pad.id, record, fadeDuration);
    }

    _emitState();
  }

  Future<void> _fadeOutVoice(_VoiceRecord voice, Duration duration) async {
    final padId = voice.pad.id;
    if (!identical(_voices[padId], voice) ||
        voice.phase == PadPlaybackPhase.fadingOut) {
      return;
    }

    voice.cancelFadeTimer();

    if (duration <= Duration.zero) {
      voice.cancelTimers();
      _voices.remove(padId);
      for (final layer in voice.layers.toList()) {
        await _audioEngine.stop(layer.handle);
      }
      _syncProgressTimer();
      _emitState();
      return;
    }

    voice.phase = PadPlaybackPhase.fadingOut;
    for (final layer in voice.layers.toList()) {
      await _audioEngine.fadeVolume(layer.handle, 0.0, duration);
      await _audioEngine.scheduleStop(layer.handle, duration);
    }

    if (!identical(_voices[padId], voice) || _isDisposed) {
      return;
    }

    _scheduleFadeOut(padId, voice, duration);
    _emitState();
  }

  void _scheduleFadeIn(String padId, _VoiceRecord record, Duration duration) {
    if (_isDisposed || !identical(_voices[padId], record)) {
      return;
    }
    record.cancelFadeTimer();
    record.pendingFadeTargetPhase = PadPlaybackPhase.playing;
    if (_isInterrupted) {
      record.pausedFadeRemaining = duration;
      return;
    }
    record.fadeDeadline = _clock.now().add(duration);
    record.fadeTimer = _clock.createTimer(duration, () {
      _completeFadeIn(padId, record);
    });
  }

  void _completeFadeIn(String padId, _VoiceRecord record) {
    if (_isDisposed || !identical(_voices[padId], record)) {
      return;
    }
    if (record.phase != PadPlaybackPhase.fadingIn) {
      return;
    }
    record.fadeTimer = null;
    record.fadeDeadline = null;
    record.pausedFadeRemaining = null;
    record.pendingFadeTargetPhase = null;
    record.phase = PadPlaybackPhase.playing;
    _emitState();
  }

  void _scheduleFadeOut(String padId, _VoiceRecord record, Duration duration) {
    if (_isDisposed || !identical(_voices[padId], record)) {
      return;
    }
    record.cancelFadeTimer();
    record.pendingFadeTargetPhase = PadPlaybackPhase.idle;
    if (_isInterrupted) {
      record.pausedFadeRemaining = duration;
      return;
    }
    record.fadeDeadline = _clock.now().add(duration);
    record.fadeTimer = _clock.createTimer(duration, () {
      _completeFadeOut(padId, record);
    });
  }

  void _completeFadeOut(String padId, _VoiceRecord record) {
    if (_isDisposed || !identical(_voices[padId], record)) {
      return;
    }
    record.cancelTimers();
    for (final layer in record.layers.toList()) {
      _fireAndForgetStop(layer.handle);
    }
    _voices.remove(padId);
    _syncProgressTimer();
    _emitState();
  }

  void _scheduleEffectCompletion(
    String padId,
    _VoiceRecord record,
    _LayerInstance layer,
    Duration remaining,
  ) {
    if (_isDisposed || !identical(_voices[padId], record)) {
      return;
    }
    layer.cancelTimer();
    if (remaining <= Duration.zero) {
      return;
    }
    if (_isInterrupted) {
      layer.pausedCompletionRemaining = remaining;
      return;
    }
    layer.completionDeadline = _clock.now().add(remaining);
    layer.completionTimer = _clock.createTimer(remaining, () {
      _completeEffectLayer(padId, record, layer);
    });
  }

  void _completeEffectLayer(
    String padId,
    _VoiceRecord record,
    _LayerInstance layer,
  ) {
    if (_isDisposed || !identical(_voices[padId], record)) {
      return;
    }
    layer.cancelTimer();
    final removed = record.layers.remove(layer);
    if (!removed) {
      return;
    }
    if (record.layers.isEmpty) {
      record.cancelTimers();
      _voices.remove(padId);
    }
    _syncProgressTimer();
    _emitState();
  }

  void _resumeVoiceTimers(
    String padId,
    _VoiceRecord voice,
    DateTime now,
    Duration pauseDelta,
  ) {
    if (voice.phase == PadPlaybackPhase.error) {
      return;
    }

    for (final layer in voice.layers.toList()) {
      layer.totalPausedDuration += pauseDelta;
      final remaining = layer.pausedCompletionRemaining;
      layer.pausedCompletionRemaining = null;
      if (remaining != null) {
        if (remaining <= Duration.zero) {
          _completeEffectLayer(padId, voice, layer);
        } else if (identical(_voices[padId], voice)) {
          _scheduleEffectCompletion(padId, voice, layer, remaining);
        }
      }
    }

    if (!identical(_voices[padId], voice)) {
      return;
    }

    final fadeRemaining = voice.pausedFadeRemaining;
    final fadeTarget = voice.pendingFadeTargetPhase;
    voice.pausedFadeRemaining = null;
    if (fadeRemaining != null && fadeTarget != null) {
      if (fadeTarget == PadPlaybackPhase.playing) {
        if (fadeRemaining <= Duration.zero) {
          _completeFadeIn(padId, voice);
        } else {
          _scheduleFadeIn(padId, voice, fadeRemaining);
        }
      } else if (fadeTarget == PadPlaybackPhase.idle) {
        if (fadeRemaining <= Duration.zero) {
          _completeFadeOut(padId, voice);
        } else {
          _scheduleFadeOut(padId, voice, fadeRemaining);
        }
      }
    }
  }

  void _syncProgressTimer() {
    final needsProgressTimer =
        !_isDisposed &&
        !_isInterrupted &&
        _voices.values.any(
          (voice) =>
              voice.pad.type == PadType.effect &&
              voice.phase != PadPlaybackPhase.error &&
              voice.layers.isNotEmpty,
        );

    if (needsProgressTimer) {
      _progressTimer ??= _clock.createPeriodicTimer(
        _progressTickInterval,
        _onProgressTick,
      );
    } else {
      _progressTimer?.cancel();
      _progressTimer = null;
    }
  }

  void _onProgressTick() {
    if (_isDisposed || _isInterrupted) {
      return;
    }
    final now = _clock.now();
    for (final entry in _voices.entries.toList()) {
      final padId = entry.key;
      final voice = entry.value;
      if (voice.pad.type != PadType.effect ||
          voice.phase == PadPlaybackPhase.error) {
        continue;
      }

      voice.layers.removeWhere((layer) {
        final inactive = !_audioEngine.isHandleActive(layer.handle);
        final elapsed = _elapsedForLayer(layer, now);
        final reachedEnd =
            layer.duration > Duration.zero && elapsed >= layer.duration;
        if (inactive || reachedEnd) {
          layer.cancelTimer();
          return true;
        }
        return false;
      });

      if (voice.layers.isEmpty) {
        voice.cancelTimers();
        _voices.remove(padId);
      }
    }

    _syncProgressTimer();
    _emitState();
  }

  void _recordPadError(SoundPad pad, AudioLoadException error) {
    final existing = _voices[pad.id];
    if (existing != null) {
      existing.cancelTimers();
      for (final layer in existing.layers.toList()) {
        _fireAndForgetStop(layer.handle);
      }
    }
    final message = error.message.trim().isNotEmpty
        ? error.message
        : 'Failed to load audio: ${error.path}';
    _voices[pad.id] = _VoiceRecord(
      pad: pad,
      phase: PadPlaybackPhase.error,
      volume: 0.0,
      layers: <_LayerInstance>[],
      errorMessage: message,
    );
    _syncProgressTimer();
    _emitState();
  }

  List<_VoiceRecord> _activeOutgoingMusic({required String excludingPadId}) {
    return _voices.values
        .where(
          (voice) =>
              voice.pad.type == PadType.music &&
              voice.pad.id != excludingPadId &&
              (voice.phase == PadPlaybackPhase.playing ||
                  voice.phase == PadPlaybackPhase.fadingIn),
        )
        .toList();
  }

  bool get _hasActiveAudioVoices => _voices.values.any(
    (voice) => voice.phase != PadPlaybackPhase.error && voice.layers.isNotEmpty,
  );

  bool _isEffectRequestStale({
    required String padId,
    required int globalStop,
    required int padStop,
    required int? opToken,
  }) {
    if (_isDisposed ||
        globalStop != _globalStopToken ||
        padStop != _padStopToken(padId)) {
      return true;
    }
    if (opToken != null && opToken != _padOpTokens[padId]) {
      return true;
    }
    return false;
  }

  bool _isMusicRequestStale({
    required String padId,
    required int globalStop,
    required int padStop,
    required int opToken,
    required int musicGen,
  }) {
    return _isDisposed ||
        globalStop != _globalStopToken ||
        padStop != _padStopToken(padId) ||
        opToken != _padOpTokens[padId] ||
        musicGen != _musicGeneration;
  }

  bool _isAmbienceRequestStale({
    required String padId,
    required int globalStop,
    required int padStop,
    required int opToken,
  }) {
    return _isDisposed ||
        globalStop != _globalStopToken ||
        padStop != _padStopToken(padId) ||
        opToken != _padOpTokens[padId];
  }

  int _nextPadOpToken(String padId) {
    final next = (_padOpTokens[padId] ?? 0) + 1;
    _padOpTokens[padId] = next;
    return next;
  }

  int _padStopToken(String padId) => _padStopTokens[padId] ?? 0;

  int _nextPadStopToken(String padId) {
    final next = (_padStopTokens[padId] ?? 0) + 1;
    _padStopTokens[padId] = next;
    return next;
  }

  Duration _elapsedForLayer(_LayerInstance layer, DateTime now) {
    final referenceTime = _isInterrupted ? (_interruptedAt ?? now) : now;
    final raw =
        referenceTime.difference(layer.startedAt) - layer.totalPausedDuration;
    return raw.isNegative ? Duration.zero : raw;
  }

  Duration _positionForLayer(_LayerInstance layer, DateTime now) {
    final enginePos = _audioEngine.getPosition(layer.handle);
    final clockPos = _elapsedForLayer(layer, now);
    final rawPos = enginePos > Duration.zero ? enginePos : clockPos;
    if (layer.duration > Duration.zero && rawPos > layer.duration) {
      return layer.duration;
    }
    return rawPos.isNegative ? Duration.zero : rawPos;
  }

  void _emitState() {
    if (_isDisposed) {
      return;
    }
    final now = _clock.now();
    final activeByPad = <String, ActiveVoiceState>{};
    for (final entry in _voices.entries) {
      final voice = entry.value;
      if (voice.phase == PadPlaybackPhase.error) {
        activeByPad[entry.key] = ActiveVoiceState(
          padId: voice.pad.id,
          phase: PadPlaybackPhase.error,
          currentVolume: 0.0,
          activeLayerCount: 0,
          errorMessage: voice.errorMessage,
        );
        continue;
      }
      final latestLayer = voice.layers.isNotEmpty ? voice.layers.last : null;
      final position = latestLayer == null
          ? Duration.zero
          : voice.pad.type == PadType.effect
          ? _positionForLayer(latestLayer, now)
          : _audioEngine.getPosition(latestLayer.handle);
      activeByPad[entry.key] = ActiveVoiceState(
        padId: voice.pad.id,
        handle: latestLayer?.handle,
        phase: voice.phase,
        currentVolume: voice.volume,
        activeLayerCount: voice.layers.length,
        position: position,
        duration: latestLayer?.duration ?? Duration.zero,
        startedAt: latestLayer?.startedAt,
      );
    }

    final nextState = PlaybackState(
      activeByPad: Map<String, ActiveVoiceState>.unmodifiable(activeByPad),
    );
    if (nextState == _state) {
      return;
    }
    _state = nextState;
    _onStateChanged?.call(_state);
  }

  void _fireAndForgetStop(String handle) {
    try {
      unawaited(_audioEngine.stop(handle).catchError((Object _) {}));
    } catch (_) {
      // Ignore stop errors during timer-driven cleanup.
    }
  }
}

class _VoiceRecord {
  _VoiceRecord({
    required this.pad,
    required this.phase,
    required this.volume,
    required this.layers,
    this.errorMessage,
  });

  SoundPad pad;
  PadPlaybackPhase phase;
  double volume;
  final List<_LayerInstance> layers;
  final String? errorMessage;

  ClockTimer? fadeTimer;
  DateTime? fadeDeadline;
  Duration? pausedFadeRemaining;
  PadPlaybackPhase? pendingFadeTargetPhase;

  void cancelFadeTimer() {
    fadeTimer?.cancel();
    fadeTimer = null;
    fadeDeadline = null;
    pausedFadeRemaining = null;
    pendingFadeTargetPhase = null;
  }

  void cancelTimers() {
    cancelFadeTimer();
    for (final layer in layers) {
      layer.cancelTimer();
    }
  }

  void pauseTimers(DateTime now) {
    if (fadeTimer != null && fadeDeadline != null) {
      final remaining = fadeDeadline!.difference(now);
      pausedFadeRemaining = remaining.isNegative ? Duration.zero : remaining;
      fadeTimer!.cancel();
      fadeTimer = null;
      fadeDeadline = null;
    }
    for (final layer in layers) {
      layer.pauseTimer(now);
    }
  }
}

class _LayerInstance {
  _LayerInstance({
    required this.handle,
    required this.startedAt,
    required this.duration,
  });

  final String handle;
  final DateTime startedAt;
  final Duration duration;
  Duration totalPausedDuration = Duration.zero;

  ClockTimer? completionTimer;
  DateTime? completionDeadline;
  Duration? pausedCompletionRemaining;

  void cancelTimer() {
    completionTimer?.cancel();
    completionTimer = null;
    completionDeadline = null;
    pausedCompletionRemaining = null;
  }

  void pauseTimer(DateTime now) {
    if (completionTimer != null && completionDeadline != null) {
      final remaining = completionDeadline!.difference(now);
      pausedCompletionRemaining = remaining.isNegative
          ? Duration.zero
          : remaining;
      completionTimer!.cancel();
      completionTimer = null;
      completionDeadline = null;
    }
  }
}

double _clampVolume(double volume) => volume.clamp(0.0, 1.0).toDouble();

Duration _nonNegativeMs(int milliseconds) =>
    Duration(milliseconds: milliseconds < 0 ? 0 : milliseconds);

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
