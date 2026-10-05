import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../diagnostics/crash_log.dart' show shareOrigin;
import 'position_link.dart';

/// Opens the system share sheet with a link to [fen] (see [positionLink]).
/// [buttonContext] anchors the sheet on tablets.
Future<void> sharePositionLink(String fen, BuildContext buttonContext) async {
  final link = positionLink(fen);
  await SharePlus.instance.share(ShareParams(
    subject: 'Chess position',
    text: 'Analyze this position in ChessGeek: $link',
    sharePositionOrigin: shareOrigin(buttonContext),
  ));
}
