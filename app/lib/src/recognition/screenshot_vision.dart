import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartchess/dartchess.dart';
import 'package:image/image.dart' as img;

import 'perspective.dart';

/// Side length of the normalized piece silhouettes that get compared.
const _maskSize = 32;

/// Longest image side we work at; bigger screenshots are downscaled first.
const _maxSide = 1200;

/// How much of an edge square may be cropped off the image, as a share of
/// the square.
const _maxCrop = 0.3;

class RecognitionException implements Exception {
  const RecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A reference silhouette of one piece, built from a piece-set image.
class PieceTemplate {
  const PieceTemplate(this.role, this.mask, this.relHeight);

  final Role role;

  /// [_maskSize]² cells, 1 where the piece is.
  final Uint8List mask;

  /// Height of the piece relative to its square.
  final double relHeight;
}

class RecognizedBoard {
  const RecognizedBoard({required this.board, required this.blackAtBottom});

  final Board board;

  /// Whether the image showed the board from Black's side.
  final bool blackAtBottom;
}

/// Builds a template from a transparent piece image (e.g. a chessground
/// piece-set asset), or returns null if the image can't be decoded.
PieceTemplate? templateFromPieceImage(Uint8List bytes, Role role) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final image = decoded.convert(format: img.Format.uint8, numChannels: 4);
  final rgba = image.getBytes(order: img.ChannelOrder.rgba);
  final w = image.width, h = image.height;
  final mask = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (rgba[i * 4 + 3] > 127) mask[i] = 1;
  }
  final blob = _Blob.largest(mask, w, h);
  if (blob == null) return null;
  return PieceTemplate(role, blob.normalized(), blob.height / h);
}

/// Finds a 2D chessboard in a screenshot, or a flat board photographed at
/// an angle (see [rectifyBoard]), and reads the pieces on it.
///
/// Strongly coloured pixels are normally taken for arrows and highlights
/// drawn over the board; [pieceHues] (degrees) are hues that belong to
/// pieces instead, e.g. this app's golden pieces in its own screenshots.
///
/// Throws [RecognitionException] if no board is found.
RecognizedBoard recognizeScreenshot(
  Uint8List imageBytes,
  List<PieceTemplate> templates, {
  List<double> pieceHues = const [],
}) {
  var image = img.decodeImage(imageBytes);
  if (image == null) {
    throw const RecognitionException("Couldn't read that image.");
  }
  // bakeOrientation copies the whole image even when there's nothing to turn.
  final orientation = image.exif.imageIfd;
  if (orientation.hasOrientation && orientation.orientation != 1) {
    image = img.bakeOrientation(image);
  }
  final longest = math.max(image.width, image.height);
  if (longest > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide)
        : img.copyResize(image, height: _maxSide);
  }
  var pixels = _Pixels.fromImage(image);
  var grid = _findGrid(pixels);
  if (grid == null) {
    // Not a straight-on screenshot: maybe a photo of a board at an angle.
    final straightened = rectifyBoard(image);
    if (straightened != null) {
      pixels = _Pixels.fromImage(straightened.image, inside: straightened.inside);
      grid = _findGrid(pixels);
    }
  }
  if (grid == null) {
    throw const RecognitionException("Couldn't find a chessboard in that image.");
  }

  final squares = <_SquareReading>[];
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      final reading = _readSquare(pixels, grid, c, r, templates, pieceHues);
      if (reading != null) squares.add(reading);
    }
  }
  _dropSmallMarks(squares);
  return _assemble(squares, _labelledBlackAtBottom(pixels, grid, squares));
}

/// Whether the colour's hue is within 25 degrees of one of [hues].
bool _isPieceHue(int r, int g, int b, List<double> hues) {
  if (hues.isEmpty) return false;
  final hue = rgbHue(r, g, b);
  for (final h in hues) {
    final d = (hue - h).abs() % 360;
    if (math.min(d, 360 - d) <= 25) return true;
  }
  return false;
}

/// The hue of a colour in degrees (0 red, 120 green, 240 blue).
double rgbHue(int r, int g, int b) {
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  if (mx == mn) return 0;
  final d = (mx - mn).toDouble();
  final double h;
  if (mx == r) {
    h = ((g - b) / d) % 6;
  } else if (mx == g) {
    h = (b - r) / d + 2;
  } else {
    h = (r - g) / d + 4;
  }
  return (h * 60 + 360) % 360;
}

/// Removes marks much smaller than the pieces around them: in every piece
/// set even a pawn is well over half as tall as a typical piece, so these
/// are icons drawn over the board (e.g. an image search's lens button).
void _dropSmallMarks(List<_SquareReading> readings) {
  if (readings.length < 3) return;
  final heights = [for (final s in readings) s.relHeight]..sort();
  final median = heights[heights.length ~/ 2];
  readings.removeWhere((s) => s.relHeight < median * 0.55);
}

/// Which way up the board is, from rank numbers drawn in the corners of the
/// edge squares (most sites do this), or null if there are none or they
/// can't be read. Only the ends of a label column are read: "8" (wide, two
/// holes) and "1" (narrow, no holes) are easy to tell apart, and both must
/// be recognised, the right way round, for the labels to decide.
bool? _labelledBlackAtBottom(_Pixels p, _Grid g, List<_SquareReading> pieces) {
  final occupied = {for (final s in pieces) (s.col, s.row)};
  final verdicts = <bool>{};
  for (final col in const [0, 7]) {
    if (occupied.contains((col, 0)) || occupied.contains((col, 7))) continue;
    for (final (right, bottom) in const [(false, false), (true, false), (false, true), (true, true)]) {
      final top = _cornerDigit(p, g, col, 0, right: right, bottom: bottom);
      final low = _cornerDigit(p, g, col, 7, right: right, bottom: bottom);
      if (top == 8 && low == 1) verdicts.add(false);
      if (top == 1 && low == 8) verdicts.add(true);
    }
  }
  return verdicts.length == 1 ? verdicts.first : null;
}

