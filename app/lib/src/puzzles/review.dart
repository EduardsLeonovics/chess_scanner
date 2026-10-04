import 'puzzle.dart';

/// Spaced repetition for puzzles: a failed puzzle comes back soon, each
/// solve in a row pushes it further out.
abstract final class ReviewRules {
  /// After a failed attempt (or a revealed solution).
  static const retryAfter = Duration(minutes: 5);

  /// After a skip: out of the way for a while, but not for long.
  static const skipFor = Duration(minutes: 30);

  /// After the 1st, 2nd, … solve in a row. Beyond the last, the last.
  static const intervals = [
    Duration(days: 1),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 21),
    Duration(days: 60),
  ];
}

/// [puzzle] after an attempt that ended in [outcome] (solved or failed).
Puzzle reviewed(Puzzle puzzle, PuzzleResult outcome, DateTime now) {
  final solved = outcome == PuzzleResult.solved;
  final streak = solved ? puzzle.streak + 1 : 0;
  final interval = solved
      ? ReviewRules.intervals[(streak - 1).clamp(0, ReviewRules.intervals.length - 1)]
      : ReviewRules.retryAfter;
  return puzzle.withReview(
    result: outcome,
    attempts: puzzle.attempts + 1,
    streak: streak,
    lastSeen: now,
    dueAt: now.add(interval),
  );
}

/// [puzzle] after the user moved on without trying it.
Puzzle skipped(Puzzle puzzle, DateTime now) {
  final pushed = now.add(ReviewRules.skipFor);
  final due = puzzle.dueAt;
  return puzzle.withReview(
    result: puzzle.result,
    attempts: puzzle.attempts,
    streak: puzzle.streak,
    lastSeen: now,
    dueAt: due != null && due.isAfter(pushed) ? due : pushed,
  );
}

/// The puzzle to show next: the most overdue one, else one never shown
/// (in [puzzles] order), else whichever is due soonest. [previous] is only
/// picked when it's the only puzzle.
Puzzle? pickNext(List<Puzzle> puzzles, DateTime now, {String? previous}) {
  final candidates = [for (final p in puzzles) if (p.id != previous) p];
  if (candidates.isEmpty) return puzzles.isEmpty ? null : puzzles.first;

  Puzzle? overdue;
  Puzzle? fresh;
  Puzzle? soonest;
  for (final p in candidates) {
    final due = p.dueAt;
    if (p.lastSeen == null || due == null) {
      fresh ??= p;
      continue;
    }
    if (!due.isAfter(now) && (overdue == null || due.isBefore(overdue.dueAt!))) overdue = p;
    if (soonest == null || due.isBefore(soonest.dueAt!)) soonest = p;
  }
  return overdue ?? fresh ?? soonest;
}
