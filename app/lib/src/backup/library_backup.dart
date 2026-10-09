import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../accounts/accounts.dart';
import '../accounts/game_sources.dart';
import '../community/community_config.dart';
import '../community/community_repository.dart';
import '../openings/repertoire.dart';
import '../puzzles/puzzle.dart';
import '../puzzles/puzzle_store.dart';
import '../settings/appearance.dart';
import '../skills/skill_stats.dart';

/// The user's linked accounts and game library as stored in their
/// ChessHive account (the `libraries` table in backend/supabase/schema.sql):
/// everything but the queue of games still to analyze, which is downloaded
/// again when needed.
@immutable
class LibraryBackupData {
  const LibraryBackupData({required this.accounts, required this.library});

  final Accounts accounts;
  final PuzzleLibrary library;

  bool get isEmpty => !accounts.any && library.puzzles.isEmpty && library.analyzedGames.isEmpty;

  /// The table's columns, part by part.
  Map<String, Object?> toColumns() => {
        'accounts': accounts.toJson(),
        'puzzles': [for (final p in library.puzzles) p.toJson()],
        'analyzed_games': library.analyzedGames.toList()..sort(),
        'coverage': {for (final e in library.coverage.entries) e.key: e.value.toJson()},
        'game_stats': {for (final e in library.gameStats.entries) e.key: e.value.toJson()},
        'opening_games': [for (final g in library.openingGames.values) g.toJson()],
      };

  /// Reads a row. The analysis parts of a row written under an older
  /// [PuzzleLibraryNotifier.dataVersion] are left out, as on the phone:
  /// those games are analyzed again.
  factory LibraryBackupData.fromRow(Map<String, dynamic> row) {
    final current = (row['data_version'] as int? ?? 1) >= PuzzleLibraryNotifier.dataVersion;
    Map<String, dynamic> map(String column) => (row[column] as Map?)?.cast<String, dynamic>() ?? const {};
    List<dynamic> list(String column) => row[column] as List<dynamic>? ?? const [];
    return LibraryBackupData(
      accounts: Accounts.fromJson(map('accounts')),
      library: PuzzleLibrary(
        puzzles: mixPuzzles([for (final p in list('puzzles')) Puzzle.fromJson(p as Map<String, dynamic>)]),
        analyzedGames: current ? list('analyzed_games').cast<String>().toSet() : const {},
        coverage: current
            ? {
                for (final MapEntry(:key, :value) in map('coverage').entries)
                  key: Coverage.fromJson(value as Map<String, dynamic>),
              }
            : const {},
        gameStats: current
            ? {
                for (final MapEntry(:key, :value) in map('game_stats').entries)
                  key: GameSkillStats.fromJson(value as Map<String, dynamic>),
              }
            : const {},
        openingGames: {
          for (final game in [
            for (final g in list('opening_games')) RepertoireGame.fromJson(g as Map<String, dynamic>),
          ])
            game.id: game,
        },
      ),
    );
  }
}

/// Combines this phone's data with the account's, so neither loses
/// anything: games analyzed on either count, a puzzle keeps the progress
/// of whichever side attempted it more, and the account's linked usernames
/// win over the phone's.
LibraryBackupData mergeBackups(LibraryBackupData phone, LibraryBackupData account) {
  final puzzles = {for (final p in phone.library.puzzles) p.id: p};
  for (final p in account.library.puzzles) {
    final mine = puzzles[p.id];
    if (mine == null || _furtherAlong(p, mine)) puzzles[p.id] = p;
  }
  final coverage = {...phone.library.coverage};
  for (final MapEntry(:key, :value) in account.library.coverage.entries) {
    final mine = coverage[key];
    coverage[key] = mine == null ? value : _mergeCoverage(mine, value);
  }
  return LibraryBackupData(
    accounts: Accounts(
      lichess: account.accounts.lichess ?? phone.accounts.lichess,
      chessCom: account.accounts.chessCom ?? phone.accounts.chessCom,
    ),
    library: PuzzleLibrary(
      puzzles: mixPuzzles(puzzles.values),
      analyzedGames: {...phone.library.analyzedGames, ...account.library.analyzedGames},
      coverage: coverage,
      gameStats: {...account.library.gameStats, ...phone.library.gameStats},
      openingGames: {...account.library.openingGames, ...phone.library.openingGames},
    ),
  );
}