/// 8 or 1 if a corner of square ([c], [r]) holds a mark shaped like that
/// digit, else null.
int? _cornerDigit(_Pixels p, _Grid g, int c, int r, {required bool right, required bool bottom}) {
  final zoneW = (g.stepX * 0.3).round(), zoneH = (g.stepY * 0.3).round();
  final edgeX = math.max(1, (g.stepX * 0.02).round());
  final edgeY = math.max(1, (g.stepY * 0.02).round());
  final x0 = right
      ? (g.x0 + (c + 1) * g.stepX).round() - edgeX - zoneW
      : (g.x0 + c * g.stepX).round() + edgeX;
  final y0 = bottom
      ? (g.y0 + (r + 1) * g.stepY).round() - edgeY - zoneH
      : (g.y0 + r * g.stepY).round() + edgeY;
  if (x0 < 0 || y0 < 0 || x0 + zoneW > p.width || y0 + zoneH > p.height) return null;
  final bg = _background(p, g, c, r);
  final threshold = math.max(60, 2 * bg.noise);
  final ink = Uint8List(zoneW * zoneH);
  for (var y = 0; y < zoneH; y++) {
    for (var x = 0; x < zoneW; x++) {
      final i = ((y0 + y) * p.width + x0 + x) * 3;
      if (bg.distanceTo(p.rgb[i], p.rgb[i + 1], p.rgb[i + 2]) > threshold) ink[y * zoneW + x] = 1;
    }
  }
  final glyph = _largestComponent(ink, zoneW, zoneH);
  if (glyph == null) return null;
  final (cells, left, top, w, h) = glyph;
  // A label is a small mark clear of the zone's edges.
  if (h < zoneH * 0.25 || h > zoneH * 0.9 || h < 6 || w > h) return null;
  final holes = _holes(cells, w, h);
  final aspect = w / h;
  if (holes == 0 && aspect < 0.6) return 1;
  if (holes == 2 && aspect >= 0.45) return 8;
  return null;
}

/// The largest 8-connected component of [mask] as its own mask cropped to
/// its bounding box: (cells, left, top, width, height).
(Uint8List, int, int, int, int)? _largestComponent(Uint8List mask, int w, int h) {
  final labels = Int32List(w * h);
  var bestLabel = 0, bestSize = 0, label = 0;
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (mask[start] == 0 || labels[start] != 0) continue;
    label++;
    var size = 0;
    labels[start] = label;
    stack.add(start);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      size++;
      final x = i % w, y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final n = ny * w + nx;
          if (mask[n] == 1 && labels[n] == 0) {
            labels[n] = label;
            stack.add(n);
          }
        }
      }
    }
    if (size > bestSize) {
      bestSize = size;
      bestLabel = label;
    }
  }
  if (bestLabel == 0) return null;
  var left = w, top = h, right = -1, bottom = -1;
  for (var i = 0; i < w * h; i++) {
    if (labels[i] != bestLabel) continue;
    final x = i % w, y = i ~/ w;
    left = math.min(left, x);
    right = math.max(right, x);
    top = math.min(top, y);
    bottom = math.max(bottom, y);
  }
  final cw = right - left + 1, ch = bottom - top + 1;
  final cells = Uint8List(cw * ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      if (labels[(top + y) * w + left + x] == bestLabel) cells[y * cw + x] = 1;
    }
  }
  return (cells, left, top, cw, ch);
}

/// How many enclosed holes a shape has: background regions (4-connected)
/// that don't reach the edge of its bounding box.
int _holes(Uint8List cells, int w, int h) {
  final seen = Uint8List(w * h);
  var holes = 0;
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (cells[start] == 1 || seen[start] == 1) continue;
    var touchesEdge = false;
    seen[start] = 1;
    stack.add(start);
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w, y = i ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touchesEdge = true;
      for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final n = ny * w + nx;
        if (cells[n] == 0 && seen[n] == 0) {
          seen[n] = 1;
          stack.add(n);
        }
      }
    }
    if (!touchesEdge) holes++;
  }
  return holes;
}

// ---------------------------------------------------------------------------
// Pixels

class _Pixels {
  _Pixels(this.width, this.height, this.rgb, this.lum, this.inside);

  factory _Pixels.fromImage(img.Image image, {Uint8List? inside}) {
    final rgb = rgbBytes(image);
    final n = image.width * image.height;
    final lum = Uint8List(n);
    for (var i = 0; i < n; i++) {
      lum[i] = (rgb[i * 3] * 299 + rgb[i * 3 + 1] * 587 + rgb[i * 3 + 2] * 114) ~/ 1000;
    }
    return _Pixels(image.width, image.height, rgb, lum, inside);
  }

  final int width;
  final int height;
  final Uint8List rgb;
  final Uint8List lum;

  /// For a straightened photo, 1 per pixel the photo showed (see
  /// [RectifiedBoard.inside]); null when every pixel is real.
  final Uint8List? inside;

  bool seen(int index) => inside == null || inside![index] == 1;
}

// ---------------------------------------------------------------------------
// Board localization
//
// Square boundaries are long straight edges, so summing the gradient along
// each column (row) gives a profile with 7 strong, evenly spaced peaks at the
// inner board lines. We search for the (start, step) whose 7 lines are much
// stronger than the square centres between them.

class _Grid {
  const _Grid(this.x0, this.y0, this.stepX, this.stepY);

  final double x0;
  final double y0;

  /// Square width and height; equal unless the image was stretched.
  final double stepX;
  final double stepY;
}

class _Lines {
  const _Lines(this.start, this.step, this.score);

  final double start;
  final double step;
  final double score;
}

/// Gradient profile across x (vertical edges), using rows [y0, y1).
Float64List _columnProfile(_Pixels p, int y0, int y1) {
  final out = Float64List(p.width - 1);
  y0 = y0.clamp(0, p.height);
  y1 = y1.clamp(0, p.height);
  for (var y = y0; y < y1; y++) {
    final row = y * p.width;
    for (var x = 0; x < p.width - 1; x++) {
      out[x] += (p.lum[row + x + 1] - p.lum[row + x]).abs();
    }
  }
  return out;
}

