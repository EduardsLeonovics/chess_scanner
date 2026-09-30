import 'package:flutter/material.dart';

const _swatches = [
  Color(0xFFFFFFFF), Color(0xFFF0D9B6), Color(0xFFEEEED2), Color(0xFFDEE3E6),
  Color(0xFFE8E0C8), Color(0xFFFFE0B2), Color(0xFFB58863), Color(0xFF769656),
  Color(0xFF8CA2AD), Color(0xFF4B7399), Color(0xFF7D4A8D), Color(0xFFB33430),
  Color(0xFFD4A017), Color(0xFF3C3C3C), Color(0xFF1E2A38), Color(0xFF000000),
];

/// Lets the user pick any colour: quick swatches, or hue, saturation and
/// brightness sliders. Returns null if cancelled.
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
              height: 56,
              decoration: BoxDecoration(
                color: _color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x22000000)),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final swatch in _swatches)
                  _Swatch(
                    color: swatch,
                    selected: swatch.toARGB32() == _color.toARGB32(),
                    onTap: () => setState(() => _hsv = HSVColor.fromColor(swatch)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _labeledSlider(
              'Hue',
              _hsv.hue,
              360,
              (v) => setState(() => _hsv = _hsv.withHue(v)),
            ),
            _labeledSlider(
              'Saturation',
              _hsv.saturation,
              1,
              (v) => setState(() => _hsv = _hsv.withSaturation(v)),
            ),
            _labeledSlider(
              'Brightness',
              _hsv.value,
              1,
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

  Widget _labeledSlider(String label, double value, double max, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Slider(value: value.clamp(0, max), max: max, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : const Color(0x33000000),
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}
