import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../engine/uci.dart';

/// Vertical White/Black bar like chess.com's, White at the bottom unless
/// [flipped].
class EvalBar extends StatelessWidget {
  const EvalBar({
    super.key,
    required this.line,
    required this.height,
    this.width = 18,
    this.flipped = false,
  });

  final PvLine? line;
  final double height;
  final double width;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    // Layout can briefly offer no room at all; never pass a negative size on.
    final height = math.max(0.0, this.height);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: line?.whiteShare ?? 0.5),
      duration: const Duration(milliseconds: 300),
      builder: (context, share, _) {
        final white = Container(
          height: height * share,
          color: const Color(0xFFF0F0F0),
        );
        final black = Container(
          height: height * (1 - share),
          color: const Color(0xFF404040),
        );
        return SizedBox(
          width: width,
          height: height,
          child: Column(children: flipped ? [white, black] : [black, white]),
        );
      },
    );
  }
}
