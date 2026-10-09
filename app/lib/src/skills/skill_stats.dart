import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../accounts/game_sources.dart' show GameSpeed;
import '../engine/uci.dart';
import '../sound/move_sounds.dart' show isCapture;
import 'opening_book.dart';

enum Skill {
  tactics('Tactics', 'Spotting combinations that win material or mate 2–3 moves later.'),
  openings('Openings', 'How well you play the opening: theory moves count as perfect, the rest as Stockfish rates them.'),
  middlegame('Middlegame', 'Accuracy in quiet middlegame positions: improving pieces, keeping the initiative, not blundering.'),
  endgame('Endgame', 'Finding the win in endgames that are winning even though material is level.'),
  positional('Positional play', 'Keeping your pieces protected and coordinated, and accuracy in balanced positions.');

  const Skill(this.label, this.description);

  final String label;
  final String description;
}

/// Thresholds for the skill measurements, in centipawns from the user's side.
abstract final class SkillRules {
  /// Material (pawns = 1) a tactic must win, and the score it must leave.
  static const tacticMaterial = 2;
  static const tacticMinScore = 150;
  static const tacticMaxMate = 5;

  /// Plies into the engine's line at which the material gain is measured:
  /// the user's third move, and the reply to it (so recaptures count).
  static const tacticPlies = 5;

  /// A move "finds" an opportunity if it gives up no more than this.
  static const findTolerance = 60;

  /// Quiet middlegame positions: the game isn't decided yet.
  static const quietMaxScore = 300;

  /// Balanced positions for positional play.
  static const balancedMaxScore = 150;

  /// Endgame chances: winning by this much with material within a pawn.
  static const endgameWinning = 200;
  static const endgameStillWinning = 150;

  /// Theory moves that count as a perfect opening score.
  static const fullTheoryMoves = 12;

  /// Following a book line to its very end counts as a perfect opening once
  /// it lasted this many of the user's moves (shorter lines say too little).
  static const exhaustedTheoryMoves = 5;

  /// A middlegame blunder drops the win chance by this many percentage
  /// points: Lichess's blunder line (0.3 on its -1..1 scale).
  static const blunderWinDrop = 15;

  /// Endgame once at most this many knights, bishops, rooks and queens remain.
  static const endgameMaxPieces = 6;

  /// Plies of the opening phase (when not in theory).
  static const openingPlies = 20;
}

/// Lichess's win-chance curve: centipawns to a 0..100 percentage.
double winPercent(int cp) {
  final c = cp.clamp(-1500, 1500);
  return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * c)) - 1);
}

/// Lichess's move accuracy (0..100) from the win chance before and after.
double moveAccuracy(int before, int after) {
  final drop = winPercent(before) - winPercent(after);
  if (drop <= 0) return 100;
  return (103.1668 * math.exp(-0.04354 * drop) - 3.1669).clamp(0, 100).toDouble();
}

const _values = {Role.pawn: 1, Role.knight: 3, Role.bishop: 3, Role.rook: 5, Role.queen: 9};

/// Material balance from [side]'s point of view.
int materialBalance(Position pos, Side side) {
  var total = 0;
  for (final (_, piece) in pos.board.pieces) {
    final value = _values[piece.role] ?? 0;
    total += piece.color == side ? value : -value;
  }
  return total;
}

int _minorsAndMajors(Position pos) =>
    pos.board.pieces.where((e) => e.$2.role != Role.pawn && e.$2.role != Role.king).length;

/// Share of [side]'s knights, bishops, rooks and queens defended by its own pieces.
(int defended, int total) coordination(Position pos, Side side) {
  var defended = 0;
  var total = 0;
  for (final (square, piece) in pos.board.pieces) {
    if (piece.color != side || piece.role == Role.pawn || piece.role == Role.king) continue;
    total++;
    if (pos.board.attacksTo(square, side).isNotEmpty) defended++;
  }
  return (defended, total);
}

/// One analyzed game's raw skill counts. Scores come from summing these
/// over many games (see [SkillProfile]).
@immutable
class GameSkillStats {
  const GameSkillStats({
    required this.playedAt,
    this.speed,
    this.tacticChances = 0,
    this.tacticsFound = 0,
    this.theoryMoves = 0,
    this.leftTheory = false,
    this.theoryExhausted = false,
    this.openingMoves = 0,
    this.openingAccuracy = 0,
    this.middleMoves = 0,
    this.middleAccuracy = 0,
    this.middleBlunders = 0,
    this.endChances = 0,
    this.endConverted = 0,
    this.endMoves = 0,
    this.endAccuracy = 0,
    this.balancedMoves = 0,
    this.balancedAccuracy = 0,
    this.piecesDefended = 0,
    this.piecesCounted = 0,
    this.timedMoves = const [0, 0, 0],
    this.thinkingTime = const [0, 0, 0],
  });

