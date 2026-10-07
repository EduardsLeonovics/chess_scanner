import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/appearance.dart';

enum ChessSite {
  lichess('Lichess'),
  chessCom('Chess.com');

  const ChessSite(this.label);

  final String label;
}

/// The usernames of the user's own accounts. Only public game data is read,
/// so a username is all that's needed. Persisted across launches.
@immutable
class Accounts {
  const Accounts({this.lichess, this.chessCom});

  final String? lichess;
  final String? chessCom;

  bool get any => lichess != null || chessCom != null;

  Map<String, dynamic> toJson() => {
        for (final site in ChessSite.values) site.name: ?of(site),
      };

  factory Accounts.fromJson(Map<String, dynamic> json) => Accounts(
        lichess: json[ChessSite.lichess.name] as String?,
        chessCom: json[ChessSite.chessCom.name] as String?,
      );

  String? of(ChessSite site) => switch (site) {
        ChessSite.lichess => lichess,
        ChessSite.chessCom => chessCom,
      };

  @override
  bool operator ==(Object other) =>
      other is Accounts && other.lichess == lichess && other.chessCom == chessCom;

  @override
  int get hashCode => Object.hash(lichess, chessCom);
}

final accountsProvider = NotifierProvider<AccountsNotifier, Accounts>(AccountsNotifier.new);

class AccountsNotifier extends Notifier<Accounts> {
  static String _key(ChessSite site) => 'accounts.${site.name}';

  @override
  Accounts build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return Accounts(
      lichess: prefs.getString(_key(ChessSite.lichess)),
      chessCom: prefs.getString(_key(ChessSite.chessCom)),
    );
  }

  /// Saves [username] (as verified with the site) or removes the account when null.
  Future<void> set(ChessSite site, String? username) => replace(switch (site) {
        ChessSite.lichess => Accounts(lichess: username, chessCom: state.chessCom),
        ChessSite.chessCom => Accounts(lichess: state.lichess, chessCom: username),
      });

  /// Saves both accounts at once.
  Future<void> replace(Accounts accounts) async {
    state = accounts;
    final prefs = ref.read(sharedPreferencesProvider);
    for (final site in ChessSite.values) {
      final username = accounts.of(site);
      if (username == null) {
        await prefs.remove(_key(site));
      } else {
        await prefs.setString(_key(site), username);
      }
    }
  }
}
