import 'dart:async';
import 'dart:convert';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'accounts.dart';

/// How fast a game was played. Lichess's ultraBullet counts as bullet and
/// its correspondence as daily; Chess.com files classical games under rapid.
enum GameSpeed {
  bullet('Bullet'),
  blitz('Blitz'),
  rapid('Rapid'),
  classical('Classical'),
  daily('Daily');

  const GameSpeed(this.label);

  final String label;

  /// From Lichess's `speed` or Chess.com's `time_class`.
  static GameSpeed? parse(String? name) => switch (name) {
        'ultraBullet' || 'bullet' => bullet,
        'blitz' => blitz,
        'rapid' => rapid,
        'classical' => classical,
        'correspondence' || 'daily' => daily,
        _ => null,
      };
}

/// A finished standard-chess game of the user's, as SAN moves from the
/// starting position.
class FetchedGame {
  const FetchedGame({
    required this.id,
    required this.site,
    required this.account,
    required this.url,
    required this.userSide,
    required this.opponent,
    required this.playedAt,
    required this.sanMoves,
    this.opponentRating,
    this.speed,
    this.initialFen = kInitialFEN,
    this.clocks,
    this.increment = 0,
  });

  /// Unique across sites, e.g. `lichess:abcd1234`.
  final String id;
  final ChessSite site;

  /// The user's username on [site].
  final String account;
  final String url;
  final Side userSide;
  final String opponent;

  /// The opponent's rating when the game was played.
  final int? opponentRating;
  final GameSpeed? speed;
  final DateTime playedAt;
  final List<String> sanMoves;
  final String initialFen;

  /// Each player's remaining time after each ply, in centiseconds (same
  /// length as [sanMoves] or shorter), when the site recorded the clock.
  final List<int>? clocks;

  /// Seconds added after every move.
  final int increment;

  String get accountKey => accountKeyOf(site, account);

  Map<String, dynamic> toJson() => {
        'id': id,
        'site': site.name,
        'account': account,
        'url': url,
        'userSide': userSide.name,
        'opponent': opponent,
        'opponentRating': opponentRating,
        'speed': speed?.name,
        'playedAt': playedAt.millisecondsSinceEpoch,
        'sanMoves': sanMoves,
        'initialFen': initialFen,
        if (clocks != null) 'clocks': clocks,
        if (increment != 0) 'increment': increment,
      };

  factory FetchedGame.fromJson(Map<String, dynamic> json) => FetchedGame(
        id: json['id'] as String,
        site: ChessSite.values.byName(json['site'] as String),
        account: json['account'] as String,
        url: json['url'] as String,
        userSide: Side.values.byName(json['userSide'] as String),
        opponent: json['opponent'] as String,
        opponentRating: json['opponentRating'] as int?,
        speed: switch (json['speed']) {
          final String name => GameSpeed.values.byName(name),
          _ => null,
        },
        playedAt: DateTime.fromMillisecondsSinceEpoch(json['playedAt'] as int),
        sanMoves: (json['sanMoves'] as List<dynamic>).cast<String>(),
        initialFen: json['initialFen'] as String,
        clocks: (json['clocks'] as List<dynamic>?)?.cast<int>(),
        increment: json['increment'] as int? ?? 0,
      );
}

/// Identifies one account, e.g. `chessCom:hikaru`.
String accountKeyOf(ChessSite site, String username) => '${site.name}:${username.toLowerCase()}';

/// Which of an account's games have been analyzed: everything played from
/// [oldest] to [newest]. Games are analyzed in an order that keeps this
/// span gap-free, so the next load only needs what lies outside it.
@immutable
class Coverage {
  const Coverage({required this.newest, required this.oldest, this.reachedFirstGame = false});

  final DateTime newest;
  final DateTime oldest;

  /// Nothing older than [oldest] is left to analyze.
  final bool reachedFirstGame;