  final DateTime playedAt;
  final GameSpeed? speed;

  /// Each combination counts once, however many moves it takes; it counts
  /// as found only if the user saw it through.
  final int tacticChances;
  final int tacticsFound;

  /// Moves the user played inside opening theory.
  final int theoryMoves;

  /// The user (not the opponent) made the first move out of theory.
  final bool leftTheory;

  /// The game followed a book line until the book had no further move.
  final bool theoryExhausted;

  /// The user's moves in the opening phase, and the sum of their
  /// accuracies (0..100): theory moves are perfect, the rest are rated by
  /// the engine.
  final int openingMoves;
  final double openingAccuracy;

  final int middleMoves;

  /// Sum of per-move accuracies (0..100) over [middleMoves].
  final double middleAccuracy;
  final int middleBlunders;
  final int endChances;
  final int endConverted;
  final int endMoves;
  final double endAccuracy;
  final int balancedMoves;
  final double balancedAccuracy;
  final int piecesDefended;
  final int piecesCounted;

  /// Per [GamePhase] (by index): the user's moves with a known thinking
  /// time, and the seconds spent on them. Zero when the game had no clock.
  final List<int> timedMoves;
  final List<double> thinkingTime;

  Map<String, dynamic> toJson() => {
        'playedAt': playedAt.millisecondsSinceEpoch,
        if (speed != null) 'sp': speed!.name,
        'tc': tacticChances,
        'tf': tacticsFound,
        'th': theoryMoves,
        'lt': leftTheory,
        'tx': theoryExhausted,
        'om': openingMoves,
        'oa': openingAccuracy,
        'mm': middleMoves,
        'ma': middleAccuracy,
        'mb': middleBlunders,
        'ec': endChances,
        'ev': endConverted,
        'em': endMoves,
        'ea': endAccuracy,
        'bm': balancedMoves,
        'ba': balancedAccuracy,
        'pd': piecesDefended,
        'pc': piecesCounted,
        if (timedMoves.any((n) => n > 0)) ...{
          'tn': timedMoves,
          'tt': [for (final t in thinkingTime) double.parse(t.toStringAsFixed(1))],
        },
      };

  factory GameSkillStats.fromJson(Map<String, dynamic> json) => GameSkillStats(
        playedAt: DateTime.fromMillisecondsSinceEpoch(json['playedAt'] as int),
        speed: GameSpeed.values.asNameMap()[json['sp']],
        tacticChances: json['tc'] as int,
        tacticsFound: json['tf'] as int,
        theoryMoves: json['th'] as int,
        leftTheory: json['lt'] as bool,
        theoryExhausted: json['tx'] as bool? ?? false,
        openingMoves: json['om'] as int? ?? 0,
        openingAccuracy: (json['oa'] as num? ?? 0).toDouble(),
        middleMoves: json['mm'] as int,
        middleAccuracy: (json['ma'] as num).toDouble(),
        middleBlunders: json['mb'] as int,
        endChances: json['ec'] as int,
        endConverted: json['ev'] as int,
        endMoves: json['em'] as int,
        endAccuracy: (json['ea'] as num).toDouble(),
        balancedMoves: json['bm'] as int,
        balancedAccuracy: (json['ba'] as num).toDouble(),
        piecesDefended: json['pd'] as int,
        piecesCounted: json['pc'] as int,
        timedMoves: (json['tn'] as List<dynamic>?)?.cast<int>() ?? const [0, 0, 0],
        thinkingTime: [
          for (final t in (json['tt'] as List<dynamic>?) ?? const [0, 0, 0]) (t as num).toDouble(),
        ],
      );
}

/// The stage of the game a move was played in, as the skills measure it:
/// the endgame once few pieces are left, the opening for the first
/// [SkillRules.openingPlies] plies, the middlegame in between.
enum GamePhase {
  opening('Opening'),
  middlegame('Middlegame'),
  endgame('Endgame');

  const GamePhase(this.label);

  final String label;

  static GamePhase of(Position before, int ply) {
    if (_minorsAndMajors(before) <= SkillRules.endgameMaxPieces) return endgame;
    return ply < SkillRules.openingPlies ? opening : middlegame;
  }
}

