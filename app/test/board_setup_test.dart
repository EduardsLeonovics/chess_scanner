import 'package:chess_scanner/src/board/board_setup.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('positionFromBoard', () {
    test('grants castling where king and rooks are home', () {
      final board = Board.parseFen('r3k2r/8/8/8/8/8/8/R3K1R1');
      final position = positionFromBoard(board, Side.white);
      expect(position.fen, 'r3k2r/8/8/8/8/8/8/R3K1R1 w Qkq - 0 1');
    });

    test('sets the side to move', () {
      final position = positionFromBoard(Board.standard, Side.black);
      expect(position.turn, Side.black);
    });

    test('rejects a board without kings', () {
      expect(
        () => positionFromBoard(Board.parseFen('8/8/8/8/8/8/8/R7'), Side.white),
        throwsA(isA<PositionSetupException>()),
      );
    });
  });

  group('withTurn', () {
    test('switches the side to move', () {
      final black = withTurn(Chess.initial, Side.black);
      expect(black.turn, Side.black);
      expect(black.board, Chess.initial.board);
    });

    test('refuses a side to move that would leave the other king in check', () {
      // Black is in check, so it must be Black to move.
      final position = Chess.fromSetup(Setup.parseFen('4k3/8/8/8/8/8/8/4K2R b - - 0 1'));
      final checked = Chess.fromSetup(Setup.parseFen('4k2R/8/8/8/8/8/8/4K3 b - - 0 1'));
      expect(withTurn(position, Side.white).turn, Side.white);
      expect(
        () => withTurn(checked, Side.white),
        throwsA(isA<PositionSetupException>().having(
          (e) => describeSetupError(e),
          'message',
          'The side not to move is in check',
        )),
      );
    });
  });

  group('rotateBoard', () {
    test('moves every piece to the opposite square', () {
      final board = Board.parseFen('4k3/8/8/8/8/8/4P3/R3K3');
      // a1 -> h8, e1 -> d8, e2 -> d7, e8 -> d1.
      expect(rotateBoard(board), Board.parseFen('3K3R/3P4/8/8/8/8/8/3k4'));
    });

    test('twice gives back the same board', () {
      final board = Board.parseFen('1r3r2/1pR2N1k/p1b1p1pP/4P2n/8/P7/1P6/1K3R2');
      expect(rotateBoard(rotateBoard(board)), board);
    });

    test('turns a starting position read from the wrong side the right way up', () {
      expect(rotateBoard(rotateBoard(Board.standard)), Board.standard);
      final upsideDown = Board.parseFen('RNBKQBNR/PPPPPPPP/8/8/8/8/pppppppp/rnbkqbnr');
      expect(rotateBoard(upsideDown), Board.standard);
    });

    test('the editor map rotates the same way', () {
      final pieces = {Square.a1: Piece.whiteRook, Square.e2: Piece.blackPawn};
      expect(rotatePieces(pieces), {Square.h8: Piece.whiteRook, Square.d7: Piece.blackPawn});
    });
  });
}