  Coverage include(DateTime playedAt) => Coverage(
        newest: playedAt.isAfter(newest) ? playedAt : newest,
        oldest: playedAt.isBefore(oldest) ? playedAt : oldest,
        reachedFirstGame: reachedFirstGame,
      );

  Coverage withReachedFirstGame() =>
      Coverage(newest: newest, oldest: oldest, reachedFirstGame: true);

  Map<String, dynamic> toJson() => {
        'newest': newest.millisecondsSinceEpoch,
        'oldest': oldest.millisecondsSinceEpoch,
        'reachedFirstGame': reachedFirstGame,
      };

  factory Coverage.fromJson(Map<String, dynamic> json) => Coverage(
        newest: DateTime.fromMillisecondsSinceEpoch(json['newest'] as int),
        oldest: DateTime.fromMillisecondsSinceEpoch(json['oldest'] as int),
        reachedFirstGame: json['reachedFirstGame'] as bool? ?? false,
      );
}

/// Not-yet-analyzed games of one account, in the order to analyze them.
class GameBatch {
  const GameBatch({
    this.newer = const [],
    this.older = const [],
    this.reachedFirstGame = false,
    this.warning,
  });

  /// Played after the analyzed span, oldest first.
  final List<FetchedGame> newer;

  /// Played before the analyzed span (or the latest games on a first load),
  /// newest first.
  final List<FetchedGame> older;

  /// [older] ends at the account's very first game.
  final bool reachedFirstGame;

  /// Set when the download stopped early; the games above are still usable.
  final String? warning;
}

