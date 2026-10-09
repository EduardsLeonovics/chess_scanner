import 'dart:async';

import 'package:flutter/scheduler.dart';

/// Frame timings in the log, for measuring smoothness on a device:
/// `flutter build apk --profile --dart-define=FRAME_LOG=true`, then
/// `adb logcat -s flutter` shows a line every few seconds of activity.
/// Off in normal builds.
abstract final class FrameLog {
  static const enabled = bool.fromEnvironment('FRAME_LOG');

  static final _build = <double>[];
  static final _raster = <double>[];
  static Timer? _timer;

  static void install() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        _build.add(t.buildDuration.inMicroseconds / 1000);
        _raster.add(t.rasterDuration.inMicroseconds / 1000);
      }
      _timer ??= Timer(const Duration(seconds: 3), _report);
    });
  }

  static void _report() {
    _timer = null;
    if (_build.isEmpty) return;
    String stats(List<double> ms) {
      final sorted = [...ms]..sort();
      double at(double q) => sorted[((sorted.length - 1) * q).round()];
      final avg = sorted.reduce((a, b) => a + b) / sorted.length;
      return 'avg ${avg.toStringAsFixed(1)} p90 ${at(0.9).toStringAsFixed(1)} '
          'max ${sorted.last.toStringAsFixed(1)}';
    }

    const budget = 1000 / 60;
    var slow = 0;
    for (var i = 0; i < _build.length; i++) {
      if (_build[i] > budget || _raster[i] > budget) slow++;
    }
    // ignore: avoid_print
    print('FRAMES ${_build.length} frames, $slow over 16.7 ms | build ${stats(_build)} | '
        'raster ${stats(_raster)}');
    _build.clear();
    _raster.clear();
  }
}