/// Seconds the user thought about each of their moves, by [GamePhase]:
/// (moves, seconds) per phase. [clocks] are the remaining times after each
/// ply in centiseconds; each player's first move is skipped (the clock
/// doesn't run yet on Lichess, and there's no earlier reading to compare).
(List<int>, List<double>) thinkingTimes({
  required Side side,
  required List<Position> positions,
  required List<int>? clocks,
  required int increment,
}) {
  final moves = [0, 0, 0];
  final seconds = [0.0, 0.0, 0.0];
  if (clocks == null) return (moves, seconds);
  final plies = math.min(clocks.length, positions.length - 1);
  for (var i = 2; i < plies; i++) {
    if (positions[i].turn != side) continue;
    final spent = (clocks[i - 2] - clocks[i]) / 100 + increment;
    // A bad reading (clock added by the opponent, a site glitch): skip it.
    if (spent < 0 || spent > 3600) continue;
    final phase = GamePhase.of(positions[i], i).index;
    moves[phase]++;
    seconds[phase] += spent;
  }
  return (moves, seconds);
}

/// Engine verdict for one position: the best line, or null when there was
/// none (game over, or the engine wasn't asked).
typedef ScanLine = PvLine?;

/// Measures the user's skills in one game.
///
/// [positions] has one more entry than [moves]; [scan] holds the engine's
/// best line for each position (null where it wasn't evaluated). [scoreOf]
/// turns a line into centipawns for a side, and [afterScore] gives the
/// user's score after their move at ply i.
GameSkillStats measureGame({
  required DateTime playedAt,
  GameSpeed? speed,
  required Side side,
  required List<Position> positions,
  required List<Move> moves,
  required List<ScanLine> scan,
  required int Function(PvLine line, Side side) scoreOf,
  required int? Function(int ply) afterScore,
  required int? Function(PvLine line, Side side) mateFor,
  OpeningBook? book,
  List<int>? clocks,
  int increment = 0,
}) {
  var tacticChances = 0, tacticsFound = 0;
  var openingMoves = 0;
  var openingAccuracy = 0.0;
  var middleMoves = 0, middleBlunders = 0;
  var middleAccuracy = 0.0;
  var endChances = 0, endConverted = 0, endMoves = 0;
  var endAccuracy = 0.0;
  var balancedMoves = 0;
  var balancedAccuracy = 0.0;
  var piecesDefended = 0, piecesCounted = 0;

  // Openings: theory lasts until the last book position the game reaches
  // (a move order that briefly leaves the book and transposes back in still
  // counts). Whoever moved out of that position left theory, unless the
  // book has no move from it: then the theory ran out and nobody left it.
  var theoryMoves = 0;
  var leftTheory = false;
  var theoryExhausted = false;
  if (book != null) {
    var last = 0;
    for (var i = 1; i < positions.length && i <= 40; i++) {
      if (book.contains(positions[i])) last = i;
    }
    for (var i = 0; i < last; i++) {
      if (positions[i].turn == side) theoryMoves++;
    }
    final movedOn = last < moves.length;
    theoryExhausted = movedOn && last > 0 && !book.continues(positions[last]);
    leftTheory = movedOn && !theoryExhausted && positions[last].turn == side;
  }

  // The user's previous move found a tactic, so a tactic now is most likely
  // the same combination continuing.
  var inCombination = false;

  for (var i = 0; i < moves.length; i++) {
    final before = positions[i];
    if (before.turn != side) continue;
    final continuing = inCombination;
    inCombination = false;
    // A move into a named opening line is theory: perfect, whatever the
    // engine would have preferred (2.Nc3 is the Jobava, not a worse 2.c4).
    final theory = book != null && i < SkillRules.openingPlies && book.contains(positions[i + 1]);
    if (theory) {
      openingMoves++;
      openingAccuracy += 100;
    }
    final best = scan[i];
    final after = afterScore(i);
    if (best == null || after == null || best.pv.isEmpty) continue;
    final bestMove = legalUciMove(before, best.pv.first);
    if (bestMove == null) continue;
    final b = scoreOf(best, side);
    final played = moves[i];
    final found = played == bestMove || after >= b - SkillRules.findTolerance;
    final quiet = !before.isCheck && !isCapture(before, bestMove);
    final pieces = _minorsAndMajors(before);
    final endgame = pieces <= SkillRules.endgameMaxPieces;
    final opening = !endgame && i < SkillRules.openingPlies;
    final accuracy = moveAccuracy(b, after);
    if (opening && !theory) {
      openingMoves++;
      openingAccuracy += accuracy;
    }

    // Tactics: a forced mate, or a line whose material gain only shows up
    // a few moves in (not simply taking a loose piece).
    final mate = mateFor(best, side);
    final isTactic = (mate != null && mate >= 2 && mate <= SkillRules.tacticMaxMate) ||
        (b >= SkillRules.tacticMinScore && _deferredGain(before, best.pv, side));
    if (isTactic) {
      final hit = found && (mate == null || after >= 90000);
      if (!continuing) {
        tacticChances++;
        if (hit) tacticsFound++;
      } else if (!hit) {
        // Started the combination but didn't finish it.
        tacticsFound--;
      }
      inCombination = hit;
    }

    if (endgame) {
      endMoves++;
      endAccuracy += accuracy;
      final level = materialBalance(before, side).abs() <= 1;
      if (b >= SkillRules.endgameWinning && level && mate == null) {
        endChances++;
        if (after >= SkillRules.endgameStillWinning) endConverted++;
      }
    } else if (!opening && quiet && b.abs() <= SkillRules.quietMaxScore) {
      middleMoves++;
      middleAccuracy += accuracy;
      if (winPercent(b) - winPercent(after) >= SkillRules.blunderWinDrop) middleBlunders++;
    }

    if (!opening && quiet && b.abs() <= SkillRules.balancedMaxScore) {
      balancedMoves++;
      balancedAccuracy += accuracy;
      final (defended, total) = coordination(before.play(played), side);
      piecesDefended += defended;
      piecesCounted += total;
    }
  }

  final (timedMoves, thinkingTime) = thinkingTimes(
    side: side,
    positions: positions,
    clocks: clocks,
    increment: increment,
  );

  return GameSkillStats(
    playedAt: playedAt,
    speed: speed,
    timedMoves: timedMoves,
    thinkingTime: thinkingTime,
    tacticChances: tacticChances,
    tacticsFound: tacticsFound,
    theoryMoves: theoryMoves,
    leftTheory: leftTheory,
    theoryExhausted: theoryExhausted,
    openingMoves: openingMoves,
    openingAccuracy: openingAccuracy,
    middleMoves: middleMoves,
    middleAccuracy: middleAccuracy,
    middleBlunders: middleBlunders,
    endChances: endChances,
    endConverted: endConverted,
    endMoves: endMoves,
    endAccuracy: endAccuracy,
    balancedMoves: balancedMoves,
    balancedAccuracy: balancedAccuracy,
    piecesDefended: piecesDefended,
    piecesCounted: piecesCounted,
  );
}

