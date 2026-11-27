import 'package:auraboard/domain/clock.dart';

/// Deterministic in-memory [Clock] for unit and widget tests.
///
/// Steps through scheduled one-shot and periodic timers in strict
/// chronological order when [advance] is called, without real wall-clock
/// delays.
class FakeClock implements Clock {
  FakeClock([DateTime? initialTime])
    : _now = initialTime ?? DateTime.utc(2026, 1, 1);

  DateTime _now;
  int _nextId = 0;
  final List<_FakeClockTimer> _timers = <_FakeClockTimer>[];

  @override
  DateTime now() => _now;

  /// Number of currently active (scheduled and not yet cancelled/expired)
  /// timers.
  int get activeTimerCount => _timers.where((timer) => timer.isActive).length;

  @override
  ClockTimer createTimer(Duration duration, void Function() callback) {
    final effectiveDuration = duration.isNegative ? Duration.zero : duration;
    final timer = _FakeClockTimer(
      id: _nextId++,
      nextDue: _now.add(effectiveDuration),
      callback: callback,
    );
    _timers.add(timer);
    return timer;
  }

  @override
  ClockTimer createPeriodicTimer(Duration period, void Function() callback) {
    if (period <= Duration.zero) {
      throw ArgumentError.value(
        period,
        'period',
        'Periodic timer duration must be positive.',
      );
    }
    final timer = _FakeClockTimer(
      id: _nextId++,
      nextDue: _now.add(period),
      period: period,
      callback: callback,
    );
    _timers.add(timer);
    return timer;
  }

  /// Advances the fake clock by [delta], firing every due timer in strict
  /// chronological order (breaking exact timestamp ties by creation order).
  void advance(Duration delta) {
    if (delta.isNegative) {
      throw ArgumentError.value(
        delta,
        'delta',
        'Cannot advance FakeClock by a negative duration.',
      );
    }

    final targetTime = _now.add(delta);

    while (true) {
      _timers.removeWhere((timer) => !timer.isActive);

      _FakeClockTimer? nextTimer;
      for (final timer in _timers) {
        if (timer.nextDue.isAfter(targetTime)) {
          continue;
        }
        if (nextTimer == null ||
            timer.nextDue.isBefore(nextTimer.nextDue) ||
            (timer.nextDue.isAtSameMomentAs(nextTimer.nextDue) &&
                timer.id < nextTimer.id)) {
          nextTimer = timer;
        }
      }

      if (nextTimer == null) {
        break;
      }

      _now = nextTimer.nextDue;
      final period = nextTimer.period;
      if (period == null) {
        nextTimer._active = false;
      } else {
        nextTimer.nextDue = nextTimer.nextDue.add(period);
      }
      nextTimer.callback();
    }

    _now = targetTime;
    _timers.removeWhere((timer) => !timer.isActive);
  }
}

class _FakeClockTimer implements ClockTimer {
  _FakeClockTimer({
    required this.id,
    required this.nextDue,
    required this.callback,
    this.period,
  });

  final int id;
  DateTime nextDue;
  final Duration? period;
  final void Function() callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  void cancel() {
    _active = false;
  }
}
