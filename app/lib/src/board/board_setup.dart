import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

/// Builds a playable position from a set-up board, e.g. a recognized or
/// hand-edited one.
///
/// Castling rights are granted wherever king and rook still stand on their
/// starting squares. Throws [PositionSetupException] if the position is not
/// legal.
Position positionFromBoard(Board board, Side turn) {
  checkMaterial(board);
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

/// [board] with its coordinates reversed: a-file and h-file swap, rank 1
/// and rank 8 swap (a1 to h8, e2 to d7, …). Fixes a scan read from the wrong
/// side; shown with the board's orientation flipped too, every piece stays
/// where it was on screen and only the coordinates change.
Board rotateBoard(Board board) {
  var rotated = Board.empty;
  for (final (square, piece) in board.pieces) {
    rotated = rotated.setPieceAt(Square(63 - square), piece);
  }
  return rotated;
}

/// [pieces] (the board editor's map) turned half a turn, see [rotateBoard].
Map<Square, Piece> rotatePieces(Map<Square, Piece> pieces) => {
      for (final MapEntry(key: square, value: piece) in pieces.entries) Square(63 - square): piece,
    };

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

/// A board with more pieces than a game can reach, see [materialProblem].
class ImpossibleMaterialException extends PositionSetupException {
  const ImpossibleMaterialException(this.message) : super(IllegalSetupCause.variant);

  /// What's wrong, for the user, e.g. "White has more than 8 pawns".
  final String message;
}

/// Why [board] can't come from a real game, or null if its material can:
/// at most 8 pawns and 16 pieces a side, and no more extra queens, rooks,
/// bishops and knights than pawns that could have promoted. Stockfish
/// crashes on boards beyond these limits, so nothing may reach it without
/// passing this check.
String? materialProblem(Board board) {
  for (final side in Side.values) {
    final name = side == Side.white ? 'White' : 'Black';
    int count(Role role) => board.piecesOf(side, role).size;
    final pawns = count(Role.pawn);
    if (pawns > 8) return '$name has more than 8 pawns';
    if (board.bySide(side).size > 16) return '$name has more than 16 pieces';
    final promoted = math.max(0, count(Role.queen) - 1) +
        math.max(0, count(Role.rook) - 2) +
        math.max(0, count(Role.bishop) - 2) +
        math.max(0, count(Role.knight) - 2);
    if (promoted > 8 - pawns) return '$name has more extra pieces than pawns that could have promoted';
  }
  return null;
}

/// Throws [ImpossibleMaterialException] if [board] fails [materialProblem].
void checkMaterial(Board board) {
  final problem = materialProblem(board);
  if (problem != null) throw ImpossibleMaterialException(problem);
}

/// Whether [fen] is a position Stockfish can safely be given: it parses,
/// its material passes [materialProblem] and it is legal.
bool isAnalyzableFen(String fen) {
  try {
    final setup = Setup.parseFen(fen);
    if (materialProblem(setup.board) != null) return false;
    Chess.fromSetup(setup, ignoreImpossibleCheck: true);
    return true;
  } on FenException {
    return false;
  } on PositionSetupException {
    return false;
  }
}

/// A short, user-facing explanation of why a position can't be analyzed.
String describeSetupError(PositionSetupException e) => e is ImpossibleMaterialException
    ? e.message
    : switch (e.cause) {
        IllegalSetupCause.empty => 'The board is empty',
        IllegalSetupCause.kings => 'Each side needs exactly one king',
        IllegalSetupCause.oppositeCheck => 'The side not to move is in check',
        IllegalSetupCause.pawnsOnBackrank => 'Pawns can\'t stand on the first or last rank',
        IllegalSetupCause.impossibleCheck => 'That check is impossible',
        IllegalSetupCause.variant => 'That position is not valid in standard chess',
      };
