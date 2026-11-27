import 'dart:async';

import 'package:auraboard/audio/session_resilience.dart';

/// Recorded invocation of [BackgroundServiceGateway.updatePlayback].
class RecordedBackgroundPlaybackUpdate {
  const RecordedBackgroundPlaybackUpdate({
    required this.isPlaying,
    required this.summaryTitle,
    required this.activeCount,
  });

  final bool isPlaying;
  final String summaryTitle;
  final int activeCount;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RecordedBackgroundPlaybackUpdate &&
            other.isPlaying == isPlaying &&
            other.summaryTitle == summaryTitle &&
            other.activeCount == activeCount;
  }

  @override
  int get hashCode => Object.hash(isPlaying, summaryTitle, activeCount);

  @override
  String toString() =>
      'RecordedBackgroundPlaybackUpdate(isPlaying: $isPlaying, '
      'summaryTitle: $summaryTitle, activeCount: $activeCount)';
}

/// Deterministic in-memory [AudioFocusGateway] spy for unit and widget tests.
class FakeAudioFocusGateway implements AudioFocusGateway {
  FakeAudioFocusGateway({this.closeStreamOnDispose = false});

  final bool closeStreamOnDispose;
  final StreamController<SessionInterruptionEvent> _interruptionsController =
      StreamController<SessionInterruptionEvent>.broadcast();

  int configureCount = 0;
  final List<bool> activeHistory = <bool>[];
  bool isDisposed = false;
  bool setActiveResult = true;

  bool get hasInterruptionListener => _interruptionsController.hasListener;

  void emitInterruption(SessionInterruptionEvent event) {
    if (!_interruptionsController.isClosed) {
      _interruptionsController.add(event);
    }
  }

  Future<void> closeStream() async {
    if (!_interruptionsController.isClosed) {
      await _interruptionsController.close();
    }
  }

  @override
  Future<void> configureForMediaPlayback() async {
    configureCount += 1;
  }

  @override
  Future<bool> setActive(bool active) async {
    activeHistory.add(active);
    return setActiveResult;
  }

  @override
  Stream<SessionInterruptionEvent> get interruptions =>
      _interruptionsController.stream;

  @override
  Future<void> dispose() async {
    isDisposed = true;
    if (closeStreamOnDispose && !_interruptionsController.isClosed) {
      await _interruptionsController.close();
    }
  }
}

/// Deterministic in-memory [BackgroundServiceGateway] spy for tests.
class FakeBackgroundServiceGateway implements BackgroundServiceGateway {
  final List<RecordedBackgroundPlaybackUpdate> updates =
      <RecordedBackgroundPlaybackUpdate>[];
  bool isDisposed = false;

  @override
  Future<void> updatePlayback({
    required bool isPlaying,
    required String summaryTitle,
    required int activeCount,
  }) async {
    updates.add(
      RecordedBackgroundPlaybackUpdate(
        isPlaying: isPlaying,
        summaryTitle: summaryTitle,
        activeCount: activeCount,
      ),
    );
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }
}

/// Deterministic in-memory [WakelockGateway] spy for tests.
class FakeWakelockGateway implements WakelockGateway {
  final List<bool> recordedStates = <bool>[];

  bool? get lastEnabled => recordedStates.isEmpty ? null : recordedStates.last;

  @override
  Future<void> setEnabled(bool enabled) async {
    recordedStates.add(enabled);
  }
}
