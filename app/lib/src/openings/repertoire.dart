import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../accounts/game_sources.dart' show GameSpeed;
import '../skills/opening_book.dart';

/// How many plies of each game are kept for the opening study.
const repertoirePlies = 24;

/// The start of one of the user's games, kept for the opening study.
@immutable
class RepertoireGame {
  const RepertoireGame({
    required this.id,
    required this.side,
    required this.sanMoves,
    required this.playedAt,
    this.speed,
  });

  final String id;
  final Side side;

  /// The first [repertoirePlies] moves, in SAN from the standard start.
  final List<String> sanMoves;
  final DateTime playedAt;
  final GameSpeed? speed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'side': side.name,
        'moves': sanMoves.join(' '),
        'playedAt': playedAt.millisecondsSinceEpoch,
        if (speed != null) 'speed': speed!.name,
      };

  factory RepertoireGame.fromJson(Map<String, dynamic> json) => RepertoireGame(
        id: json['id'] as String,
        side: Side.values.byName(json['side'] as String),
        sanMoves: (json['moves'] as String).split(' ').where((m) => m.isNotEmpty).toList(),
        playedAt: DateTime.fromMillisecondsSinceEpoch(json['playedAt'] as int),
        speed: GameSpeed.values.asNameMap()[json['speed']],
      );

  /// The positions of the game, starting with the initial one.
  List<Position> positions() {
    final out = <Position>[Chess.initial];
    for (final san in sanMoves) {
      final move = out.last.parseSan(san);
      if (move == null) break;
      out.add(out.last.play(move));
    }
    return out;
  }
}

/// One opening (by family name, e.g. "Sicilian Defense") and the user's
/// games in it.
@immutable
class OpeningFamily {
  const OpeningFamily({required this.name, required this.games});

  final String name;
  final List<RepertoireGame> games;

  /// The family part of a full opening name (see [OpeningBook.familyOf]).
  static String familyOf(String name) => OpeningBook.familyOf(name);

  /// The user's openings as [side], most played first.
  static List<OpeningFamily> group(
    Iterable<RepertoireGame> games,
    Side side,
    OpeningBook book,
  ) {
    final byName = <String, List<RepertoireGame>>{};
    for (final game in games.where((g) => g.side == side)) {
      final name = book.nameOfGame(game.positions());
      byName.putIfAbsent(name == null ? 'Other openings' : familyOf(name), () => []).add(game);
    }
    return [
      for (final MapEntry(:key, :value) in byName.entries) OpeningFamily(name: key, games: value),
    ]..sort((a, b) {
        // "Other" last, otherwise by how often it's played.
        if (a.name == 'Other openings') return 1;
        if (b.name == 'Other openings') return -1;
        return b.games.length.compareTo(a.games.length);
      });
  }
}

/// What was played from one position in the user's games.
@immutable
class TreeNode {
  const TreeNode(this.moves);

  /// Move (normalized UCI) -> how many games played it here.
  final Map<String, int> moves;

  int get total => moves.values.fold(0, (a, b) => a + b);

  /// Moves by frequency, most played first.
  List<MapEntry<String, int>> get ranked =>
      moves.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// The user's games in one opening merged into a tree of positions
/// (transpositions share a node).
class OpeningTree {
  OpeningTree(Iterable<RepertoireGame> games) {
    for (final game in games) {
      Position pos = Chess.initial;
      for (final san in game.sanMoves) {
        final move = pos.parseSan(san);
        if (move == null) break;
        final node = _nodes.putIfAbsent(keyOf(pos), () => {});
        node[move.uci] = (node[move.uci] ?? 0) + 1;
        pos = pos.play(move);
      }
    }
  }

  final _nodes = <String, Map<String, int>>{};

  TreeNode? at(Position position) {
    final moves = _nodes[keyOf(position)];
    return moves == null ? null : TreeNode(moves);
  }

  static String keyOf(Position position) => position.fen.split(' ').take(4).join(' ');
}
