import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/board_setup.dart';

/// Shared positions are links to a small web page. With ChessHive
/// installed, Android opens them in the app (App Links); otherwise the page
/// shows the position and sends the visitor to the Play Store. The page
/// itself also opens the app through the [appScheme] link.
abstract final class PositionLinks {
  static const host = 'eduardsleonovics.github.io';
  static const path = '/chesshive/p/';

  /// `chesshive://position?fen=…`, used by the web page's "Open in app".
  static const appScheme = 'chesshive';
}

/// The link that opens [fen] in ChessHive.
Uri positionLink(String fen) => Uri.https(PositionLinks.host, PositionLinks.path, {'fen': fen});

/// The position in a link made by [positionLink] (or its app-scheme form),
/// or null if [uri] isn't one or holds no legal position.
Position? positionFromLink(Uri uri) {
  final ours = (uri.scheme == 'https' && uri.host == PositionLinks.host && uri.path.startsWith(PositionLinks.path)) ||
      (uri.scheme == PositionLinks.appScheme && uri.host == 'position');
  final fen = uri.queryParameters['fen'];
  if (!ours || fen == null) return null;
  try {
    // Any material may be shared; the analysis board won't hand Stockfish
    // a position it can't take (see materialProblem).
    return checkNotCheckmate(Chess.fromSetup(Setup.parseFen(fen.trim())));
  } on FenException {
    return null;
  } on PositionSetupException {
    return null;
  }
}

/// A position opened from a link, waiting for the analysis board to take it.
final pendingPositionProvider = NotifierProvider<PendingPosition, Position?>(PendingPosition.new);

class PendingPosition extends Notifier<Position?> {
  @override
  Position? build() => null;

  void open(Position position) => state = position;

  void clear() => state = null;
}

/// Listens for incoming links for the app's lifetime, including the one it
/// was launched with. [onLink] gets each position link; [onInvalid] any
/// link of ours that holds no usable position.
StreamSubscription<Uri>? listenForPositionLinks({
  required void Function(Position position) onLink,
  required VoidCallback onInvalid,
}) {
  if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    return null;
  }
  try {
    return AppLinks().uriLinkStream.listen((uri) {
      final position = positionFromLink(uri);
      if (position != null) {
        onLink(position);
      } else if (uri.queryParameters.containsKey('fen')) {
        onInvalid();
      }
    }, onError: (Object e) => debugPrint('Link error: $e'));
  } catch (e) {
    debugPrint('Links unavailable: $e');
    return null;
  }
}
