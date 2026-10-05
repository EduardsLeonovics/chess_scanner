import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../accounts/accounts.dart';

enum PuzzleKind {
  /// A forced mate in 3–5 that the user missed.
  mate('Mate'),

  /// A quiet move, the only one that kept a winning (+2) position, which
  /// the user missed and threw the advantage away.
  onlyMove('Only move'),

  /// A capture that won material, the best move, which the user missed and
  /// whose absence swung the eval against them.
  capture('Capture a piece'),

  /// A balanced position (within ±1) where the user's move lost on the spot
  /// (−5 or worse); the puzzle is to find a move that keeps the balance.
  blunder('Avoid the blunder');

  const PuzzleKind(this.label);

  final String label;
}

/// What the user filters by: the kinds, with mates split by length.
enum PuzzleCategory {
  mateIn1('Mate in 1'),
  mateIn2('Mate in 2'),
  mateIn3('Mate in 3'),
  mateIn4('Mate in 4'),
  mateIn5('Mate in 5'),
  onlyMove('Only move'),
  capture('Capture a piece'),
  blunder('Avoid the blunder');

  const PuzzleCategory(this.label);

  final String label;
}

/// The outcome of the latest attempt; [unsolved] if never attempted.
enum PuzzleResult { unsolved, solved, failed }

/// A position from one of the user's games where they missed something.
@immutable
class Puzzle {
  const Puzzle({
    required this.id,
    required this.kind,
    required this.fen,
    required this.solution,
    required this.userSide,
    required this.playedSan,
    required this.bestScore,
    required this.gameId,
    required this.site,
    required this.gameUrl,
    required this.opponent,
    required this.playedAt,
    required this.moveNumber,
    this.opponentRating,
    this.lastMove,
    this.mateIn,
    this.result = PuzzleResult.unsolved,
    this.attempts = 0,
    this.streak = 0,
    this.lastSeen,
    this.dueAt,
  });

  final String id;
  final PuzzleKind kind;

  /// Position before [lastMove], so the board can show the opponent's move
  /// that set up the puzzle. When [lastMove] is null the user is to move.
  final String fen;

  /// The opponent's move leading into the puzzle, in UCI.
  final String? lastMove;

  /// Moves in UCI, starting with the user's: user, reply, user, …
  final List<String> solution;

  final Side userSide;

  /// What the user actually played in the game.
  final String playedSan;

  /// Engine score of the best move in centipawns from the user's side
  /// (mates as ±100000-ish, see `scoreOf`). Used to accept equally good
  /// alternatives.
  final int bestScore;
  final int? mateIn;

  final String gameId;
  final ChessSite site;
  final String gameUrl;
  final String opponent;

  /// The opponent's rating at the time of the game, when the site gave it.
  final int? opponentRating;
  final DateTime playedAt;

  /// Full-move number of the user's move in the game.
  final int moveNumber;

  final PuzzleResult result;

  /// Spaced repetition (see `review.dart`): how often it was attempted,
  /// solved in a row, last shown, and when it's due again. [lastSeen] is
  /// null for a puzzle never shown.
  final int attempts;
  final int streak;
  final DateTime? lastSeen;
  final DateTime? dueAt;

  PuzzleCategory get category => switch (kind) {
        PuzzleKind.mate => switch (mateIn) {
            1 => PuzzleCategory.mateIn1,
            2 => PuzzleCategory.mateIn2,
            3 => PuzzleCategory.mateIn3,
            4 => PuzzleCategory.mateIn4,
            _ => PuzzleCategory.mateIn5,
          },
        PuzzleKind.onlyMove => PuzzleCategory.onlyMove,
        PuzzleKind.capture => PuzzleCategory.capture,
        PuzzleKind.blunder => PuzzleCategory.blunder,
      };

  Puzzle withReview({
    required PuzzleResult result,
    required int attempts,
    required int streak,
    required DateTime? lastSeen,
    required DateTime? dueAt,
  }) =>
      Puzzle(
        id: id,
        kind: kind,
        fen: fen,
        lastMove: lastMove,
        solution: solution,
        userSide: userSide,
        playedSan: playedSan,
        bestScore: bestScore,
        mateIn: mateIn,
        gameId: gameId,
        site: site,
        gameUrl: gameUrl,
        opponent: opponent,
        opponentRating: opponentRating,
        playedAt: playedAt,
        moveNumber: moveNumber,
        result: result,
        attempts: attempts,
        streak: streak,
        lastSeen: lastSeen,
        dueAt: dueAt,
      );

  /// Never attempted or shown, as when it was found.
  Puzzle withoutReview() => withReview(
        result: PuzzleResult.unsolved,
        attempts: 0,
        streak: 0,
        lastSeen: null,
        dueAt: null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'fen': fen,
        'lastMove': lastMove,
        'solution': solution,
        'userSide': userSide.name,
        'playedSan': playedSan,
        'bestScore': bestScore,
        'mateIn': mateIn,
        'gameId': gameId,
        'site': site.name,
        'gameUrl': gameUrl,
        'opponent': opponent,
        'opponentRating': opponentRating,
        'playedAt': playedAt.millisecondsSinceEpoch,
        'moveNumber': moveNumber,
        'result': result.name,
        'attempts': attempts,
        'streak': streak,
        'lastSeen': lastSeen?.millisecondsSinceEpoch,
        'dueAt': dueAt?.millisecondsSinceEpoch,
      };

  /// Puzzles saved before spaced repetition only have a [result]: a solved
  /// one comes back in a day, a failed one is due now.
  factory Puzzle.fromJson(Map<String, dynamic> json) {
    final result = PuzzleResult.values.byName(json['result'] as String);
    DateTime? time(String key) => switch (json[key]) {
          final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
          _ => null,
        };
    final legacy = !json.containsKey('attempts');
    final now = DateTime.now();
    return Puzzle(
      id: json['id'] as String,
      kind: PuzzleKind.values.byName(json['kind'] as String),
      fen: json['fen'] as String,
      lastMove: json['lastMove'] as String?,
      solution: (json['solution'] as List<dynamic>).cast<String>(),
      userSide: Side.values.byName(json['userSide'] as String),
      playedSan: json['playedSan'] as String,
      bestScore: json['bestScore'] as int,
      mateIn: json['mateIn'] as int?,
      gameId: json['gameId'] as String,
      site: ChessSite.values.byName(json['site'] as String),
      gameUrl: json['gameUrl'] as String,
      opponent: json['opponent'] as String,
      opponentRating: json['opponentRating'] as int?,
      playedAt: DateTime.fromMillisecondsSinceEpoch(json['playedAt'] as int),
      moveNumber: json['moveNumber'] as int,
      result: result,
      attempts: legacy ? (result == PuzzleResult.unsolved ? 0 : 1) : json['attempts'] as int,
      streak: legacy ? (result == PuzzleResult.solved ? 1 : 0) : json['streak'] as int,
      lastSeen: legacy ? (result == PuzzleResult.unsolved ? null : now) : time('lastSeen'),
      dueAt: legacy
          ? switch (result) {
              PuzzleResult.unsolved => null,
              PuzzleResult.solved => now.add(const Duration(days: 1)),
              PuzzleResult.failed => now,
            }
          : time('dueAt'),
    );
  }
}
