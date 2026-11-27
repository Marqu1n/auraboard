import 'dart:async';

/// Handle to a scheduled one-shot or periodic timer returned by [Clock].
abstract interface class ClockTimer {
  bool get isActive;
  void cancel();
}

/// Abstraction over wall-clock time and timers for deterministic scheduling.
abstract interface class Clock {
  DateTime now();
  ClockTimer createTimer(Duration duration, void Function() callback);
  ClockTimer createPeriodicTimer(Duration period, void Function() callback);
}

/// Production [Clock] backed by [DateTime.now] and [Timer].
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();

  @override
  ClockTimer createTimer(Duration duration, void Function() callback) {
    final effectiveDuration = duration.isNegative ? Duration.zero : duration;
    return _SystemClockTimer(Timer(effectiveDuration, callback));
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
    return _SystemClockTimer(Timer.periodic(period, (_) => callback()));
  }
}

class _SystemClockTimer implements ClockTimer {
  _SystemClockTimer(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
