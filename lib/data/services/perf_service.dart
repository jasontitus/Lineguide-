import 'package:firebase_performance/firebase_performance.dart';

import '../../main.dart';

/// Lightweight wrapper for Firebase Performance custom traces.
class PerfService {
  PerfService._();
  static final instance = PerfService._();

  FirebasePerformance? get _perf =>
      firebaseAvailable ? FirebasePerformance.instance : null;

  /// Start a named trace. Call [Trace.stop] when the operation completes.
  Trace? startTrace(String name) {
    try {
      final trace = _perf?.newTrace(name);
      trace?.start();
      return trace;
    } catch (_) {
      return null;
    }
  }

  /// Measure an async operation end-to-end.
  Future<T> measure<T>(String name, Future<T> Function() operation) async {
    final trace = startTrace(name);
    try {
      final result = await operation();
      return result;
    } finally {
      trace?.stop();
    }
  }
}
