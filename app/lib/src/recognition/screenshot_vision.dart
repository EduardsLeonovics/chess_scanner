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
/// Throws [RecognitionException] if no board is found.
RecognizedBoard recognizeScreenshot(
  Uint8List imageBytes,
  List<PieceTemplate> templates,
) {
  var image = img.decodeImage(imageBytes);
  if (image == null) {
    throw const RecognitionException("Couldn't read that image.");
  }
  image = img.bakeOrientation(image);
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
      pixels = _Pixels.fromImage(straightened);
      grid = _findGrid(pixels);
    }
  }
  if (grid == null) {
    throw const RecognitionException("Couldn't find a chessboard in that image.");
  }

  final squares = <_SquareReading>[];
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      final reading = _readSquare(pixels, grid, c, r, templates);
      if (reading != null) squares.add(reading);
    }
  }
  return _assemble(squares);
}

// ---------------------------------------------------------------------------
// Pixels

class _Pixels {
  _Pixels(this.width, this.height, this.rgb, this.lum);

  factory _Pixels.fromImage(img.Image image) {
    final rgb = image
        .convert(format: img.Format.uint8, numChannels: 3)
        .getBytes(order: img.ChannelOrder.rgb);
    final n = image.width * image.height;
    final lum = Uint8List(n);
    for (var i = 0; i < n; i++) {
      lum[i] = (rgb[i * 3] * 299 + rgb[i * 3 + 1] * 587 + rgb[i * 3 + 2] * 114) ~/ 1000;
    }
    return _Pixels(image.width, image.height, rgb, lum);
  }

  final int width;
  final int height;
  final Uint8List rgb;
  final Uint8List lum;
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
    List.generate(64, (i) => _background(p, grid, i % 8, i ~/ 8).luminance);

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

_Background _background(_Pixels p, _Grid g, int c, int r) {
  final patchX = math.max(2, (g.stepX * 0.1).round());
  final patchY = math.max(2, (g.stepY * 0.1).round());
  final insetX = math.max(1, (g.stepX * 0.04).round());
  final insetY = math.max(1, (g.stepY * 0.04).round());
  final left = (g.x0 + c * g.stepX).round() + insetX;
  final top = (g.y0 + r * g.stepY).round() + insetY;
  final right = (g.x0 + (c + 1) * g.stepX).round() - insetX - patchX;
  final bottom = (g.y0 + (r + 1) * g.stepY).round() - insetY - patchY;
  final corners = [
    for (final (px, py) in [(left, top), (right, top), (left, bottom), (right, bottom)])
      [
        for (var y = py; y < py + patchY; y++)
          for (var x = px; x < px + patchX; x++)
            if (x >= 0 && y >= 0 && x < p.width && y < p.height) (y * p.width + x) * 3,
      ],
  ];
  final pixels = corners.expand((corner) => corner).toList();
  if (pixels.isEmpty) return const _Background([0, 0, 0], 0);
  int median(int channel) {
    final v = [for (final i in pixels) p.rgb[i + channel]]..sort();
    return v[v.length ~/ 2];
  }

  final bg = _Background([median(0), median(1), median(2)], 0);
  // Texture shows in every corner, a piece only in some (rook bases fill
  // the bottom ones), so the quietest corner tells how textured it is.
  var noise = 1 << 30;
  for (final corner in corners) {
    if (corner.isEmpty) continue;
    final distances = [
      for (final i in corner) bg.distanceTo(p.rgb[i], p.rgb[i + 1], p.rgb[i + 2]),
    ]..sort();
    noise = math.min(noise, distances[(distances.length * 0.9).floor()]);
  }
  return _Background(bg.color, noise);
}

class _SquareReading {
  _SquareReading(this.col, this.row, this.brightness, this.ranked);

  /// Column and row in the image, (0, 0) = top left.
  final int col;
  final int row;

  /// Share of the piece's pixels that are bright; used to tell White from
  /// Black relative to the other pieces in the same image.
  final double brightness;

  /// Candidate roles, best first.
  final List<(Role, double)> ranked;