/// Whether [pv] wins material only after the first move: nothing much is
/// gained immediately, but by the user's third move (and the reply) at
/// least [SkillRules.tacticMaterial] is.
bool _deferredGain(Position start, List<String> pv, Side side) {
  if (pv.length < 3) return false;
  final base = materialBalance(start, side);
  var pos = start;
  final balances = <int>[];
  for (final uci in pv.take(SkillRules.tacticPlies + 1)) {
    final move = legalUciMove(pos, uci);
    if (move == null) break;
    pos = pos.play(move);
    balances.add(materialBalance(pos, side) - base);
  }
  if (balances.length < 3) return false;
  final immediate = balances[0];
  // The gain after the user's last move counted, after the reply if there is one.
  final settled = balances.length > SkillRules.tacticPlies
      ? math.min(balances[SkillRules.tacticPlies - 1], balances[SkillRules.tacticPlies])
      : balances.last;
  return immediate < SkillRules.tacticMaterial && settled >= SkillRules.tacticMaterial;
}

/// One skill's score with what it's based on.
@immutable
class SkillScore {
  const SkillScore(this.skill, this.value, this.basis);

  final Skill skill;

  /// 0..100, or null when there isn't enough data yet.
  final double? value;

  /// Plain-language description of the evidence, e.g. "found 7 of 12".
  final String basis;
}

/// How long the user thinks per move, over the analyzed games that had a
/// clock.
@immutable
class TimeProfile {
  const TimeProfile({required this.games, required this.moves, required this.seconds});

  /// Games with clock data.
  final int games;

  /// Per [GamePhase] (by index).
  final List<int> moves;
  final List<double> seconds;

  int get totalMoves => moves.fold(0, (a, b) => a + b);

  /// Average seconds per move overall, or null without data.
  double? get average {
    final n = totalMoves;
    return n == 0 ? null : seconds.fold(0.0, (a, b) => a + b) / n;
  }

  /// Average seconds per move in [phase], or null without data.
  double? averageIn(GamePhase phase) =>
      moves[phase.index] == 0 ? null : seconds[phase.index] / moves[phase.index];