/// Gradient profile across y (horizontal edges), using columns [x0, x1).
Float64List _rowProfile(_Pixels p, int x0, int x1) {
  final out = Float64List(p.height - 1);
  x0 = x0.clamp(0, p.width);
  x1 = x1.clamp(0, p.width);
  for (var y = 0; y < p.height - 1; y++) {
    final row = y * p.width;
    var sum = 0.0;
    for (var x = x0; x < x1; x++) {
      sum += (p.lum[row + p.width + x] - p.lum[row + x]).abs();
    }
    out[y] = sum;
  }
  return out;
}

_Lines? _findLines(Float64List profile, double minStep, double maxStep) {
  final candidates = _lineCandidates(profile, minStep, maxStep, 1);
  return candidates.isEmpty ? null : candidates.first;
}

/// The [count] best-scoring line patterns with clearly different spacings,
/// best first.
List<_Lines> _lineCandidates(
  Float64List profile,
  double minStep,
  double maxStep,
  int count,
) {
  final len = profile.length;
  double at(double pos) {
    final i = pos.round();
    return i < 0 || i >= len ? 0 : profile[i];
  }

  double peak(double pos) => math.max(at(pos - 1), math.max(at(pos), at(pos + 1)));

  final bestPerStep = <_Lines>[];
  minStep = math.max(minStep, 6);
  for (var step = minStep; step <= maxStep; step += 0.25) {
    _Lines? best;
    // Screenshots are often cropped tightly: allow part of the outer files
    // or ranks to be cut off.
    final crop = step * _maxCrop;
    final lastStart = len + 1 - 8 * step + crop;
    for (var start = -1.0 - crop; start <= lastStart; start += 1) {
      var score = 0.0;
      var weakest = double.infinity;
      var prevMid = at(start + 0.5 * step);
      for (var k = 1; k <= 7; k++) {
        final mid = at(start + (k + 0.5) * step);
        final contrast = peak(start + k * step) - (prevMid + mid) / 2;
        score += contrast;
        weakest = math.min(weakest, contrast);
        prevMid = mid;
      }
      // All seven inner lines should stand out, not just a few strong ones
      // (in blurry images a line can drown next to a piece's strokes).
      score += 3 * weakest;
      // The outer edges count too (they may be missing when the board
      // touches the image border), which pins the grid to the board.
      score += peak(start) + peak(start + 8 * step);
      if (best == null || score > best.score) best = _Lines(start, step, score);
    }
    if (best != null) bestPerStep.add(best);
  }
  bestPerStep.sort((a, b) => b.score.compareTo(a.score));
  final picked = <_Lines>[];
  for (final lines in bestPerStep) {
    if (picked.length == count) break;
    if (picked.every((other) => (other.step - lines.step).abs() > other.step * 0.08)) {
      picked.add(lines);
    }
  }
  return picked;
}

_Grid? _findGrid(_Pixels p) {
  final shortSide = math.min(p.width, p.height);
  final minStep = shortSide / 8 * 0.3;
  final maxStep = shortSide / (8 - 2 * _maxCrop);
  final portrait = p.width <= p.height;

  // Pieces with strong vertical strokes can make a fraction of the real
  // square size score best, so try the few best spacings and let the
  // checkerboard decide.
  _Grid? best;
  var bestScore = double.negativeInfinity;
  final firsts = _lineCandidates(
    portrait ? _columnProfile(p, 0, p.height) : _rowProfile(p, 0, p.width),
    minStep,
    maxStep,
    4,
  );
  for (final first in firsts) {
    final grid = portrait ? _gridFromColumns(p, first) : _gridFromRows(p, first);
    if (grid == null) continue;
    final (placed, score) = _bestPlacement(p, grid);
    if (placed != null && score > bestScore) {
      bestScore = score;
      best = placed;
    }
  }
  return best != null && _looksLikeCheckerboard(_squareLums(p, best)) ? best : null;
}

/// Completes a grid from its vertical lines ([xs]): phone screenshots have
/// the board spanning the width, so these are found first.
_Grid? _gridFromColumns(_Pixels p, _Lines xs) {
  final ys = _findLines(
    _rowProfile(p, xs.start.round(), (xs.start + 8 * xs.step).round()),
    xs.step * 0.9,
    xs.step * 1.1,
  );
  if (ys == null) return null;
  final refined = _findLines(
    _columnProfile(p, ys.start.round(), (ys.start + 8 * ys.step).round()),
    xs.step * 0.97,
    xs.step * 1.03,
  );
  if (refined == null) return null;
  return _Grid(refined.start + 1, ys.start + 1, refined.step, ys.step);
}

/// Completes a grid from its horizontal lines ([ys]), for landscape images.
_Grid? _gridFromRows(_Pixels p, _Lines ys) {
  final xs = _findLines(
    _columnProfile(p, ys.start.round(), (ys.start + 8 * ys.step).round()),
    ys.step * 0.9,
    ys.step * 1.1,
  );
  if (xs == null) return null;
  final refined = _findLines(
    _rowProfile(p, xs.start.round(), (xs.start + 8 * xs.step).round()),
    ys.step * 0.97,
    ys.step * 1.03,
  );
  if (refined == null) return null;
  return _Grid(xs.start + 1, refined.start + 1, xs.step, refined.step);
}

/// A grid shifted by a whole square still lines up with the edges; returns
/// the placement covering the cleanest light/dark checkerboard, and its score.
(_Grid?, double) _bestPlacement(_Pixels p, _Grid found) {
  _Grid? best;
  var bestScore = double.negativeInfinity;
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      final grid = _Grid(
        found.x0 + dx * found.stepX,
        found.y0 + dy * found.stepY,
        found.stepX,
        found.stepY,
      );
      if (grid.x0 < -2 - grid.stepX * _maxCrop ||
          grid.y0 < -2 - grid.stepY * _maxCrop ||
          grid.x0 + 8 * grid.stepX > p.width + 2 + grid.stepX * _maxCrop ||
          grid.y0 + 8 * grid.stepY > p.height + 2 + grid.stepY * _maxCrop) {
        continue;
      }
      final score = _checkerScore(_squareLums(p, grid));
      if (score > bestScore) {
        bestScore = score;
        best = grid;
      }
    }
  }
  return (best, bestScore);
}

