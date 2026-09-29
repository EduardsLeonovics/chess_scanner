import 'package:chess_scanner/main.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('analysis page shows the board and engine status', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChessScannerApp()));
    await tester.pump();

    expect(find.byType(Chessboard), findsOneWidget);
    // Tests run on the host, where native Stockfish isn't available.
    expect(find.textContaining('Android and iOS only'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();
    expect(find.text('Position (FEN)'), findsOneWidget);
  });
}
