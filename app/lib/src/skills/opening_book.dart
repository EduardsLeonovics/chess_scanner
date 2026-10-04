import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every position that occurs in a named opening line ("theory"), from the
/// Lichess chess-openings data set bundled in `assets/openings/`.
class OpeningBook {
  OpeningBook._(this._positions, this._continued, this._names);

  /// Builds the book from the data set's TSV text (`eco \t name \t pgn`).
  factory OpeningBook.parse(String tsv) {
    final positions = <String>{_key(Chess.initial)};
    final continued = <String>{};
    final names = <String, String>{};
    for (final line in tsv.split('\n')) {
      if (line.isEmpty || line.startsWith('#') || line.startsWith('eco\t')) continue;
      final columns = line.split('\t');
      if (columns.length < 3) continue;
      Position pos = Chess.initial;
      var complete = true;
      for (final token in columns[2].split(' ')) {
        if (token.isEmpty || token.endsWith('.')) continue;
        final move = pos.parseSan(token);
        if (move == null) {
          complete = false;
          break;
        }
        continued.add(_key(pos));
        pos = pos.play(move);
        positions.add(_key(pos));
      }
      // A line names the position it ends in (first name wins).
      if (complete) names.putIfAbsent(_key(pos), () => columns[1]);
    }
    return OpeningBook._(positions, continued, names);
  }

  final Set<String> _positions;

  /// Positions some book line plays on from.
  final Set<String> _continued;
  final Map<String, String> _names;

  int get size => _positions.length;

  /// Whether [position] is a known theory position (transpositions included).
  bool contains(Position position) => _positions.contains(_key(position));

  /// Whether the book has a move from [position]. When it hasn't, the
  /// theory simply ends there; nobody "left" it.
  bool continues(Position position) => _continued.contains(_key(position));

  /// The opening's name if [position] ends a named line, e.g.
  /// "Sicilian Defense: Najdorf Variation".
  String? nameOf(Position position) => _names[_key(position)];

  /// The most specific opening name reached in a game: the last position
  /// along [positions] that has a name.
  String? nameOfGame(Iterable<Position> positions) {
    String? name;
    for (final pos in positions) {
      name = nameOf(pos) ?? name;
    }
    return name;
  }

  /// Board, side to move, castling rights and en-passant square: the move
  /// counters don't matter for theory.
  static String _key(Position position) => position.fen.split(' ').take(4).join(' ');
}

final openingBookProvider = FutureProvider<OpeningBook>((ref) async {
  return OpeningBook.parse(await rootBundle.loadString('assets/openings/openings.tsv'));
});