class GameSourceException implements Exception {
  const GameSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef StatusCallback = void Function(String status);

const _timeout = Duration(seconds: 20);
const _headers = {'User-Agent': 'ChessScanner/1.0 (Flutter; puzzle trainer)'};

/// Lichess allows one request at a time per IP and asks clients to wait a
/// full minute after a 429.
const _rateLimitWait = Duration(seconds: 61);
const _rateLimitRetries = 3;

/// Checks [username] exists on [site] and returns it as the site spells it.
Future<String> verifyAccount(ChessSite site, String username, {http.Client? client}) async {
  final name = username.trim();
  if (name.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{2,30}$').hasMatch(name)) {
    throw const GameSourceException('That doesn\'t look like a valid username.');
  }
  final uri = switch (site) {
    ChessSite.lichess => Uri.https('lichess.org', '/api/user/$name'),
    ChessSite.chessCom => Uri.https('api.chess.com', '/pub/player/${name.toLowerCase()}'),
  };
  final response = await _get(uri, client: client);
  if (response.statusCode == 404 || response.statusCode == 410) {
    throw GameSourceException('No ${site.label} account named "$name".');
  }
  _check(response, site);
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  if (json['disabled'] == true || json['closed'] == true) {
    throw GameSourceException('The ${site.label} account "$name" is closed.');
  }
  return switch (site) {
    ChessSite.lichess => json['username'] as String? ?? name,
    ChessSite.chessCom => json['username'] as String? ?? name.toLowerCase(),
  };
}

/// Up to [want] games of [username] on [site] that lie outside [coverage]
/// and aren't in [analyzed]: newer games first, then older ones.
///
/// Never throws for network trouble: whatever arrived is returned with a
/// [GameBatch.warning].
Future<GameBatch> fetchUnanalyzed(
  ChessSite site,
  String username, {
  required Coverage? coverage,
  required Set<String> analyzed,
  int want = 100,
  StatusCallback? onStatus,
  http.Client? client,
}) {
  return switch (site) {
    ChessSite.lichess => _lichessBatch(username, coverage, analyzed, want, onStatus, client),
    ChessSite.chessCom => _chessComBatch(username, coverage, analyzed, want, onStatus, client),
  };
}

// ---------------------------------------------------------------- Lichess --

Future<GameBatch> _lichessBatch(
  String username,
  Coverage? coverage,
  Set<String> analyzed,
  int want,
  StatusCallback? onStatus,
  http.Client? client,
) async {
  final newer = <FetchedGame>[];
  final older = <FetchedGame>[];
  var reachedFirst = coverage?.reachedFirstGame ?? false;
  try {
    if (coverage != null) {
      await _lichessStream(
        username,
        {'since': '${coverage.newest.millisecondsSinceEpoch + 1}', 'sort': 'dateAsc'},
        want,
        (g) => analyzed.contains(g.id) ? null : newer.add(g),
        onStatus,
        client,
      );
    }
    final remaining = want - newer.length;
    if (remaining > 0 && !reachedFirst) {
      final received = await _lichessStream(
        username,
        {
          if (coverage != null) 'until': '${coverage.oldest.millisecondsSinceEpoch - 1}',
          'sort': 'dateDesc',
        },
        remaining,
        (g) => analyzed.contains(g.id) ? null : older.add(g),
        onStatus,
        client,
      );
      reachedFirst = received < remaining;
    }
  } on GameSourceException catch (e) {
    return GameBatch(newer: newer, older: older, warning: e.message);
  }
  return GameBatch(newer: newer, older: older, reachedFirstGame: reachedFirst);
}

/// Streams up to [max] games from the Lichess export, handing each standard
/// game to [onGame] as it arrives. Returns how many games Lichess sent
/// (including skipped variants), so callers can tell when history ran out.
Future<int> _lichessStream(
  String username,
  Map<String, String> params,
  int max,
  void Function(FetchedGame) onGame,
  StatusCallback? onStatus,
  http.Client? client,
) async {
  final uri = Uri.https('lichess.org', '/api/games/user/$username', {
    ...params,
    'max': '$max',
    'moves': 'true',
    'clocks': 'true',
    'evals': 'false',
    'opening': 'false',
    'finished': 'true',
  });
  final me = username.toLowerCase();
  final owned = client == null;
  final http_ = client ?? http.Client();
  try {
    for (var attempt = 0;; attempt++) {
      final request = http.Request('GET', uri)
        ..headers.addAll({..._headers, 'Accept': 'application/x-ndjson'});
      final http.StreamedResponse response;
      try {
        response = await http_.send(request).timeout(_timeout);
      } on TimeoutException {
        throw const GameSourceException('Lichess didn\'t answer. Check your connection.');
      } on http.ClientException {
        throw const GameSourceException('Couldn\'t reach Lichess. Check your connection.');
      }

      if (response.statusCode == 429) {
        await response.stream.drain<void>();
        if (attempt >= _rateLimitRetries) {
          throw const GameSourceException(
            'Lichess is still limiting downloads. Your other games were analyzed; '
            'load again later to get the rest.',
          );
        }
        for (var s = _rateLimitWait.inSeconds; s > 0; s -= 5) {
          onStatus?.call('Lichess asked us to slow down. Retrying in ${s}s…');
          await Future<void>.delayed(const Duration(seconds: 5));
        }
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw GameSourceException('Lichess returned an error (${response.statusCode}).');
      }

      var received = 0;
      try {
        await for (final line in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .timeout(const Duration(seconds: 30))) {
          if (line.trim().isEmpty) continue;
          received++;
          onStatus?.call('Downloading games… $received');
          final game = _parseLichessGame(jsonDecode(line) as Map<String, dynamic>, me, username);
          if (game != null) onGame(game);
        }
      } on TimeoutException {
        throw const GameSourceException('The Lichess download stalled. Kept what arrived.');
      } on http.ClientException {
        throw const GameSourceException('The Lichess download was interrupted. Kept what arrived.');
      }
      return received;
    }
  } finally {
    if (owned) http_.close();
  }
}

FetchedGame? _parseLichessGame(Map<String, dynamic> json, String me, String username) {
  if (json['variant'] != 'standard' || json['initialFen'] != null) return null;
  final moves = (json['moves'] as String? ?? '').split(' ').where((m) => m.isNotEmpty).toList();
  if (moves.length < 10) return null;
  final players = json['players'] as Map<String, dynamic>;
  Map<String, dynamic> player(String color) => players[color] as Map<String, dynamic>? ?? const {};
  String? idOf(String color) => (player(color)['user'] as Map<String, dynamic>?)?['id'] as String?;

  final Side side;
  if (idOf('white') == me) {
    side = Side.white;
  } else if (idOf('black') == me) {
    side = Side.black;
  } else {
    return null;
  }
  final opponent = player(side == Side.white ? 'black' : 'white');
  final user = opponent['user'] as Map<String, dynamic>?;
  final ai = opponent['aiLevel'];
  final id = json['id'] as String;
  final clocks = (json['clocks'] as List<dynamic>?)?.whereType<int>().toList();
  final clock = json['clock'] as Map<String, dynamic>?;
  return FetchedGame(
    id: 'lichess:$id',
    site: ChessSite.lichess,
    account: username,
    url: 'https://lichess.org/$id${side == Side.black ? '/black' : ''}',
    userSide: side,
    opponent: user?['name'] as String? ?? (ai != null ? 'Stockfish level $ai' : 'Anonymous'),
    opponentRating: opponent['rating'] as int?,
    speed: GameSpeed.parse(json['speed'] as String?),
    // Lichess's since/until filter on the creation time.
    playedAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    sanMoves: moves,
    clocks: clocks == null || clocks.isEmpty ? null : clocks,
    increment: clock?['increment'] as int? ?? 0,
  );
}

// -------------------------------------------------------------- Chess.com --

Future<GameBatch> _chessComBatch(
  String username,
  Coverage? coverage,
  Set<String> analyzed,
  int want,
  StatusCallback? onStatus,
  http.Client? client,
) async {
  final me = username.toLowerCase();
  final newer = <FetchedGame>[];
  final older = <FetchedGame>[];
  var reachedFirst = coverage?.reachedFirstGame ?? false;
  try {
    onStatus?.call('Downloading games…');
    final response = await _get(
      Uri.https('api.chess.com', '/pub/player/$me/games/archives'),
      client: client,
    );
    _check(response, ChessSite.chessCom);
    // Monthly archive URLs ending in /YYYY/MM, oldest first.
    final archives = ((jsonDecode(response.body) as Map<String, dynamic>)['archives']
            as List<dynamic>)
        .cast<String>();
    int monthOf(String url) {
      final parts = url.split('/');
      return int.parse(parts[parts.length - 2]) * 12 + int.parse(parts.last) - 1;
    }

    int monthOfDate(DateTime d) => d.toUtc().year * 12 + d.toUtc().month - 1;

    Future<List<FetchedGame>> month(String url) async {
      final r = await _get(Uri.parse(url), client: client);
      _check(r, ChessSite.chessCom);
      final games = ((jsonDecode(r.body) as Map<String, dynamic>)['games'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return [
        for (final json in games)
          // Skip analyzed games before the costly PGN parse: the month of
          // the newest game is downloaded again on every load.
          if (!analyzed.contains(_chessComId(json))) ?_parseChessComGame(json, me),
      ]..sort((a, b) => a.playedAt.compareTo(b.playedAt));
    }

    if (coverage != null) {
      final from = monthOfDate(coverage.newest);
      for (final url in archives.where((u) => monthOf(u) >= from)) {
        if (newer.length >= want) break;
        onStatus?.call('Downloading games… ${newer.length}');
        for (final game in await month(url)) {
          if (game.playedAt.isAfter(coverage.newest) && newer.length < want) newer.add(game);
        }
      }
    }
    if (newer.length < want && !reachedFirst) {
      final before = coverage == null ? null : monthOfDate(coverage.oldest);
      final months = archives.reversed.where((u) => before == null || monthOf(u) <= before).toList();
      var i = 0;
      for (; i < months.length && newer.length + older.length < want; i++) {
        onStatus?.call('Downloading games… ${newer.length + older.length}');
        for (final game in (await month(months[i])).reversed) {
          final isOlder = coverage == null || game.playedAt.isBefore(coverage.oldest);
          if (isOlder && newer.length + older.length < want) older.add(game);
        }
      }
      reachedFirst = i == months.length && newer.length + older.length < want;
    }
  } on GameSourceException catch (e) {
    return GameBatch(newer: newer, older: older, warning: e.message);
  }
  return GameBatch(newer: newer, older: older, reachedFirstGame: reachedFirst);
}

/// The id [_parseChessComGame] gives the game in [json].
String _chessComId(Map<String, dynamic> json) => 'chesscom:${json['uuid'] ?? json['url']}';

FetchedGame? _parseChessComGame(Map<String, dynamic> json, String me) {
  if (json['rules'] != 'chess') return null;
  final pgn = json['pgn'] as String?;
  if (pgn == null) return null;
  final white = json['white'] as Map<String, dynamic>;
  final black = json['black'] as Map<String, dynamic>;
  final Side side;
  if ((white['username'] as String).toLowerCase() == me) {
    side = Side.white;
  } else if ((black['username'] as String).toLowerCase() == me) {
    side = Side.black;
  } else {
    return null;
  }
  final parsed = PgnGame.parsePgn(pgn);
  if (parsed.headers['SetUp'] == '1' || parsed.headers.containsKey('FEN')) return null;
  final nodes = parsed.moves.mainline().toList();
  final moves = [for (final node in nodes) node.san];
  if (moves.length < 10) return null;
  // "180+2": 3 minutes plus 2 seconds a move. Daily games ("1/259200")
  // have days per move: their clock says nothing about thinking time.
  final timeControl = json['time_control'] as String? ?? '';
  final daily = timeControl.contains('/');
  final increment = daily ? 0 : int.tryParse(timeControl.split('+').skip(1).firstOrNull ?? '') ?? 0;
  List<int>? clocks;
  if (!daily) {
    clocks = [];
    for (final node in nodes) {
      final clock = node.comments?.map(PgnComment.fromPgn).map((c) => c.clock).nonNulls.firstOrNull;
      if (clock == null) break;
      clocks.add(clock.inMilliseconds ~/ 10);
    }
    if (clocks.isEmpty) clocks = null;
  }
  final url = json['url'] as String;
  final opponent = side == Side.white ? black : white;
  return FetchedGame(
    id: _chessComId(json),
    site: ChessSite.chessCom,
    account: me,
    url: url,
    userSide: side,
    opponent: opponent['username'] as String,
    opponentRating: opponent['rating'] as int?,
    speed: GameSpeed.parse(json['time_class'] as String?),
    playedAt: DateTime.fromMillisecondsSinceEpoch((json['end_time'] as int) * 1000),
    sanMoves: moves,
    clocks: clocks,
    increment: increment,
  );
}

// ---------------------------------------------------------------- Helpers --

Future<http.Response> _get(Uri uri, {http.Client? client}) async {
  final headers = {..._headers, 'Accept': 'application/json'};
  try {
    final future = client == null ? http.get(uri, headers: headers) : client.get(uri, headers: headers);
    return await future.timeout(_timeout);
  } on TimeoutException {
    throw const GameSourceException('The request timed out. Check your connection.');
  } on http.ClientException {
    throw const GameSourceException('Couldn\'t reach the server. Check your connection.');
  }
}

void _check(http.Response response, ChessSite site) {
  if (response.statusCode == 429) {
    throw GameSourceException('${site.label} is limiting requests. Try again in a minute.');
  }
  if (response.statusCode != 200) {
    throw GameSourceException('${site.label} returned an error (${response.statusCode}).');
  }
}
