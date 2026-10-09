import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lets the user pick any colour from a colour wheel (hue around it,
/// saturation from the centre out), with saturation and brightness
/// sliders. Returns null if cancelled.
Future<Color?> showColorPicker(
  BuildContext context, {
  required String title,
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(title: title, initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 44,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x22000000)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ColorWheel(
                hsv: _hsv,
                onChanged: (hsv) => setState(() => _hsv = hsv),
              ),
            ),
            const SizedBox(height: 12),
            _labeledSlider(
              'Saturation',
              _hsv.saturation,
              (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _labeledSlider(
              'Brightness',
              _hsv.value,
              (v) => setState(() => _hsv = _hsv.withValue(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Done')),
      ],
    );
  }

  Widget _labeledSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
        ),
      ],
    );
  }
}

/// A colour wheel: the angle picks the hue, the distance from the centre
/// the saturation (white in the middle). Tap or drag to choose; brightness
/// is kept and shown by darkening the wheel.
class ColorWheel extends StatelessWidget {
  const ColorWheel({super.key, required this.hsv, required this.onChanged, this.size = 220});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double size;

  void _pick(Offset local) {
    final center = Offset(size / 2, size / 2);
    final d = local - center;
    final radius = size / 2;
    final hue = (math.atan2(d.dy, d.dx) * 180 / math.pi + 360) % 360;
    final saturation = (d.distance / radius).clamp(0.0, 1.0);
    onChanged(hsv.withHue(hue).withSaturation(saturation));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Colour wheel',
      child: GestureDetector(
        onPanDown: (e) => _pick(e.localPosition),
        onPanUpdate: (e) => _pick(e.localPosition),
        child: CustomPaint(size: Size.square(size), painter: _WheelPainter(hsv)),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Hues around the circle, fading to white towards the centre.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(colors: [
          for (var h = 0; h <= 360; h += 60) HSVColor.fromAHSV(1, h % 360 * 1.0, 1, 1).toColor(),
        ]).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)]).createShader(rect),
    );
    // The current brightness darkens the whole wheel.
    canvas.drawCircle(center, radius, Paint()..color = Color.fromRGBO(0, 0, 0, 1 - hsv.value));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0x22000000),
    );

    // Where the current colour sits.
    final angle = hsv.hue * math.pi / 180;
    final at = center + Offset(math.cos(angle), math.sin(angle)) * hsv.saturation * radius;
    canvas.drawCircle(at, 11, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      at,
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white,
    );
    canvas.drawCircle(
      at,
      12.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x66000000),
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}