/// Background luminance of each square, row by row from the top left.
List<double> _squareLums(_Pixels p, _Grid grid) =>
    List.generate(64, (i) => _background(p, grid, i % 8, i ~/ 8, withNoise: false).luminance);

(double, double) _parityMeans(List<double> lums) {
  final sums = [0.0, 0.0];
  for (var i = 0; i < 64; i++) {
    sums[(i % 8 + i ~/ 8) % 2] += lums[i];
  }
  return (sums[0] / 32, sums[1] / 32);
}

/// High when the squares alternate between two uniform shades.
double _checkerScore(List<double> lums) {
  final (even, odd) = _parityMeans(lums);
  var spread = 0.0;
  for (var i = 0; i < 64; i++) {
    spread += (lums[i] - ((i % 8 + i ~/ 8) % 2 == 0 ? even : odd)).abs();
  }
  return (even - odd).abs() - spread / 64;
}

bool _looksLikeCheckerboard(List<double> lums) {
  final (light, dark) = _parityMeans(lums);
  if ((light - dark).abs() < 12) return false;
  // Allow a few squares to be off (move highlights, check glow).
  var consistent = 0;
  for (var i = 0; i < 64; i++) {
    final own = (i % 8 + i ~/ 8) % 2 == 0 ? light : dark;
    final other = own == light ? dark : light;
    if ((lums[i] - own).abs() < (lums[i] - other).abs()) consistent++;
  }
  return consistent >= 56;
}

// ---------------------------------------------------------------------------
// Squares

/// A square's own colour and how much it varies (e.g. wood grain), taken
/// from its four corner patches: they show the square including any move
/// highlight, and are almost never covered by a piece.
class _Background {
  const _Background(this.color, this.noise);

  final List<int> color;

  /// How far pixels of the plain square stray from [color]: the 90th
  /// percentile distance in the quietest corner.
  final int noise;

  int distanceTo(int red, int green, int blue) =>
      (red - color[0]).abs() + (green - color[1]).abs() + (blue - color[2]).abs();

  double get luminance => (color[0] * 299 + color[1] * 587 + color[2] * 114) / 1000;
}

/// The plain colour of square ([c], [r]) from its four corner patches, and
/// with [withNoise] how textured it is.
///
/// Medians and percentiles come from histograms (values are small integers),
/// which pick the same element sorting would, without the sorting: this runs
/// thousands of times per scan.
_Background _background(_Pixels p, _Grid g, int c, int r, {bool withNoise = true}) {
  final patchX = math.max(2, (g.stepX * 0.1).round());
  final patchY = math.max(2, (g.stepY * 0.1).round());
  final insetX = math.max(1, (g.stepX * 0.04).round());
  final insetY = math.max(1, (g.stepY * 0.04).round());
  final left = (g.x0 + c * g.stepX).round() + insetX;
  final top = (g.y0 + r * g.stepY).round() + insetY;
  final right = (g.x0 + (c + 1) * g.stepX).round() - insetX - patchX;
  final bottom = (g.y0 + (r + 1) * g.stepY).round() - insetY - patchY;
  final corners = [(left, top), (right, top), (left, bottom), (right, bottom)];
  final rgb = p.rgb;

  // Calls [visit] with the rgb offset of each pixel of a corner patch that
  // lies inside the image.
  void eachPixel((int, int) corner, void Function(int i) visit) {
    final (px, py) = corner;
    final x0 = math.max(px, 0), x1 = math.min(px + patchX, p.width);
    final y0 = math.max(py, 0), y1 = math.min(py + patchY, p.height);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (p.seen(y * p.width + x)) visit((y * p.width + x) * 3);
      }
    }
  }

  final histogram = Int32List(3 * 256);
  var count = 0;
  for (final corner in corners) {
    eachPixel(corner, (i) {
      histogram[rgb[i]]++;
      histogram[256 + rgb[i + 1]]++;
      histogram[512 + rgb[i + 2]]++;
      count++;
    });
  }
  if (count == 0) return const _Background([0, 0, 0], 0);
  int median(int channel) => _kth(histogram, channel * 256, 256, count ~/ 2);

  final bg = _Background([median(0), median(1), median(2)], 0);
  if (!withNoise) return bg;
  // Texture shows in every corner, a piece only in some (rook bases fill
  // the bottom ones), so the quietest corner tells how textured it is.
  var noise = 1 << 30;
  final distances = Int32List(3 * 255 + 1);
  for (final corner in corners) {
    distances.fillRange(0, distances.length, 0);
    var n = 0;
    eachPixel(corner, (i) {
      distances[bg.distanceTo(rgb[i], rgb[i + 1], rgb[i + 2])]++;
      n++;
    });
    if (n == 0) continue;
    noise = math.min(noise, _kth(distances, 0, distances.length, (n * 0.9).floor()));
  }
  return _Background(bg.color, noise);
}

/// The [k]th smallest value (from 0) counted in [histogram]'s [size] bins
/// starting at [offset]: what sorting the values and taking index [k] gives.
int _kth(Int32List histogram, int offset, int size, int k) {
  var seen = 0;
  for (var v = 0; v < size; v++) {
    seen += histogram[offset + v];
    if (seen > k) return v;
  }
  return size - 1;
}

class _SquareReading {
  _SquareReading(this.col, this.row, this.brightness, this.ranked, this.shape, this.relHeight);

  /// Column and row in the image, (0, 0) = top left.
  final int col;
  final int row;

  /// The piece's fill brightness, -1 (black) to 1 (white), the median
  /// inside it, less its saturation (white is never strongly coloured).
  /// Used to tell White from Black relative to the other pieces in the
  /// same image.
  final double brightness;

  /// Candidate roles, best first.
  List<(Role, double)> ranked;

  /// The piece's normalized silhouette.
  final Uint8List shape;

  /// The piece's height relative to its square.
  final double relHeight;

  Side color = Side.white;
}

