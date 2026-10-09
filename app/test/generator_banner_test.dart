import 'package:chess_scanner/src/puzzles/generator_banner.dart';
import 'package:chess_scanner/src/puzzles/puzzle_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const running = GeneratorState(running: true, done: 20, total: 100, found: 3, message: 'Analyzing game 21 of 100');

  Widget app(GeneratorState state) => ProviderScope(
        child: MaterialApp(home: Scaffold(body: Column(children: [GeneratorBanner(state: state)]))),
      );

  testWidgets('while running: one short note, no counter, no background', (tester) async {
    await tester.pumpWidget(app(running));
    expect(find.text('Analyzing games in the background. This will take some time.'), findsOneWidget);
    expect(find.textContaining('21'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // The buttons have their own (transparent) Material; nothing paints a panel.
    final panels = tester
        .widgetList<Material>(find.descendant(of: find.byType(GeneratorBanner), matching: find.byType(Material)))
        .where((m) => m.type != MaterialType.button && m.type != MaterialType.transparency);
    expect(panels, isEmpty);
  });

  testWidgets('Hide removes the note', (tester) async {
    await tester.pumpWidget(app(running));
    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(find.textContaining('Analyzing'), findsNothing);
  });
}
