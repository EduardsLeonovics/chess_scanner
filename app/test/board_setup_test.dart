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
}