_SquareReading? _readSquare(
  _Pixels p,
  _Grid g,
  int c,
  int r,
  List<PieceTemplate> templates,
  List<double> pieceHues,
) {
  final insetX = math.max(1, (g.stepX * 0.04).round());
  final insetY = math.max(1, (g.stepY * 0.04).round());
  final left = math.max(0, (g.x0 + c * g.stepX).round() + insetX);
  final top = math.max(0, (g.y0 + r * g.stepY).round() + insetY);
  final right = math.min(p.width, (g.x0 + (c + 1) * g.stepX).round() - insetX);
  final bottom = math.min(p.height, (g.y0 + (r + 1) * g.stepY).round() - insetY);
  final w = right - left, h = bottom - top;
  if (w < 6 || h < 6) return null;
  if (p.inside != null) {
    var seen = 0;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        seen += p.inside![y * p.width + x];
      }
    }
    // Mostly out of the photo: what little shows can't be read as a piece.
    if (seen < w * h * 0.7) return null;
  }

  final bg = _background(p, g, c, r);
  // Textured squares (wood, marble) need a higher bar, or their grain
  // sticks to the pieces and changes their outline.
  final threshold = math.max(60, 2 * bg.noise);
  final mask = Uint8List(w * h);
  final core = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!p.seen((top + y) * p.width + left + x)) continue;
      final i = ((top + y) * p.width + left + x) * 3;
      final red = p.rgb[i], green = p.rgb[i + 1], blue = p.rgb[i + 2];
      final dist = bg.distanceTo(red, green, blue);
      // Pieces are drawn in near-neutral colours; strongly coloured pixels
      // are arrows or highlights drawn over the board, unless their hue is
      // a known piece colour.
      final saturation = math.max(red, math.max(green, blue)) -
          math.min(red, math.min(green, blue));
      final pieceHue = saturation > 45 && _isPieceHue(red, green, blue, pieceHues);
      if (dist > threshold && (saturation <= 45 || pieceHue)) {
        mask[y * w + x] = 1;
        final lum = p.lum[(top + y) * p.width + left + x];
        // "Ink": clearly black or white, or the known colour of the pieces.
        if (pieceHue || (saturation <= 40 && (lum <= 70 || lum >= 200))) core[y * w + x] = 1;
      }
    }
  }
  final blob = _pieceBlob(mask, core, w, h);
  // Coordinates, move dots and other small marks are not pieces.
  if (blob == null || blob.height < h * 0.35 || blob.area < w * h * 0.05) {
    return null;
  }

  // Judge brightness away from the outline, which is dark on white pieces
  // too; measured over all lichess sets this separates the colours best.
  final interior = blob.eroded(math.max(1, (w * 0.04).round()));
  // The median brightness inside the piece is its fill colour: drawn lines
  // and details (white ones on black pieces, black ones on white) are a
  // minority. Its median saturation tells white from coloured (golden)
  // pieces, which can be nearly as bright.
  final lums = Int32List(256), sats = Int32List(256);
  var counted = 0;
  for (var y = blob.top; y <= blob.bottom; y++) {
    for (var x = blob.left; x <= blob.right; x++) {
      if (interior[y * w + x] == 0) continue;
      counted++;
      final i = (top + y) * p.width + left + x;
      lums[p.lum[i]]++;
      final red = p.rgb[i * 3], green = p.rgb[i * 3 + 1], blue = p.rgb[i * 3 + 2];
      sats[math.max(red, math.max(green, blue)) - math.min(red, math.min(green, blue))]++;
    }
  }

  final shape = blob.normalized();
  final relHeight = blob.height / h;
  final bestByRole = <Role, double>{};
  for (final t in templates) {
    final score = _iou(shape, t.mask) - 0.5 * (relHeight - t.relHeight).abs();
    if (score > (bestByRole[t.role] ?? double.negativeInfinity)) {
      bestByRole[t.role] = score;
    }
  }
  if (bestByRole.isEmpty) return null;
  final ranked = [for (final e in bestByRole.entries) (e.key, e.value)]
    ..sort((a, b) => b.$2.compareTo(a.$2));
  // Real pieces of ordinary sets match at 0.72 or better; weaker matches
  // are overlays drawn on the board (share buttons, lens icons, arrows).
  if (ranked.first.$2 < 0.65) return null;
  final fill = counted == 0 ? 128 : _kth(lums, 0, 256, counted ~/ 2);
  final saturation = counted == 0 ? 0 : _kth(sats, 0, 256, counted ~/ 2);
  return _SquareReading(c, r, (fill - 128) / 128 - saturation / 200, ranked, shape, relHeight);
}

