import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance.dart' show sharedPreferencesProvider;

/// When live analysis stops on its own.
enum SearchLimit {
  depth('Depth'),
  time('Time'),

  /// Until the position changes. Game analysis waits while this runs.
  unlimited('Unlimited');

  const SearchLimit(this.label);

  final String label;
}

/// How Stockfish analyzes the board on the analysis page. Persisted.
/// Puzzle generation uses its own fixed searches.
@immutable
class EngineSettings {
  const EngineSettings({
    this.lines = 3,
    this.limit = SearchLimit.depth,
    this.depth = 24,
    this.seconds = 10,
    this._threads,
    this.hashMb = 64,
    this.showLines = true,
  });

  static const maxLines = 5;
  static const minDepth = 10;
  static const maxDepth = 40;
  static const minSeconds = 1;
  static const maxSeconds = 30;
  static const hashSizes = [16, 32, 64, 128, 256];

  /// Cores the engine may use. By default all but one (at most 4), so the
  /// UI stays smooth.
  static int get maxThreads => kIsWeb ? 1 : math.max(1, Platform.numberOfProcessors);
  static int get defaultThreads => math.max(1, math.min(4, maxThreads - 1));

  /// MultiPV: how many best moves are shown.
  final int lines;
  final SearchLimit limit;
  final int depth;
  final int seconds;
  final int? _threads;
  int get threads => (_threads ?? defaultThreads).clamp(1, maxThreads);
  final int hashMb;

  /// The lines under the board are expanded.
  final bool showLines;

  EngineSettings copyWith({
    int? lines,
    SearchLimit? limit,
    int? depth,
    int? seconds,
    int? threads,
    int? hashMb,
    bool? showLines,
  }) =>
      EngineSettings(
        lines: lines ?? this.lines,
        limit: limit ?? this.limit,
        depth: depth ?? this.depth,
        seconds: seconds ?? this.seconds,
        threads: threads ?? _threads,
        hashMb: hashMb ?? this.hashMb,
        showLines: showLines ?? this.showLines,
      );

  @override
  bool operator ==(Object other) =>
      other is EngineSettings &&
      other.lines == lines &&
      other.limit == limit &&
      other.depth == depth &&
      other.seconds == seconds &&
      other.threads == threads &&
      other.hashMb == hashMb &&
      other.showLines == showLines;

  @override
  int get hashCode => Object.hash(lines, limit, depth, seconds, threads, hashMb, showLines);
}

final engineSettingsProvider =
    NotifierProvider<EngineSettingsNotifier, EngineSettings>(EngineSettingsNotifier.new);

class EngineSettingsNotifier extends Notifier<EngineSettings> {
  static const _lines = 'engine.lines';
  static const _limit = 'engine.limit';
  static const _depth = 'engine.depth';
  static const _seconds = 'engine.seconds';
  static const _threads = 'engine.threads';
  static const _hash = 'engine.hashMb';
  static const _showLines = 'engine.showLines';

  @override
  EngineSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    const d = EngineSettings();
    return EngineSettings(
      lines: (prefs.getInt(_lines) ?? d.lines).clamp(1, EngineSettings.maxLines),
      limit: SearchLimit.values.asNameMap()[prefs.getString(_limit)] ?? d.limit,
      depth: (prefs.getInt(_depth) ?? d.depth).clamp(EngineSettings.minDepth, EngineSettings.maxDepth),
      seconds: (prefs.getInt(_seconds) ?? d.seconds).clamp(EngineSettings.minSeconds, EngineSettings.maxSeconds),
      threads: prefs.getInt(_threads),
      hashMb: EngineSettings.hashSizes.contains(prefs.getInt(_hash)) ? prefs.getInt(_hash)! : d.hashMb,
      showLines: prefs.getBool(_showLines) ?? d.showLines,
    );
  }

  void set(EngineSettings settings) {
    state = settings;
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setInt(_lines, settings.lines);
    prefs.setString(_limit, settings.limit.name);
    prefs.setInt(_depth, settings.depth);
    prefs.setInt(_seconds, settings.seconds);
    prefs.setInt(_threads, settings.threads);
    prefs.setInt(_hash, settings.hashMb);
    prefs.setBool(_showLines, settings.showLines);
  }

  void reset() => set(EngineSettings(showLines: state.showLines));
}
