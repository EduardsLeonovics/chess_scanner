import 'dart:async';
import 'dart:convert';

import 'package:chess_scanner/src/accounts/accounts.dart';
import 'package:chess_scanner/src/accounts/game_sources.dart';
import 'package:chess_scanner/src/backup/library_backup.dart';
import 'package:chess_scanner/src/community/community_repository.dart';
import 'package:chess_scanner/src/puzzles/puzzle.dart';
import 'package:chess_scanner/src/puzzles/puzzle_store.dart';
import 'package:chess_scanner/src/settings/appearance.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

Puzzle _puzzle(String id, {int attempts = 0}) => Puzzle(
      id: id,
      kind: PuzzleKind.onlyMove,
      fen: kInitialFEN,
      solution: const ['e2e4'],
      userSide: Side.white,
      playedSan: 'a3',
      bestScore: 300,
      gameId: 'g',
      site: ChessSite.lichess,
      gameUrl: '',
      opponent: 'rival',
      playedAt: DateTime(2026),
      moveNumber: 1,
      attempts: attempts,
    );

FetchedGame _game(String id, DateTime playedAt) => FetchedGame(
      id: id,
      site: ChessSite.lichess,
      account: 'me',
      url: '',
      userSide: Side.white,
      opponent: 'rival',
      playedAt: playedAt,
      sanMoves: const [],
    );

User _user(String id) => User(id: id, appMetadata: const {}, userMetadata: const {}, aud: '', createdAt: '');

class _FakeStore implements BackupStore {
  final rows = <String, Map<String, dynamic>>{};
  final saves = <Map<String, Object?>>[];
  bool offline = false;

  @override
  Future<Map<String, dynamic>?> fetch(String userId) async {
    if (offline) throw Exception('offline');
    return rows[userId];
  }

  @override
  Future<void> save(String userId, Map<String, Object?> columns) async {
    if (offline) throw Exception('offline');
    saves.add(columns);
    // As the server would store it: plain JSON.
    rows[userId] = {...?rows[userId], ...jsonDecode(jsonEncode(columns)) as Map<String, dynamic>};
  }
}

/// A row as [LibraryBackupData.toColumns] writes it, read back as JSON.
Map<String, dynamic> _row(LibraryBackupData data, {int? version}) => {
      ...jsonDecode(jsonEncode(data.toColumns())) as Map<String, dynamic>,
      'data_version': version ?? PuzzleLibraryNotifier.dataVersion,
    };

