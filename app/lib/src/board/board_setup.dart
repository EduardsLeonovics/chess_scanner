import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

/// Builds a playable position from a set-up board, e.g. a recognized or
/// hand-edited one.
///
/// Any material is allowed (20 queens a side is fine to set up and share),
/// but each side needs exactly one king and the side to move must not
/// already be checkmated. Castling rights are granted wherever king and rook
/// still stand on their starting squares. Throws [PositionSetupException]
/// if the position can't be played.
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
  return checkNotCheckmate(Chess.fromSetup(
    Setup(
      board: board,
      turn: turn,
      castlingRights: castling,
      halfmoves: 0,
      fullmoves: 1,
    ),
    ignoreImpossibleCheck: true,
  ));
}

/// [position], or throws [PositionRuleException] if the side to move is
/// already checkmated: there would be nothing to play or analyze.
Position checkNotCheckmate(Position position) {
  if (position.isCheckmate) {
    final side = position.turn == Side.white ? 'White' : 'Black';
    throw PositionRuleException('$side is already checkmated');
  }
  return position;
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

/// A position our own rules refuse (see [checkNotCheckmate]).
class PositionRuleException extends PositionSetupException {
  const PositionRuleException(this.message) : super(IllegalSetupCause.variant);

  /// What's wrong, for the user, e.g. "White is already checkmated".
  final String message;
}

/// Why Stockfish can't analyze [board], or null if it can: its material
/// must be reachable in a real game (at most 8 pawns and 16 pieces a side,
/// and no more extra queens, rooks, bishops and knights than pawns that
/// could have promoted). Stockfish's fixed-size tables overflow beyond that
/// and crash the app, so nothing may reach it without passing this check.
/// Such positions can still be set up, viewed and shared.
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
String describeSetupError(PositionSetupException e) => e is PositionRuleException
    ? e.message
    : switch (e.cause) {
        IllegalSetupCause.empty => 'The board is empty',
        IllegalSetupCause.kings => 'Each side needs exactly one king',
        IllegalSetupCause.oppositeCheck => 'The side not to move is in check',
        IllegalSetupCause.pawnsOnBackrank => 'Pawns can\'t stand on the first or last rank',
        IllegalSetupCause.impossibleCheck => 'That check is impossible',
        IllegalSetupCause.variant => 'That position is not valid in standard chess',
      };