/// Where two roles match a piece about equally well against the templates,
/// lets the pieces that look just like it vote: all pieces in one image
/// share a piece set, so its other pawns (say) have nearly the same
/// silhouette, and one close call among them is outvoted by the rest.
void _settleCloseCalls(List<_SquareReading> readings) {
  final settled = <_SquareReading, List<(Role, double)>>{};
  for (final s in readings) {
    if (s.ranked.length < 2 || s.ranked[0].$2 - s.ranked[1].$2 >= 0.03) continue;
    final peers = [
      for (final o in readings)
        if (!identical(o, s) && _iou(s.shape, o.shape) >= _peerIou) o,
    ];
    if (peers.isEmpty) continue;
    final votes = <Role, double>{};
    for (final o in [s, ...peers]) {
      for (final (role, score) in o.ranked) {
        votes[role] = (votes[role] ?? 0) + score;
      }
    }
    settled[s] = [
      for (final (role, _) in s.ranked) (role, votes[role]! / (peers.length + 1)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
  }
  // Applied afterwards, so every vote counts the original readings.
  for (final MapEntry(key: s, value: ranked) in settled.entries) {
    s.ranked = ranked;
  }
}

/// Least overlap of two silhouettes for them to count as the same kind of
/// piece of one set.
const _peerIou = 0.88;

/// Splits the pieces into White and Black by brightness.
///
/// No fixed threshold works for every piece set (some black sets are
/// brighter than some white ones), but within one image all pieces share a
/// set. Heavily detailed white pieces (e.g. merida's queen) can still be
/// darker than plain black ones, so where a piece type clearly shows both
/// colours it is split on its own; the rest use the split of all pieces.
///
/// With few pieces one very dark or bright piece can look like a group of
/// its own, so the split of all pieces must fall between the two kings
/// when there are two.
void _assignColors(List<_SquareReading> readings) {
  final values = [for (final s in readings) s.brightness];
  final kings = [
    for (final s in readings)
      if (s.ranked.first.$1 == Role.king) s.brightness,
  ]..sort();
  final overall = (kings.length == 2 ? _splitPoint(values, between: (kings[0], kings[1])) : null) ??
      _splitPoint(values) ??
      0.0;
  for (final s in readings) {
    s.color = s.brightness > overall ? Side.white : Side.black;
  }
  for (final role in Role.values) {
    final same = [for (final s in readings) if (s.ranked.first.$1 == role) s];
    final split = _splitPoint([for (final s in same) s.brightness]);
    if (split == null) continue;
    for (final s in same) {
      s.color = s.brightness > split ? Side.white : Side.black;
    }
  }
}

/// Otsu's threshold between a dark and a bright group, or null if the
/// values don't form two clearly separate groups. With [between], only
/// thresholds inside that range count.
double? _splitPoint(List<double> values, {(double, double)? between}) {
  values = [...values]..sort();
  double? threshold;
  var bestSeparation = 0.0;
  var bestGap = 0.0;
  for (var i = 1; i < values.length; i++) {
    final candidate = (values[i - 1] + values[i]) / 2;
    if (between != null && (candidate <= between.$1 || candidate >= between.$2)) continue;
    final dark = values.sublist(0, i), light = values.sublist(i);
    final darkMean = dark.reduce((a, b) => a + b) / dark.length;
    final lightMean = light.reduce((a, b) => a + b) / light.length;
    final gap = lightMean - darkMean;
    final separation = dark.length * light.length * gap * gap;
    if (separation > bestSeparation) {
      bestSeparation = separation;
      bestGap = gap;
      threshold = candidate;
    }
  }
  return bestGap >= 0.15 ? threshold : null;
}

/// The part of [mask] within a few pixels of [core] ("ink": clearly black
/// or white pixels). Board texture that differs from the square colour but
/// trails away from the piece (wood grain) is dropped. Without enough ink to
/// go on, [mask] is returned unchanged.
Uint8List _nearInk(Uint8List mask, Uint8List core, int w, int h) {
  var inked = 0;
  for (final v in core) {
    inked += v;
  }
  if (inked < w * h * 0.03) return mask;
  final reach = math.max(2, (w * 0.06).round());
  // Distance to the nearest ink pixel, in 8-neighbour steps.
  final dist = Int32List(w * h)..fillRange(0, w * h, 1 << 20);
  final queue = <int>[];
  for (var i = 0; i < w * h; i++) {
    if (core[i] == 1) {
      dist[i] = 0;
      queue.add(i);
    }
  }
  for (var head = 0; head < queue.length; head++) {
    final i = queue[head];
    if (dist[i] >= reach) continue;
    final x = i % w, y = i ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final n = ny * w + nx;
        if (dist[n] > dist[i] + 1) {
          dist[n] = dist[i] + 1;
          queue.add(n);
        }
      }
    }
  }
  final out = Uint8List(w * h);
  for (var i = 0; i < w * h; i++) {
    if (mask[i] == 1 && dist[i] <= reach) out[i] = 1;
  }
  return out;
}

/// The piece's shape in a square: the largest blob of [mask] near ink (see
/// [_nearInk]), with its holes filled.
///
/// A light piece on a light square shows only its grey outline, so it fills
/// only if that outline is closed. Glare (e.g. on a photographed monitor)
/// can make part of the outline too faint to count as ink, leaving a thin
/// broken line; then the unfiltered mask, or the outline with small gaps
/// closed, gives the shape.
_Blob? _pieceBlob(Uint8List mask, Uint8List core, int w, int h) {
  bool filled(_Blob blob) => blob.area >= (blob.right - blob.left + 1) * blob.height * 0.4;
  final inked = _Blob.largest(_nearInk(mask, core, w, h), w, h);
  if (inked == null) return null;
  if (filled(inked)) {
    // Some sets cut a piece in two with a thin light stripe (MPChess's
    // rook): a short blob may be only part of it. Bridging small gaps
    // shows the whole piece.
    if (inked.height >= h * 0.45) return inked;
    final gap = math.max(2, (w * 0.04).round());
    final closed = _Blob.largest(_dilated(_nearInk(mask, core, w, h), w, h, gap), w, h);
    final joined = closed == null ? null : _Blob.largest(closed.eroded(gap), w, h);
    return joined != null && joined.height >= inked.height * 1.3 ? joined : inked;
  }
  final raw = _Blob.largest(mask, w, h);
  if (raw != null && filled(raw)) return raw;
  final gap = math.max(2, (w * 0.05).round());
  final closed = _Blob.largest(_dilated(inked.mask, w, h, gap), w, h);
  final shrunk = closed == null ? null : _Blob.largest(closed.eroded(gap), w, h);
  return shrunk != null && filled(shrunk) ? shrunk : inked;
}

/// [mask] grown by [steps] pixels (4-neighbour dilation).
Uint8List _dilated(Uint8List mask, int w, int h, int steps) {
  var current = mask;
  for (var step = 0; step < steps; step++) {
    final next = Uint8List.fromList(current);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (current[i] == 1) continue;
        if ((x > 0 && current[i - 1] == 1) ||
            (x < w - 1 && current[i + 1] == 1) ||
            (y > 0 && current[i - w] == 1) ||
            (y < h - 1 && current[i + w] == 1)) {
          next[i] = 1;
        }
      }
    }
    current = next;
  }
  return current;
}

double _iou(Uint8List a, Uint8List b) {
  var inter = 0, union = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == 1 || b[i] == 1) {
      union++;
      if (a[i] == 1 && b[i] == 1) inter++;
    }
  }
  return union == 0 ? 0 : inter / union;
}

/// The largest connected shape in a mask, with its holes filled.
class _Blob {
  _Blob(this.mask, this.width, this.left, this.top, this.right, this.bottom, this.area);

  final Uint8List mask;
  final int width;
  final int left, top, right, bottom;
  final int area;

  int get height => bottom - top + 1;

