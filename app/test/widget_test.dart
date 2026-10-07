import 'package:chess_scanner/main.dart';
import 'package:chess_scanner/src/community/community_repository.dart';
import 'package:chess_scanner/src/diagnostics/crash_log.dart';
import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:chess_scanner/src/settings/settings_page.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _pumpApp(WidgetTester tester, {bool signedIn = false}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      crashLogProvider.overrideWithValue(CrashLog(prefs)),
      if (signedIn) signedInProvider.overrideWithValue(true),
    ],
    child: const ChessGeekApp(),
  ));
  await tester.pump();
  return prefs;
}

SegmentedButton<Side> _toggle(WidgetTester tester, int index) =>
    tester.widgetList<SegmentedButton<Side>>(find.byType(SegmentedButton<Side>)).elementAt(index);

void main() {
  testWidgets('analysis page shows the board and engine status', (tester) async {
    await _pumpApp(tester);

    expect(find.byType(Chessboard), findsOneWidget);
    expect(find.byTooltip('Scan a position'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    // Tests run on the host, where native Stockfish isn't available.
    expect(find.textContaining('Android and iOS only'), findsOneWidget);
  });

  testWidgets('Move toggles the side to move', (tester) async {
    await _pumpApp(tester);

    expect(_toggle(tester, 0).selected, {Side.white});
    await tester.tap(find.text('Black').first);
    await tester.pump();
    expect(_toggle(tester, 0).selected, {Side.black});
  });

  testWidgets('Side flips the board perspective', (tester) async {
    await _pumpApp(tester);

    expect(tester.widget<Chessboard>(find.byType(Chessboard)).orientation, Side.white);
    await tester.tap(find.text('Black').last);
    await tester.pump();
    expect(_toggle(tester, 1).selected, {Side.black});
    expect(tester.widget<Chessboard>(find.byType(Chessboard)).orientation, Side.black);
    // The side to move is unaffected.
    expect(_toggle(tester, 0).selected, {Side.white});
  });

  testWidgets('Rotate swaps the coordinates; the pieces stay put on screen', (tester) async {
    await _pumpApp(tester);

    Chessboard board() => tester.widget<Chessboard>(find.byType(Chessboard));
    expect(board().controller.game.fen, startsWith('rnbqkbnr/pppppppp/'));
    await tester.tap(find.bySemanticsLabel('Rotate board'));
    await tester.pump();
    // a1 is now h8 and so on, shown from Black's side: White's pieces are
    // still at the bottom of the screen, only the labels changed.
    expect(board().controller.game.fen, startsWith('RNBKQBNR/PPPPPPPP/8/8/8/8/pppppppp/rnbkqbnr'));
    expect(board().orientation, Side.black);
    await tester.tap(find.bySemanticsLabel('Rotate board'));
    await tester.pump();
    expect(board().controller.game.fen, startsWith('rnbqkbnr/pppppppp/'));
    expect(board().orientation, Side.white);
  });

  testWidgets('the board controls offer sharing', (tester) async {
    await _pumpApp(tester);
    expect(find.byTooltip('Share position'), findsOneWidget);
  });

  testWidgets('edit mode swaps in the board editor and back', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('Edit board'));
    await tester.pump();
    expect(find.byType(ChessboardEditor), findsOneWidget);

    await tester.tap(find.byTooltip('Done'));
    await tester.pump();
    expect(find.byType(Chessboard), findsOneWidget);
  });

  testWidgets('the other tabs leave the board', (tester) async {
    await _pumpApp(tester);

    for (final tab in ['Puzzles', 'Community', 'Openings', 'Skills']) {
      await tester.tap(find.bySemanticsLabel(tab));
      await tester.pumpAndSettle();
      expect(find.byType(Chessboard, skipOffstage: true), findsNothing);
    }
    await tester.tap(find.bySemanticsLabel('Scan'));
    await tester.pumpAndSettle();
    expect(find.byType(Chessboard), findsOneWidget);
  });

  testWidgets('Community sits between Puzzles and Openings', (tester) async {
    await _pumpApp(tester);

    double x(String tab) => tester.getCenter(find.bySemanticsLabel(tab)).dx;
    expect(x('Puzzles'), lessThan(x('Community')));
    expect(x('Community'), lessThan(x('Openings')));
    await tester.tap(find.bySemanticsLabel('Community'));
    await tester.pumpAndSettle();
    // Tests have no community server.
    expect(find.text('Community unavailable'), findsOneWidget);
  });

  testWidgets('Share offers posting to the community or a link', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('Share position'));
    await tester.pumpAndSettle();
    expect(find.text('Post to the ChessGeek community'), findsOneWidget);
    expect(find.text('Share a link'), findsOneWidget);
    // Without a community server the internal option is off.
    final post = tester.widget<ListTile>(
      find.ancestor(of: find.text('Post to the ChessGeek community'), matching: find.byType(ListTile)),
    );
    expect(post.enabled, isFalse);
  });

  testWidgets('settings change and remember the board theme', (tester) async {
    // Connecting accounts needs a ChessGeek sign-in.
    final prefs = await _pumpApp(tester, signedIn: true);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Customization'), findsOneWidget);
    // Account connect buttons sit above the customization options.
    final lichess = find.text('Connect to Lichess');
    expect(lichess, findsOneWidget);
    expect(find.text('Connect to Chess.com'), findsOneWidget);
    expect(
      tester.getTopLeft(lichess).dy,
      lessThan(tester.getTopLeft(find.text('Customization')).dy),
    );
    final settingsList = find
        .descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable))
        .first;
    for (final title in ['Board theme', 'Pieces', 'Board color', 'Piece color']) {
      await tester.scrollUntilVisible(find.text(title), 100, scrollable: settingsList);
      expect(find.text(title), findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Green'),
      -100,
      scrollable: settingsList,
    );
    await tester.ensureVisible(find.bySemanticsLabel('Green'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Green'));
    await tester.pump();
    expect(prefs.getString('appearance.boardTheme'), 'green');

    await tester.pageBack();
    await tester.pumpAndSettle();
    final board = tester.widget<Chessboard>(find.byType(Chessboard));
    expect(board.settings.colorScheme, ChessboardColorScheme.green);
  });
}
