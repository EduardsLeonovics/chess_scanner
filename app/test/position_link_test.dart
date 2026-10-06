import 'package:chess_scanner/src/share/position_link.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fen = '1r3r2/1pR2N1k/p1b1p1pP/4P2n/8/P7/1P6/1K3R2 w - - 0 1';

  test('a shared link opens the same position', () {
    final link = positionLink(fen);
    expect(link.host, PositionLinks.host);
    expect(positionFromLink(link)!.fen, fen);
  });

  test('the web page\'s app-scheme link works too', () {
    final uri = Uri.parse('chessgeek://position?fen=${Uri.encodeQueryComponent(fen)}');
    expect(positionFromLink(uri)!.fen, fen);
  });

  test('other links and broken positions are refused', () {
    expect(positionFromLink(Uri.parse('https://example.com/chessgeek/p/?fen=8/8/8/8/8/8/8/8')), isNull);
    expect(positionFromLink(positionLink('not a fen')), isNull);
    // Two white kings: parses as FEN but isn't a legal position.
    expect(positionFromLink(positionLink('4k3/8/8/8/8/8/8/K3K3 w - - 0 1')), isNull);
    expect(positionFromLink(Uri.https(PositionLinks.host, PositionLinks.path)), isNull);
  });

  test('the starting position round-trips', () {
    expect(positionFromLink(positionLink(kInitialFEN))!.fen, kInitialFEN);
  });

  test('a crafted link with impossible material is refused', () {
    final link = positionLink('rnbqkbnr/pppppppp/8/8/8/PPPPPPPP/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    expect(positionFromLink(link), isNull);
  });
}