  /// The shape shrunk by [steps] pixels (4-neighbour erosion), or the shape
  /// itself if nothing would remain.
  Uint8List eroded(int steps) {
    final h = mask.length ~/ width;
    var current = mask;
    for (var step = 0; step < steps; step++) {
      final next = Uint8List(mask.length);
      var any = false;
      for (var y = 1; y < h - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          final i = y * width + x;
          if (current[i] == 1 &&
              current[i - 1] == 1 &&
              current[i + 1] == 1 &&
              current[i - width] == 1 &&
              current[i + width] == 1) {
            next[i] = 1;
            any = true;
          }
        }
      }
      if (!any) return current;
      current = next;
    }
    return current;
  }

  static _Blob? largest(Uint8List mask, int w, int h) {
    final labels = Int32List(w * h);
    final stack = <int>[];
    var bestLabel = 0, bestSize = 0, label = 0;
    void visit(int n) {
      if (mask[n] == 1 && labels[n] == 0) {
        labels[n] = label;
        stack.add(n);
      }
    }

    for (var start = 0; start < w * h; start++) {
      if (mask[start] == 0 || labels[start] != 0) continue;
      label++;
      var size = 0;
      stack.add(start);
      labels[start] = label;
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        size++;
        final x = i % w, y = i ~/ w;
        // Left, right, up, down; written out because a list of neighbours
        // per pixel was millions of allocations per scan.
        if (x > 0) visit(i - 1);
        if (x < w - 1) visit(i + 1);
        if (y > 0) visit(i - w);
        if (y < h - 1) visit(i + w);
      }
      if (size > bestSize) {
        bestSize = size;
        bestLabel = label;
      }
    }
    if (bestLabel == 0) return null;

    // Fill holes: everything not reachable from the border without crossing
    // the shape belongs to it.
    final outside = Uint8List(w * h);
    for (var x = 0; x < w; x++) {
      stack
        ..add(x)
        ..add((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      stack
        ..add(y * w)
        ..add(y * w + w - 1);
    }
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (outside[i] == 1 || labels[i] == bestLabel) continue;
      outside[i] = 1;
      final x = i % w, y = i ~/ w;
      if (x > 0) stack.add(i - 1);
      if (x < w - 1) stack.add(i + 1);
      if (y > 0) stack.add(i - w);
      if (y < h - 1) stack.add(i + w);
    }

    final out = Uint8List(w * h);
    var left = w, top = h, right = -1, bottom = -1, area = 0;
    for (var i = 0; i < w * h; i++) {
      if (outside[i] == 1) continue;
      out[i] = 1;
      area++;
      final x = i % w, y = i ~/ w;
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
    }
    return _Blob(out, w, left, top, right, bottom, area);
  }

  /// The shape scaled to fit a [_maskSize] square, keeping its aspect ratio,
  /// centred horizontally and resting on the bottom edge.
  Uint8List normalized() {
    final bw = right - left + 1, bh = bottom - top + 1;
    final scale = _maskSize / math.max(bw, bh);
    final ow = bw * scale, oh = bh * scale;
    final ox = (_maskSize - ow) / 2, oy = _maskSize - oh;
    final out = Uint8List(_maskSize * _maskSize);
    for (var y = 0; y < _maskSize; y++) {
      for (var x = 0; x < _maskSize; x++) {
        // 2x2 supersampling per output cell.
        var hits = 0;
        for (final (dx, dy) in const [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]) {
          final sx = ((x + dx - ox) / scale).floor();
          final sy = ((y + dy - oy) / scale).floor();
          if (sx < 0 || sy < 0 || sx >= bw || sy >= bh) continue;
          hits += mask[(top + sy) * width + left + sx];
        }
        if (hits >= 2) out[y * _maskSize + x] = 1;
      }
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// Board assembly

/// How far the roles read (per [roleOf]) are from a position a game can
/// reach (0 when plausible, else roughly one per problem), and how many
/// pieces are beyond a side's starting set (a second queen, a third
/// bishop...): possible, but rare. Each side needs one king, at most 8
/// pawns (never on the first or last rank) and no more extra queens,
/// rooks, bishops and knights than it has promoted pawns.
(int, int) _materialProblems(List<_SquareReading> readings, Role Function(_SquareReading) roleOf) {
  var bad = 0, unusual = 0;
  for (final side in Side.values) {
    final count = {for (final role in Role.values) role: 0};
    for (final s in readings) {
      if (s.color == side) count[roleOf(s)] = count[roleOf(s)]! + 1;
    }
    bad += (count[Role.king]! - 1).abs();
    final pawns = count[Role.pawn]!;
    bad += math.max(0, pawns - 8);
    final extra = math.max<int>(0, count[Role.queen]! - 1) +
        math.max<int>(0, count[Role.rook]! - 2) +
        math.max<int>(0, count[Role.bishop]! - 2) +
        math.max<int>(0, count[Role.knight]! - 2);
    bad += math.max(0, extra - math.max(0, 8 - pawns));
    unusual += extra;
  }
  for (final s in readings) {
    if (roleOf(s) == Role.pawn && (s.row == 0 || s.row == 7)) bad++;
  }
  return (bad, unusual);
}

/// When the best role of each piece on its own adds up to an impossible
/// position (13 bishops and no king, say, from a piece set unlike any
/// template), rethinks the roles of whole groups of identical-looking
/// pieces: in one image every pawn has the same silhouette, so they get
/// the same role. Picks the roles that make the position possible while
/// matching the shapes as well as it can. Returns whether anything changed.
bool _makePlausible(List<_SquareReading> readings) {
  final (bad, unusual) = _materialProblems(readings, (s) => s.ranked.first.$1);
  if (bad == 0 && unusual < 3) return false;
  final groups = <List<_SquareReading>>[];
  for (final s in readings) {
    final group = groups.where((g) => _iou(g.first.shape, s.shape) >= _peerIou).firstOrNull;
    if (group == null) {
      groups.add([s]);
    } else {
      group.add(s);
    }
  }
  double scoreOf(_SquareReading s, Role role) =>
      s.ranked.firstWhere((e) => e.$1 == role, orElse: () => (role, 0.0)).$2;
  final roleOf = <_SquareReading, Role>{for (final s in readings) s: s.ranked.first.$1};
  final groupRole = [for (final g in groups) roleOf[g.first]!];
  void apply() {
    for (var i = 0; i < groups.length; i++) {
      for (final s in groups[i]) {
        roleOf[s] = groupRole[i];
      }
    }
  }

  // Being possible matters far more than a closer shape match, and usual
  // material more than a slightly closer one.
  double objective() {
    var total = 0.0;
    for (final s in readings) {
      total += scoreOf(s, roleOf[s]!);
    }
    final (bad, unusual) = _materialProblems(readings, (s) => roleOf[s]!);
    // In every set the king is at least as tall as the queen: that settles
    // a near-tie between a king-like and a queen-like group. Each side's
    // king is compared with its own queens only: in a photo, pieces nearer
    // the camera look taller.
    var shorterKing = 0.0;
    for (final s in readings) {
      if (roleOf[s] != Role.king) continue;
      for (final o in readings) {
        if (o.color == s.color && roleOf[o] == Role.queen && o.relHeight > s.relHeight + 0.005) shorterKing += 0.2;
      }
    }
    // With much material left, kings keep to the outer two ranks (they only
    // walk to the middle in endgames): a tie-breaker, like the height.
    var centralKing = 0.0;
    if (readings.length >= 16) {
      for (final s in readings) {
        if (roleOf[s] == Role.king && s.row >= 2 && s.row <= 5) centralKing += 0.05;
      }
    }
    return total - 10 * bad - unusual - shorterKing - centralKing;
  }

  // Few groups (the usual case): try every combination of roles, or of
  // each group's three likeliest ones when there are many groups. A fix
  // can take two groups changing at once (bishops back to bishops and
  // kings to kings), which one step at a time can't find; and an unusual
  // piece set's pawns may not even look most like pawns.
  final allRoles = math.pow(Role.values.length, groups.length) <= 300000;
  final options = [
    for (final g in groups) allRoles ? Role.values : [for (final e in g.first.ranked.take(3)) e.$1],
  ];
  final combinations = options.fold<double>(1, (n, o) => n * o.length);
  if (combinations <= 300000) {
    var best = double.negativeInfinity;
    List<Role>? bestRoles;
    void search(int i) {
      if (i == groups.length) {
        apply();
        final value = objective();
        if (value > best) {
          best = value;
          bestRoles = [...groupRole];
        }
        return;
      }
      for (final role in options[i]) {
        groupRole[i] = role;
        search(i + 1);
      }
    }

    search(0);
    groupRole.setAll(0, bestRoles!);
  }

  apply();
  var current = objective();
  // Hill climbing from there: change one group's role, or swap two groups'
  // roles, while that helps.
  for (var round = 0; round < 50; round++) {
    var bestValue = current;
    void Function()? bestMove;
    for (var i = 0; i < groups.length; i++) {
      final was = groupRole[i];
      for (final role in Role.values) {
        if (role == was) continue;
        groupRole[i] = role;
        apply();
        final value = objective();
        if (value > bestValue + 1e-9) {
          bestValue = value;
          bestMove = () => groupRole[i] = role;
        }
      }
      groupRole[i] = was;
      for (var j = i + 1; j < groups.length; j++) {
        final other = groupRole[j];
        if (other == was) continue;
        groupRole[i] = other;
        groupRole[j] = was;
        apply();
        final value = objective();
        if (value > bestValue + 1e-9) {
          bestValue = value;
          bestMove = () {
            groupRole[i] = other;
            groupRole[j] = was;
          };
        }
        groupRole[i] = was;
        groupRole[j] = other;
      }
    }
    if (bestMove == null) break;
    bestMove();
    current = bestValue;
  }
  apply();
  var changed = false;
  for (final s in readings) {
    final role = roleOf[s]!;
    if (s.ranked.first.$1 == role) continue;
    changed = true;
    s.ranked = [
      (role, scoreOf(s, role)),
      for (final e in s.ranked)
        if (e.$1 != role) e,
    ];
  }
  return changed;
}

RecognizedBoard _assemble(List<_SquareReading> readings, bool? labelledBlackAtBottom) {
  _settleCloseCalls(readings);
  _assignColors(readings);
  if (_makePlausible(readings)) _assignColors(readings);

  // Decide which side is at the bottom: kings if we have both, otherwise
  // where each side's pieces sit on average.
  _SquareReading? king(Side side) {
    final kings = readings.where((s) => s.color == side && s.ranked.first.$1 == Role.king);
    return kings.isEmpty ? null : kings.reduce((a, b) => a.ranked.first.$2 >= b.ranked.first.$2 ? a : b);
  }

  double meanRow(Side side) {
    final rows = [for (final s in readings) if (s.color == side) s.row];
    return rows.isEmpty ? 3.5 : rows.reduce((a, b) => a + b) / rows.length;
  }

  final wk = king(Side.white), bk = king(Side.black);
  final blackAtBottom = labelledBlackAtBottom ??
      (wk != null && bk != null ? wk.row < bk.row : meanRow(Side.white) < meanRow(Side.black));

  Square squareOf(_SquareReading s) => blackAtBottom
      ? Square.fromCoords(File(7 - s.col), Rank(s.row))
      : Square.fromCoords(File(s.col), Rank(7 - s.row));

  var board = Board.empty;
  final keptKing = {Side.white: wk, Side.black: bk};
  for (final s in readings) {
    final square = squareOf(s);
    final backRank = square.rank == Rank.first || square.rank == Rank.eighth;
    // Take the best role that is possible here: pawns never stand on the
    // back ranks and each side has exactly one king.
    final role = s.ranked
        .map((e) => e.$1)
        .firstWhere(
          (role) =>
              !(role == Role.pawn && backRank) &&
              !(role == Role.king && !identical(keptKing[s.color], s)),
          orElse: () => s.ranked.first.$1,
        );
    board = board.setPieceAt(square, Piece(color: s.color, role: role));
  }
  return RecognizedBoard(board: board, blackAtBottom: blackAtBottom);
}