  Side color = Side.white;
}

_SquareReading? _readSquare(
  _Pixels p,
  _Grid g,
  int c,
  int r,
  List<PieceTemplate> templates,
) {
  final insetX = math.max(1, (g.stepX * 0.04).round());
  final insetY = math.max(1, (g.stepY * 0.04).round());
  final left = math.max(0, (g.x0 + c * g.stepX).round() + insetX);
  final top = math.max(0, (g.y0 + r * g.stepY).round() + insetY);
  final right = math.min(p.width, (g.x0 + (c + 1) * g.stepX).round() - insetX);
  final bottom = math.min(p.height, (g.y0 + (r + 1) * g.stepY).round() - insetY);
  final w = right - left, h = bottom - top;
  if (w < 6 || h < 6) return null;

  final bg = _background(p, g, c, r);
  // Textured squares (wood, marble) need a higher bar, or their grain
  // sticks to the pieces and changes their outline.
  final threshold = math.max(60, 2 * bg.noise);
  final mask = Uint8List(w * h);
  final core = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = ((top + y) * p.width + left + x) * 3;
      final red = p.rgb[i], green = p.rgb[i + 1], blue = p.rgb[i + 2];
      final dist = bg.distanceTo(red, green, blue);
      // Pieces are drawn in near-neutral colours; strongly coloured pixels
      // are arrows or highlights drawn over the board.
      final saturation = math.max(red, math.max(green, blue)) -
          math.min(red, math.min(green, blue));
      if (dist > threshold && saturation <= 60) {
        mask[y * w + x] = 1;
        final lum = p.lum[(top + y) * p.width + left + x];
        if (saturation <= 40 && (lum <= 70 || lum >= 200)) core[y * w + x] = 1;
      }
    }
  }
  final blob = _Blob.largest(_nearInk(mask, core, w, h), w, h);
  // Coordinates, move dots and other small marks are not pieces.
  if (blob == null || blob.height < h * 0.35 || blob.area < w * h * 0.05) {
    return null;
  }

  // Judge brightness away from the outline, which is dark on white pieces
  // too; measured over all lichess sets this separates the colours best.
  final interior = blob.eroded(math.max(1, (w * 0.04).round()));
  var bright = 0, counted = 0;
  for (var y = blob.top; y <= blob.bottom; y++) {
    for (var x = blob.left; x <= blob.right; x++) {
      if (interior[y * w + x] == 0) continue;
      counted++;
      if (p.lum[(top + y) * p.width + left + x] >= 160) bright++;
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
  return _SquareReading(c, r, counted == 0 ? 0 : bright / counted, ranked);
}

/// Splits the pieces into White and Black by brightness.
///
/// No fixed threshold works for every piece set (some black sets are
/// brighter than some white ones), but within one image all pieces share a
/// set. Heavily detailed white pieces (e.g. merida's queen) can still be
/// darker than plain black ones, so where a piece type clearly shows both
/// colours it is split on its own; the rest use the split of all pieces.
void _assignColors(List<_SquareReading> readings) {
  final overall = _splitPoint([for (final s in readings) s.brightness]) ?? 0.3;
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
/// values don't form two clearly separate groups.
double? _splitPoint(List<double> values) {
  values = [...values]..sort();
  double? threshold;
  var bestSeparation = 0.0;
  var bestGap = 0.0;
  for (var i = 1; i < values.length; i++) {
    final dark = values.sublist(0, i), light = values.sublist(i);
    final darkMean = dark.reduce((a, b) => a + b) / dark.length;
    final lightMean = light.reduce((a, b) => a + b) / light.length;
    final gap = lightMean - darkMean;
    final separation = dark.length * light.length * gap * gap;
    if (separation > bestSeparation) {
      bestSeparation = separation;
      bestGap = gap;
      threshold = (values[i - 1] + values[i]) / 2;
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
        for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final n = ny * w + nx;
          if (mask[n] == 1 && labels[n] == 0) {
            labels[n] = label;
            stack.add(n);
          }
        }
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

RecognizedBoard _assemble(List<_SquareReading> readings) {
  _assignColors(readings);

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
  final blackAtBottom = wk != null && bk != null
      ? wk.row < bk.row
      : meanRow(Side.white) < meanRow(Side.black);

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