  factory TimeProfile.from(Iterable<GameSkillStats> stats) {
    final moves = [0, 0, 0];
    final seconds = [0.0, 0.0, 0.0];
    var games = 0;
    for (final g in stats) {
      if (!g.timedMoves.any((n) => n > 0)) continue;
      games++;
      for (var p = 0; p < 3; p++) {
        moves[p] += g.timedMoves[p];
        seconds[p] += g.thinkingTime[p];
      }
    }
    return TimeProfile(games: games, moves: moves, seconds: seconds);
  }
}

/// The user's five skill scores over their analyzed games.
@immutable
class SkillProfile {
  const SkillProfile({required this.scores, required this.games, this.from, this.to});

  final Map<Skill, SkillScore> scores;
  final int games;
  final DateTime? from;
  final DateTime? to;

  /// Minimum evidence before a score is shown.
  static const minTacticChances = 3;
  static const minTheoryGames = 3;
  static const minMoves = 20;
  static const minEndChances = 3;

  factory SkillProfile.from(Iterable<GameSkillStats> stats) {
    final games = stats.toList()..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    int sumInt(int Function(GameSkillStats) f) => games.fold(0, (s, g) => s + f(g));
    double sum(double Function(GameSkillStats) f) => games.fold(0.0, (s, g) => s + f(g));

    final tc = sumInt((g) => g.tacticChances), tf = sumInt((g) => g.tacticsFound);
    final tactics = SkillScore(
      Skill.tactics,
      tc >= minTacticChances ? 100 * tf / tc : null,
      tc == 0 ? 'No tactical chances found yet' : 'Found $tf of $tc tactical chances',
    );

    // Openings: how accurately the opening phase is played. Theory moves
    // count as perfect; how long the theory lasted is only shown (named
    // lines are often short, so leaving them early isn't a mistake).
    final om = sumInt((g) => g.openingMoves);
    final left = games.where((g) => g.leftTheory).toList();
    final avgTheory = left.isEmpty ? 0.0 : left.fold(0, (s, g) => s + g.theoryMoves) / left.length;
    final openingValue = om >= minMoves ? sum((g) => g.openingAccuracy) / om : null;
    final openings = SkillScore(
      Skill.openings,
      openingValue,
      om == 0
          ? 'No opening moves analyzed yet'
          : [
              '$om opening moves${openingValue == null ? '' : ', ${openingValue.round()}% accurate'}',
              if (left.isNotEmpty) 'you leave theory after ${avgTheory.toStringAsFixed(1)} moves on average',
            ].join(' · '),
    );

    final mm = sumInt((g) => g.middleMoves), mb = sumInt((g) => g.middleBlunders);
    final middlegame = SkillScore(
      Skill.middlegame,
      mm >= minMoves ? sum((g) => g.middleAccuracy) / mm : null,
      mm == 0 ? 'No quiet middlegame moves yet' : '$mm quiet moves, $mb blunder${mb == 1 ? '' : 's'}',
    );

    final ec = sumInt((g) => g.endChances), ev = sumInt((g) => g.endConverted);
    final em = sumInt((g) => g.endMoves);
    final endAcc = em == 0 ? null : sum((g) => g.endAccuracy) / em;
    double? endValue;
    if (ec >= minEndChances) {
      final conversion = 100 * ev / ec;
      endValue = endAcc != null && em >= minMoves ? 0.6 * conversion + 0.4 * endAcc : conversion;
    } else if (endAcc != null && em >= minMoves) {
      endValue = endAcc;
    }
    final endgame = SkillScore(
      Skill.endgame,
      endValue,
      ec > 0
          ? 'Kept the win in $ev of $ec hidden winning endgames'
          : (em == 0 ? 'No endgame moves yet' : '$em endgame moves, no hidden wins yet'),
    );

    final bm = sumInt((g) => g.balancedMoves);
    final pc = sumInt((g) => g.piecesCounted), pd = sumInt((g) => g.piecesDefended);
    final positional = SkillScore(
      Skill.positional,
      bm >= minMoves && pc > 0 ? 0.5 * (sum((g) => g.balancedAccuracy) / bm) + 0.5 * (100 * pd / pc) : null,
      pc == 0 ? 'No balanced positions yet' : '${(100 * pd / pc).round()}% of your pieces protected',
    );

    return SkillProfile(
      scores: {for (final s in [tactics, openings, middlegame, endgame, positional]) s.skill: s},
      games: games.length,
      from: games.isEmpty ? null : games.first.playedAt,
      to: games.isEmpty ? null : games.last.playedAt,
    );
  }
}
