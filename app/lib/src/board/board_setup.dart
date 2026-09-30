import 'package:dartchess/dartchess.dart';

/// Builds a playable position from a set-up board, e.g. a recognized or
/// hand-edited one.
///
/// Castling rights are granted wherever king and rook still stand on their
/// starting squares. Throws [PositionSetupException] if the position is not
/// legal.
Position positionFromBoard(Board board, Side turn) {
  var castling = SquareSet.empty;
  for (final side in Side.values) {
    final rank = side == Side.white ? Rank.first : Rank.eighth;
    if (board.pieceAt(Square.fromCoords(File.e, rank)) != Piece(color: side, role: Role.king)) {
      continue;
    }
    for (final file in [File.a, File.h]) {
      final square = Square.fromCoords(file, rank);
      if (board.pieceAt(square) == Piece(color: side, role: Role.rook)) {
        castling = castling.withSquare(square);
      }
    }
  }
  return Chess.fromSetup(
    Setup(
      board: board,
      turn: turn,
      castlingRights: castling,
      halfmoves: 0,
      fullmoves: 1,
    ),
    ignoreImpossibleCheck: true,
  );
}

/// The same position with the other side to move. Throws
/// [PositionSetupException] if that is not legal (the side that would not be
/// moving is in check).
Position withTurn(Position position, Side turn) {
  final setup = Setup.parseFen(position.fen);
  return Chess.fromSetup(
    Setup(
      board: setup.board,
      turn: turn,
      castlingRights: setup.castlingRights,
      halfmoves: setup.halfmoves,
      fullmoves: setup.fullmoves,
    ),
    ignoreImpossibleCheck: true,
  );
}

/// A short, user-facing explanation of why a position can't be analyzed.
String describeSetupError(PositionSetupException e) => switch (e.cause) {
      IllegalSetupCause.empty => 'The board is empty',
      IllegalSetupCause.kings => 'Each side needs exactly one king',
      IllegalSetupCause.oppositeCheck => 'The side not to move is in check',
      IllegalSetupCause.pawnsOnBackrank => 'Pawns can\'t stand on the first or last rank',
      IllegalSetupCause.impossibleCheck => 'That check is impossible',
      IllegalSetupCause.variant => 'That position is not valid in standard chess',
    };