bool _furtherAlong(Puzzle a, Puzzle b) {
  if (a.attempts != b.attempts) return a.attempts > b.attempts;
  final seenA = a.lastSeen, seenB = b.lastSeen;
  return seenA != null && (seenB == null || seenA.isAfter(seenB));
}

/// One span when the two overlap. Otherwise the newer one: the games of the
/// other are still known as analyzed, so they're skipped when the older
/// games are loaded again.
Coverage _mergeCoverage(Coverage a, Coverage b) {
  final overlap = !a.oldest.isAfter(b.newest) && !b.oldest.isAfter(a.newest);
  if (!overlap) return a.newest.isAfter(b.newest) ? a : b;
  final older = a.oldest.isBefore(b.oldest) ? a : b;
  return Coverage(
    newest: a.newest.isAfter(b.newest) ? a.newest : b.newest,
    oldest: older.oldest,
    reachedFirstGame:
        a.oldest == b.oldest ? a.reachedFirstGame || b.reachedFirstGame : older.reachedFirstGame,
  );
}

/// Where backups are kept. Replaceable for tests.
abstract interface class BackupStore {
  /// The user's row, or null if they have none yet.
  Future<Map<String, dynamic>?> fetch(String userId);

  /// Writes [columns] (with `data_version`) to the user's row.
  Future<void> save(String userId, Map<String, Object?> columns);
}

class SupabaseBackupStore implements BackupStore {
  SupabaseBackupStore(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> fetch(String userId) =>
      _client.from('libraries').select().eq('user_id', userId).maybeSingle();

  @override
  Future<void> save(String userId, Map<String, Object?> columns) =>
      _client.from('libraries').upsert({'user_id': userId, ...columns});
}

/// Null without a community server (tests, unconfigured builds).
final backupStoreProvider = Provider<BackupStore?>(
  (ref) => CommunityConfig.ready ? SupabaseBackupStore(Supabase.instance.client) : null,
);

enum BackupStatus {
  /// Signed out, or no server.
  off,
  syncing,
  saved,

  /// The last upload failed (usually no connection); it's tried again on
  /// the next change and at the next launch.
  failed,
}

final libraryBackupProvider = NotifierProvider<LibraryBackup, BackupStatus>(LibraryBackup.new);

/// Keeps the signed-in user's library in their ChessHive account.
///
/// When they sign in (or the app starts signed in), the account's copy is
/// merged with the phone's (see [mergeBackups]) and the result kept on
/// both. After that, changes are uploaded a little later, only the parts
/// that changed. Signing out ([signOut]) removes the library from the phone.
class LibraryBackup extends Notifier<BackupStatus> {
  /// The user the phone's library belongs to. A library left by another
  /// user (whose session ended without signing out) is removed when
  /// someone else signs in.
  static const _ownerKey = 'backup.owner';
  static const _uploadDelay = Duration(seconds: 20);

  /// The user whose library is in sync and uploaded on changes.
  String? _user;

  /// Per column, the JSON known to be in the account.
  final _uploaded = <String, String>{};

  Timer? _timer;
  Future<bool>? _uploading;

  @override
  BackupStatus build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(communityUserProvider.select((user) => user.value?.id), (_, id) {
      // Not from within build: syncing changes the state.
      scheduleMicrotask(() => id == null ? _stop() : _sync(id));
    }, fireImmediately: true);
    ref.listen(puzzleLibraryProvider, (_, _) => _changed());
    ref.listen(accountsProvider, (_, _) => _changed());
    return BackupStatus.off;
  }

  void _stop() {
    _user = null;
    _timer?.cancel();
    _timer = null;
    _uploaded.clear();
    state = BackupStatus.off;
  }

