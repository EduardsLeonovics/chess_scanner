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
  capture('Capture a piece');

  const PuzzleKind(this.label);

  final String label;
}

/// What the user filters by: the kinds, with mates split by length.
enum PuzzleCategory {
  mateIn3('Mate in 3'),
  mateIn4('Mate in 4'),
  mateIn5('Mate in 5'),
  onlyMove('Only move'),
  capture('Capture a piece');

  const PuzzleCategory(this.label);

  final String label;
}

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

  PuzzleCategory get category => switch (kind) {
        PuzzleKind.mate => switch (mateIn) {
            3 => PuzzleCategory.mateIn3,
            4 => PuzzleCategory.mateIn4,
            _ => PuzzleCategory.mateIn5,
          },
        PuzzleKind.onlyMove => PuzzleCategory.onlyMove,
        PuzzleKind.capture => PuzzleCategory.capture,
      };

  Puzzle withResult(PuzzleResult result) => Puzzle(
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
      };

  factory Puzzle.fromJson(Map<String, dynamic> json) => Puzzle(
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
        result: PuzzleResult.values.byName(json['result'] as String),
      );
}
