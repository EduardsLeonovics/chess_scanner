import 'package:flutter/material.dart';

import '../engine/uci.dart';

/// Horizontal White/Black bar, White on the left unless [flipped] (Black
/// at the bottom of the board). The score is written at the end of the
/// side that's better.
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.line,
    this.height = 18,
    this.flipped = false,
  });

  final PvLine? line;
  final double height;
  final bool flipped;

  static const _white = Color(0xFFF0F0F0);
  static const _black = Color(0xFF404040);

  @override
  Widget build(BuildContext context) {
    final line = this.line;
    final whiteBetter = line == null || (line.mate ?? line.cp!) >= 0;
    // White's end is on the left unless flipped.
    final labelOnLeft = whiteBetter != flipped;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(end: line?.whiteShare ?? 0.5),
              duration: const Duration(milliseconds: 300),
              builder: (context, share, _) {
                // Flex can't be 0: a mate leaves a sliver of the loser's colour.
                final whiteFlex = (share * 1000).round().clamp(1, 999);
                final white = Expanded(flex: whiteFlex, child: const ColoredBox(color: _white));
                final black = Expanded(flex: 1000 - whiteFlex, child: const ColoredBox(color: _black));
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: flipped ? [black, white] : [white, black],
                );
              },
            ),
            if (line != null)
              Align(
                alignment: labelOnLeft ? Alignment.centerLeft : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    evalBarLabel(line),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: whiteBetter ? _black : _white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The bar's short score: `0.0`, `+5.0`, `-1.3`, `M3`, `-M2`.
String evalBarLabel(PvLine line) {
  final mate = line.mate;
  if (mate != null) return mate < 0 ? '-M${-mate}' : 'M$mate';
  final pawns = line.cp! / 100;
  final text = pawns.abs().toStringAsFixed(1);
  if (text == '0.0') return text;
  return '${pawns > 0 ? '+' : '-'}$text';
}
