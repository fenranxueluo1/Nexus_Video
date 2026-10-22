import 'dart:async';

class TaskToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
    _listeners.clear();
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeOnCancel(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const TaskAborted();
    }
  }
}

class TaskAborted implements Exception {
  const TaskAborted();

  @override
  String toString() => '操作已取消';
}

class RateGate {
  RateGate(this.interval);
  final Duration interval;
  DateTime? _last;

  bool get ready {
    final now = DateTime.now();
    if (_last == null || now.difference(_last!) >= interval) {
      _last = now;
      return true;
    }
    return false;
  }

  void reset() => _last = null;
}