void main() {
  group('mergeBackups', () {
    test('keeps the games and puzzles of both, and the account\'s usernames', () {
      final phone = LibraryBackupData(
        accounts: const Accounts(lichess: 'phone', chessCom: 'mine'),
        library: PuzzleLibrary(
          puzzles: [_puzzle('a', attempts: 3), _puzzle('b')],
          analyzedGames: const {'g1', 'g2'},
        ),
      );
      final account = LibraryBackupData(
        accounts: const Accounts(lichess: 'account'),
        library: PuzzleLibrary(
          puzzles: [_puzzle('a', attempts: 1), _puzzle('b', attempts: 2), _puzzle('c')],
          analyzedGames: const {'g2', 'g3'},
        ),
      );
      final merged = mergeBackups(phone, account);
      expect(merged.accounts.lichess, 'account');
      expect(merged.accounts.chessCom, 'mine');
      expect(merged.library.analyzedGames, {'g1', 'g2', 'g3'});
      final attempts = {for (final p in merged.library.puzzles) p.id: p.attempts};
      expect(attempts, {'a': 3, 'b': 2, 'c': 0}, reason: 'the progress of whichever attempted it more');
    });

    test('joins overlapping spans of analyzed games, else keeps the newer', () {
      Coverage span(int from, int to, {bool first = false}) =>
          Coverage(oldest: DateTime(2026, from), newest: DateTime(2026, to), reachedFirstGame: first);
      LibraryBackupData data(Coverage c) =>
          LibraryBackupData(accounts: const Accounts(), library: PuzzleLibrary(coverage: {'k': c}));

      final joined = mergeBackups(data(span(3, 6)), data(span(1, 4, first: true))).library.coverage['k']!;
      expect(joined.oldest, DateTime(2026, 1));
      expect(joined.newest, DateTime(2026, 6));
      expect(joined.reachedFirstGame, isTrue);

      final apart = mergeBackups(data(span(1, 2)), data(span(5, 6))).library.coverage['k']!;
      expect(apart.oldest, DateTime(2026, 5));
    });
  });

  test('a row survives the trip to the server and back', () {
    final data = LibraryBackupData(
      accounts: const Accounts(chessCom: 'me'),
      library: PuzzleLibrary(
        puzzles: [_puzzle('a', attempts: 2)],
        analyzedGames: const {'g1'},
        coverage: {'k': Coverage(oldest: DateTime(2026), newest: DateTime(2026, 2))},
      ),
    );
    final back = LibraryBackupData.fromRow(_row(data));
    expect(jsonEncode(back.toColumns()), jsonEncode(data.toColumns()));
  });

  test('a row from an older analysis keeps the puzzles but not the analyzed games', () {
    final data = LibraryBackupData(
      accounts: const Accounts(lichess: 'me'),
      library: PuzzleLibrary(puzzles: [_puzzle('a')], analyzedGames: const {'g1'}),
    );
    final back = LibraryBackupData.fromRow(_row(data, version: PuzzleLibraryNotifier.dataVersion - 1));
    expect(back.library.puzzles, hasLength(1));
    expect(back.library.analyzedGames, isEmpty);
    expect(back.accounts.lichess, 'me');
  });

  group('LibraryBackup', () {
    late ProviderContainer container;
    late _FakeStore store;
    late StreamController<User?> users;
    late SharedPreferences prefs;

    Future<void> start({Map<String, Object> saved = const {}}) async {
      SharedPreferences.setMockInitialValues(saved);
      prefs = await SharedPreferences.getInstance();
      store = _FakeStore();
      users = StreamController<User?>();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backupStoreProvider.overrideWithValue(store),
        communityUserProvider.overrideWith((ref) => users.stream),
      ]);
      container.listen(libraryBackupProvider, (_, _) {});
      users.add(null);
      await pumpEventQueue();
    }

    Future<void> signIn(String id) async {
      users.add(_user(id));
      await pumpEventQueue();
    }

    tearDown(() {
      container.dispose();
      users.close();
    });

    test('signing in after a reinstall brings the library back', () async {
      await start();
      store.rows['u1'] = _row(LibraryBackupData(
        accounts: const Accounts(lichess: 'me'),
        library: PuzzleLibrary(puzzles: [_puzzle('a')], analyzedGames: const {'g1'}),
      ));
      await signIn('u1');
      expect(container.read(accountsProvider).lichess, 'me');
      expect(container.read(puzzleLibraryProvider).analyzedGames, {'g1'});
      expect(container.read(puzzleLibraryProvider).puzzles.single.id, 'a');
      expect(store.saves, isEmpty, reason: 'nothing new to upload');
      expect(container.read(libraryBackupProvider), BackupStatus.saved);
    });

    test('the first sign-in uploads what the phone has, then only changes', () async {
      await start(saved: {'accounts.lichess': 'me'});
      container.read(puzzleLibraryProvider.notifier).addGame(_game('g1', DateTime(2026)), [_puzzle('a')]);
      await signIn('u1');
      expect(store.saves, hasLength(1));
      expect(store.rows['u1']!['analyzed_games'], ['g1']);
      expect(store.rows['u1']!['accounts'], {'lichess': 'me'});

      container.read(puzzleLibraryProvider.notifier).recordResult('a', PuzzleResult.solved);
      expect(await container.read(libraryBackupProvider.notifier).upload(), isTrue);
      expect(store.saves.last.keys, unorderedEquals(['puzzles', 'data_version']));
    });

    test('signing out saves first, then clears the phone', () async {
      await start(saved: {'accounts.lichess': 'me'});
      await signIn('u1');
      container.read(puzzleLibraryProvider.notifier).addGame(_game('g1', DateTime(2026)), [_puzzle('a')]);
      expect(await container.read(libraryBackupProvider.notifier).signOut(), isTrue);
      expect(store.rows['u1']!['analyzed_games'], ['g1']);
      expect(container.read(accountsProvider).any, isFalse);
      expect(container.read(puzzleLibraryProvider).puzzles, isEmpty);
    });

    test('signing out offline needs force', () async {
      await start(saved: {'accounts.lichess': 'me'});
      await signIn('u1');
      store.offline = true;
      container.read(puzzleLibraryProvider.notifier).addGame(_game('g1', DateTime(2026)), [_puzzle('a')]);
      final backup = container.read(libraryBackupProvider.notifier);
      expect(await backup.signOut(), isFalse);
      expect(container.read(puzzleLibraryProvider).puzzles, hasLength(1), reason: 'still on the phone');
      expect(await backup.signOut(force: true), isTrue);
      expect(container.read(puzzleLibraryProvider).puzzles, isEmpty);
    });

    test('another user signing in doesn\'t get the previous user\'s library', () async {
      await start(saved: {'accounts.lichess': 'first'});
      await signIn('u1');
      // u1's session ends without signing out; u2 signs in.
      users.add(null);
      await pumpEventQueue();
      await signIn('u2');
      expect(container.read(accountsProvider).any, isFalse);
      expect(store.rows['u2'], isNull, reason: 'nothing of u1 uploaded to u2');
    });
  });
}
