import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/uci.dart';

/// Vertical White/Black bar like chess.com's, White at the bottom unless
/// [flipped]. The score is written at the end of the side that's better.
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.line,
    required this.height,
    this.width = 26,
    this.flipped = false,
  });

  final PvLine? line;
  final double height;
  final double width;
  final bool flipped;

  static const _white = Color(0xFFF0F0F0);
  static const _black = Color(0xFF404040);

  @override
  Widget build(BuildContext context) {
    // Layout can briefly offer no room at all; never pass a negative size on.
    final height = math.max(0.0, this.height);
    final line = this.line;
    final whiteBetter = line == null || (line.mate ?? line.cp!) >= 0;
    // White's end is at the bottom unless flipped.
    final labelAtBottom = whiteBetter != flipped;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: line?.whiteShare ?? 0.5),
            duration: const Duration(milliseconds: 300),
            builder: (context, share, _) {
              final white = Container(height: height * share, color: _white);
              final black = Container(height: height * (1 - share), color: _black);
              return Column(children: flipped ? [white, black] : [black, white]);
            },
          ),
          if (line != null && height > 40)
            Positioned(
              left: 1,
              right: 1,
              top: labelAtBottom ? null : 3,
              bottom: labelAtBottom ? 3 : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  evalBarLabel(line),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: whiteBetter ? _black : _white,
                  ),
                ),
              ),
            ),
        ],
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
