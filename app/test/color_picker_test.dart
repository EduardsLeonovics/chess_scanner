import 'package:chess_scanner/src/settings/color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the wheel picks hue by angle and saturation by distance, keeping brightness', (tester) async {
    var picked = HSVColor.fromAHSV(1, 0, 0, 0.8);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(
            builder: (context, setState) => ColorWheel(
              hsv: picked,
              size: 200,
              onChanged: (hsv) => setState(() => picked = hsv),
            ),
          ),
        ),
      ),
    ));
    final center = tester.getCenter(find.byType(ColorWheel));

    // Straight down from the centre, at the rim: hue 90, fully saturated.
    await tester.tapAt(center + const Offset(0, 99));
    expect(picked.hue, closeTo(90, 1));
    expect(picked.saturation, closeTo(1, 0.02));
    expect(picked.value, 0.8);

    // Halfway to the left: hue 180, half saturated.
    await tester.tapAt(center + const Offset(-50, 0));
    expect(picked.hue, closeTo(180, 1));
    expect(picked.saturation, closeTo(0.5, 0.02));
  });
}
