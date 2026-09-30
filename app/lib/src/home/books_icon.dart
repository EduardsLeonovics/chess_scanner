import 'package:flutter/widgets.dart';

/// Three books stacked on top of each other, drawn in the same outlined
/// style as Material's `*_outlined` icons (there is no such Material icon).
class BooksIcon extends StatelessWidget {
  const BooksIcon({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BooksPainter(color)),
    );
  }
}

class _BooksPainter extends CustomPainter {
  const _BooksPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 24x24 grid like Material icons.
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    // (left, top, right) of each book, top to bottom; the middle one is
    // shifted so the stack looks casually piled.
    const books = [(4.0, 4.0, 18.5), (6.0, 9.75, 20.5), (3.0, 15.5, 21.0)];
    const height = 4.5;
    for (final (left, top, right) in books) {
      canvas.drawRRect(
        RRect.fromLTRBR(left, top, right, top + height, const Radius.circular(1)),
        paint,
      );
      // Spine band near the right end.
      canvas.drawLine(Offset(right - 3, top), Offset(right - 3, top + height), paint);
    }
  }

  @override
  bool shouldRepaint(_BooksPainter oldDelegate) => oldDelegate.color != color;
}