  LibraryBackupData get _phone =>
      LibraryBackupData(accounts: ref.read(accountsProvider), library: ref.read(puzzleLibraryProvider));

  Future<void> _sync(String userId) async {
    final store = ref.read(backupStoreProvider);
    if (store == null || _user == userId) return;
    _stop();
    state = BackupStatus.syncing;
    final prefs = ref.read(sharedPreferencesProvider);
    final owner = prefs.getString(_ownerKey);
    if (owner != null && owner != userId) await _clearPhone();
    try {
      final row = await store.fetch(userId);
      if (ref.read(communityUserProvider).value?.id != userId) return;
      if (row != null && (row['data_version'] as int? ?? 1) > PuzzleLibraryNotifier.dataVersion) {
        // Written by a newer version of the app: leave it alone.
        state = BackupStatus.failed;
        return;
      }
      final account = row == null ? null : LibraryBackupData.fromRow(row);
      // Merged with the phone's library as it is now, after the download:
      // a run may have added games meanwhile.
      final merged = account == null ? _phone : mergeBackups(_phone, account);
      ref.read(puzzleLibraryProvider.notifier).restore(merged.library);
      await ref.read(accountsProvider.notifier).replace(merged.accounts);
      await prefs.setString(_ownerKey, userId);
      if (account != null) {
        for (final MapEntry(:key, :value) in account.toColumns().entries) {
          _uploaded[key] = jsonEncode(value);
        }
      }
      _user = userId;
      if (account == null && merged.isEmpty) {
        // Nothing to keep yet: the row is made with the first games.
        state = BackupStatus.saved;
      } else {
        await upload();
      }
    } catch (e) {
      debugPrint('Library backup: $e');
      state = BackupStatus.failed;
    }
  }

  void _changed() {
    if (_user == null) return;
    _timer ??= Timer(_uploadDelay, upload);
  }

  /// Uploads what changed since the last upload. True when the account has
  /// everything (also when there was nothing to upload).
  Future<bool> upload() async {
    for (var running = _uploading; running != null; running = _uploading) {
      await running;
    }
    final upload = _uploading = _upload();
    try {
      return await upload;
    } finally {
      _uploading = null;
    }
  }

  Future<bool> _upload() async {
    _timer?.cancel();
    _timer = null;
    final user = _user;
    final store = ref.read(backupStoreProvider);
    if (user == null || store == null) return false;
    final changed = <String, Object?>{};
    final encoded = <String, String>{};
    for (final MapEntry(:key, :value) in _phone.toColumns().entries) {
      final json = jsonEncode(value);
      if (_uploaded[key] != json) {
        changed[key] = value;
        encoded[key] = json;
      }
    }
    if (changed.isEmpty) {
      state = BackupStatus.saved;
      return true;
    }
    state = BackupStatus.syncing;
    try {
      await store.save(user, {...changed, 'data_version': PuzzleLibraryNotifier.dataVersion});
      _uploaded.addAll(encoded);
      if (_user == user) state = BackupStatus.saved;
      return true;
    } catch (e) {
      debugPrint('Library backup: $e');
      if (_user == user) state = BackupStatus.failed;
      return false;
    }
  }

  /// Uploads what isn't in the account yet, signs out and removes the
  /// library from the phone. Without [force], returns false (still signed
  /// in) when the upload failed. Throws [CommunityException].
  Future<bool> signOut({bool force = false}) async {
    if (!force && _user != null && !await upload()) return false;
    await ref.read(communityProvider)?.signOut();
    _stop();
    await _clearPhone();
    return true;
  }

  /// Deletes the account (with its backup) and removes the library from
  /// the phone. Throws [CommunityException].
  Future<void> deleteAccount() async {
    await ref.read(communityProvider)?.deleteAccount();
    _stop();
    await _clearPhone();
  }

  Future<void> _clearPhone() async {
    ref.read(puzzleLibraryProvider.notifier).deleteAll();
    await ref.read(accountsProvider.notifier).replace(const Accounts());
    await ref.read(sharedPreferencesProvider).remove(_ownerKey);
  }
}
