import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Piece;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appearance.dart';

/// Opens a slider for the piece outline width, with a white and a black
/// knight showing the result as it changes. Saves as the slider moves.
Future<void> showOutlineWidthPicker(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _OutlineWidthDialog());
}

class _OutlineWidthDialog extends ConsumerWidget {
  const _OutlineWidthDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final notifier = ref.read(appearanceProvider.notifier);
    final assets = ref.watch(pieceAssetsProvider).value;
    final scheme = appearance.colorScheme;

    Widget knight(Piece piece, Color square) => Container(
          width: 112,
          height: 112,
          color: square,
          alignment: Alignment.center,
          child: assets == null
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : PieceWidget(piece: piece, size: 104, pieceAssets: assets),
        );

    return AlertDialog(
      title: const Text('Outline width'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                knight(Piece.whiteKnight, scheme.lightSquare),
                knight(Piece.blackKnight, scheme.darkSquare),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(appearance.outlineWidth == 0 ? 'None' : '${appearance.outlineWidth}'),
          Slider(
            value: appearance.outlineWidth.toDouble(),
            max: Appearance.maxOutlineWidth.toDouble(),
            divisions: Appearance.maxOutlineWidth,
            label: '${appearance.outlineWidth}',
            onChanged: (v) => notifier.setOutlineWidth(v.round()),
          ),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
