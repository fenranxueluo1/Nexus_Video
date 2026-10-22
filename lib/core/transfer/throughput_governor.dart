import 'dart:async';

import '../util/task_token.dart';

class ThroughputGovernor {
  ThroughputGovernor(this.bytesPerSecond);

  int bytesPerSecond;
  double _available = 0;
  DateTime _lastRefill = DateTime.now();
  Future<void> _tail = Future.value();

  bool get enabled => bytesPerSecond > 0;

  Future<void> acquire(int bytes, TaskToken token) {
    if (bytes <= 0) {
      return Future.value();
    }
    final completer = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await _consume(bytes, token);
        if (!completer.isCompleted) {
          completer.complete();
        }
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  Future<void> _consume(int bytes, TaskToken token) async {
    if (!enabled) {
      return;
    }
    var remaining = bytes.toDouble();
    while (remaining > 0) {
      token.throwIfCancelled();
      if (!enabled) {
        return;
      }
      final now = DateTime.now();
      final elapsed = now.difference(_lastRefill).inMicroseconds / 1000000.0;
      _lastRefill = now;
      final capacity = bytesPerSecond.toDouble();
      _available = (_available + elapsed * capacity).clamp(0, capacity);
      final take = _available < remaining ? _available : remaining;
      _available -= take;
      remaining -= take;
      if (remaining <= 0) {
        return;
      }
      final waitSeconds = (remaining / capacity).clamp(0.01, 0.1);
      await Future<void>.delayed(
        Duration(microseconds: (waitSeconds * 1000000).round()),
      );
    }
  }

  void setLimit(int value) {
    bytesPerSecond = value < 0 ? 0 : value;
    _available = 0;
    _lastRefill = DateTime.now();
  }
}
