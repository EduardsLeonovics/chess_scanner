import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// Straightening a photographed board.
//
// A board seen at an angle (a photo of a monitor, a printed diagram) is no
// longer an axis-aligned grid, but its square edges are still two families
// of straight lines: 9 per direction, each family meeting in a vanishing
// point. Along any line crossing a family, the 9 lines' positions follow a
// 1D projective map of their index, u(k) = (a·k + b) / (c·k + 1), whatever
// the perspective. So:
//
// 1. find straight edges (Hough transform, each edge pixel voting only near
//    its own gradient direction),
// 2. split the strongest lines into the two dominant directions,
// 3. per direction, find the 9-line projective grid that most lines agree
//    with (RANSAC over triples of lines and their possible indices),
// 4. intersect the outermost lines for the 4 board corners, and warp the
//    photo so the board is square and upright, with a margin around it.
//
// The existing screenshot reader then finds the exact grid in the warped
// image, so the fit here only has to be roughly right (within a square).

/// Longest side the lines are searched at.
const _workSide = 800;

/// Hough resolution: half a degree, one pixel.
const _thetaStep = 0.5;
const _thetaBins = 360;

/// Each edge pixel votes within this many degrees of its gradient direction.
const _voteSpread = 3.0;

/// Strongest lines kept, and per direction for the grid fit.
const _maxLines = 120;
const _maxFamilyLines = 26;

/// Side of the straightened image, and the margin around the board in it
/// (as a share of the board side).
const rectifiedSide = 800;
const _margin = 0.2;

class _Line {
  const _Line(this.theta, this.rho, this.strength);

  /// Normal direction in degrees, [0, 180), and distance from the origin:
  /// x·cos θ + y·sin θ = ρ.
  final double theta;
  final double rho;
  final double strength;
}

/// The photo with the board found in it straightened: square, upright, the
/// board filling the middle of a [rectifiedSide]² image. Null if no board
/// grid could be found.
img.Image? rectifyBoard(img.Image image) {
  final scale = _workSide / math.max(image.width, image.height);
  final work = scale < 1
      ? img.copyResize(image,
          width: (image.width * scale).round(), height: (image.height * scale).round())
      : image;
  final s = scale < 1 ? scale : 1.0;
  final w = work.width, h = work.height;
  if (w < 64 || h < 64) return null;

  final gray = _gray(work);
  final lines = _houghLines(gray, w, h);
  if (lines.length < 10) return null;

  final families = _families(lines);
  if (families == null) return null;
  final candidates = [
    for (final (angle, members) in families) _fitFamily(members, angle, w, h),
  ];
  if (candidates.any((c) => c.isEmpty)) return null;

  // Text, frames and piece outlines also make lines, so several grids fit
  // about as well. The board is the pair whose 64 cells alternate light and
  // dark the most; a grid off by half a square scores about zero.
  // The best-fitting pair has the most accurate lines, so it wins unless
  // another pair is clearly more of a board.
  List<(double, double, _Pt)>? bestCorners;
  var bestContrast = 0.0;
  var firstContrast = 0.0;
  List<(double, double, _Pt)>? firstCorners;
  for (final a in candidates[0]) {
    for (final b in candidates[1]) {
      final corners = <(double, double, _Pt)>[];
      for (final i in [0, 8]) {
        for (final j in [0, 8]) {
          final p = _intersect(a.line(i), b.line(j));
          if (p == null) break;
          corners.add((i / 8, j / 8, p));
        }
      }
      if (corners.length < 4) continue;
      final hom = _Homography.fromCorners(corners);
      if (hom == null) continue;
      final contrast = _checkerContrast(gray, w, h, hom);
      if (identical(a, candidates[0].first) && identical(b, candidates[1].first)) {
        firstContrast = contrast;
        firstCorners = corners;
      }
      if (contrast > bestContrast) {
        bestContrast = contrast;
        bestCorners = corners;
      }
    }
  }
  if (firstCorners != null && firstContrast >= _minContrast && bestContrast < firstContrast * 1.3) {
    bestCorners = firstCorners;
  }
  if (bestCorners == null || bestContrast < _minContrast) return null;

  final homography = _orientedHomography([
    for (final (x, y, p) in bestCorners) (x, y, _Pt(p.x / s, p.y / s)),
  ]);
  if (homography == null) return null;
  return _warp(image, homography);
}

/// Least light/dark difference between a grid's cells, in grey levels, for
/// it to count as a board.
const _minContrast = 12.0;

/// How strongly the 8×8 cells under [hom] alternate: the mean brightness of
/// one colour's cells minus the other's (absolute), from the middle of each
/// cell, where pieces cover the least background.
double _checkerContrast(Float32List gray, int w, int h, _Homography hom) {
  var sum = 0.0;
  var counted = 0;
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      var cell = 0.0;
      var samples = 0;
      for (final dy in const [0.2, 0.5, 0.8]) {
        for (final dx in const [0.2, 0.5, 0.8]) {
          // The corners of a cell show the background around a piece.
          if (dx == 0.5 && dy == 0.5) continue;
          final p = hom.map((c + dx) / 8, (r + dy) / 8);
          final x = p.x.round(), y = p.y.round();
          if (x < 0 || y < 0 || x >= w || y >= h) continue;
          cell += gray[y * w + x];
          samples++;
        }
      }
      if (samples == 0) return 0;
      counted++;
      sum += (r + c).isEven ? cell / samples : -cell / samples;
    }
  }
  return counted < 64 ? 0 : (sum / 32).abs();
}

// ---------------------------------------------------------------------------
// Lines

Float32List _gray(img.Image image) {
  final rgb = image
      .convert(format: img.Format.uint8, numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  final n = image.width * image.height;
  final gray = Float32List(n);
  for (var i = 0; i < n; i++) {
    gray[i] = (rgb[i * 3] + rgb[i * 3 + 1] + rgb[i * 3 + 2]) / 3;
  }
  return gray;
}

List<_Line> _houghLines(Float32List g, int w, int h) {
  // Sobel gradients.
  final n = w * h;
  final gx = Float32List(n), gy = Float32List(n), mag = Float32List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final a = g[i - w - 1], b = g[i - w], c = g[i - w + 1];
      final d = g[i - 1], f = g[i + 1];
      final p = g[i + w - 1], q = g[i + w], r = g[i + w + 1];
      final dx = (c + 2 * f + r) - (a + 2 * d + p);
      final dy = (p + 2 * q + r) - (a + 2 * b + c);
      gx[i] = dx;
      gy[i] = dy;
      mag[i] = math.sqrt(dx * dx + dy * dy);
    }
  }

  // The strongest 10% of gradients vote.
  var maxMag = 0.0;
  for (final m in mag) {
    if (m > maxMag) maxMag = m;
  }
  if (maxMag == 0) return const [];
  const bins = 1024;
  final hist = Int32List(bins);
  for (final m in mag) {
    hist[math.min(bins - 1, (m / maxMag * (bins - 1)).floor())]++;
  }
  var threshold = maxMag;
  for (var k = bins - 1, count = 0; k >= 0; k--) {
    count += hist[k];
    if (count >= n * 0.1) {
      threshold = k / (bins - 1) * maxMag;
      break;
    }
  }

  final diag = math.sqrt(w * w + h * h).ceil();
  final rhoBins = 2 * diag + 1;
  final acc = Float32List(_thetaBins * rhoBins);
  final cosT = Float64List(_thetaBins), sinT = Float64List(_thetaBins);
  for (var t = 0; t < _thetaBins; t++) {
    cosT[t] = math.cos(t * _thetaStep * math.pi / 180);
    sinT[t] = math.sin(t * _thetaStep * math.pi / 180);
  }
  final spread = (_voteSpread / _thetaStep).round();
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final m = mag[i];
      if (m <= threshold) continue;
      var angle = math.atan2(gy[i], gx[i]) * 180 / math.pi;
      angle %= 180;
      if (angle < 0) angle += 180;
      final center = (angle / _thetaStep).round();
      for (var k = -spread; k <= spread; k++) {
        final t = (center + k) % _thetaBins;
        final rho = (x * cosT[t] + y * sinT[t]).round() + diag;
        acc[t * rhoBins + rho] += m;
      }
    }
  }

  // Local maxima in a 9×9 window (θ wraps around), strongest first.
  var accMax = 0.0;
  for (final v in acc) {
    if (v > accMax) accMax = v;
  }
  final floor = accMax * 0.05;
  final peaks = <_Line>[];
  for (var t = 0; t < _thetaBins; t++) {
    for (var r = 4; r < rhoBins - 4; r++) {
      final v = acc[t * rhoBins + r];
      if (v <= floor) continue;
      var isMax = true;
      for (var dt = -4; dt <= 4 && isMax; dt++) {
        final tt = (t + dt) % _thetaBins;
        // Wrapping θ past 180° mirrors ρ.
        final wraps = t + dt < 0 || t + dt >= _thetaBins;
        for (var dr = -4; dr <= 4; dr++) {
          if (dt == 0 && dr == 0) continue;
          final rr = wraps ? rhoBins - 1 - (r + dr) : r + dr;
          if (rr < 0 || rr >= rhoBins) continue;
          final other = acc[tt * rhoBins + rr];
          if (other > v || (other == v && (dt < 0 || (dt == 0 && dr < 0)))) {
            isMax = false;
            break;
          }
        }
      }
      if (isMax) peaks.add(_Line(t * _thetaStep, (r - diag).toDouble(), v));
    }
  }
  peaks.sort((a, b) => b.strength.compareTo(a.strength));
  return peaks.take(_maxLines).toList();
}

double _angleDiff(double a, double b) {
  final d = (a - b).abs() % 180;
  return math.min(d, 180 - d);
}

/// The two dominant line directions (at least 30° apart) and the lines
/// near each, strongest first.
List<(double, List<_Line>)>? _families(List<_Line> lines) {
  final hist = Float64List(180);
  for (final l in lines.take(60)) {
    hist[l.theta.floor() % 180] += l.strength;
  }
  final smooth = Float64List(180);
  for (var i = 0; i < 180; i++) {
    for (var k = -4; k <= 4; k++) {
      smooth[i] += hist[(i + k) % 180];
    }
  }
  int argMax(bool Function(int) allowed) {
    var best = -1;
    for (var i = 0; i < 180; i++) {
      if (allowed(i) && (best < 0 || smooth[i] > smooth[best])) best = i;
    }
    return best;
  }

  final a1 = argMax((_) => true);
  final a2 = argMax((i) => _angleDiff(i.toDouble(), a1.toDouble()) > 30);
  if (a2 < 0 || smooth[a2] == 0) return null;
  return [
    for (final a in [a1, a2])
      (
        a.toDouble(),
        [for (final l in lines) if (_angleDiff(l.theta, a.toDouble()) < 15) l].take(_maxFamilyLines).toList(),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Grid fit

class _Pt {
  const _Pt(this.x, this.y);

  final double x;
  final double y;
}

/// A line through two points.
typedef _Segment = (_Pt, _Pt);

/// 9 lines of one direction: their positions along two crossing lines
/// ("transversals", [_t0] and [_t1]) as 1D projective maps of the index.
class _GridFit {
  _GridFit(this._t0, this._t1, this._direction, this._p0, this._p1, this.inliers);

  final _Line _t0;
  final _Line _t1;

  /// Unit vector along the transversals, positions are measured along it.
  final _Pt _direction;
  final List<double> _p0;
  final List<double> _p1;
  final int inliers;

  _Segment line(int k) {
    _Pt on(_Line t, double pos) {
      final th = t.theta * math.pi / 180;
      return _Pt(math.cos(th) * t.rho + _direction.x * pos, math.sin(th) * t.rho + _direction.y * pos);
    }

    return (on(_t0, _p0[k]), on(_t1, _p1[k]));
  }
}

_Pt? _intersectLines(_Line a, _Line b) {
  final t1 = a.theta * math.pi / 180, t2 = b.theta * math.pi / 180;
  final a11 = math.cos(t1), a12 = math.sin(t1), a21 = math.cos(t2), a22 = math.sin(t2);
  final det = a11 * a22 - a12 * a21;
  if (det.abs() < 1e-6) return null;
  return _Pt((a.rho * a22 - a12 * b.rho) / det, (a11 * b.rho - a.rho * a21) / det);
}

_Pt? _intersect(_Segment a, _Segment b) {
  final (p, p2) = a;
  final (q, q2) = b;
  final rx = p2.x - p.x, ry = p2.y - p.y;
  final sx = q2.x - q.x, sy = q2.y - q.y;
  final det = rx * (-sy) - ry * (-sx);
  if (det.abs() < 1e-9) return null;
  final t = ((q.x - p.x) * (-sy) - (q.y - p.y) * (-sx)) / det;
  return _Pt(p.x + t * rx, p.y + t * ry);
}

/// The 9-line projective grids most of [lines] agree with, best first,
/// each clearly different from the others.
List<_GridFit> _fitFamily(List<_Line> lines, double angle, int w, int h) {
  // Two transversals across the family, a quarter of the image apart.
  final normal = (angle + 90) % 180;
  final th = normal * math.pi / 180;
  final center = (w / 2) * math.cos(th) + (h / 2) * math.sin(th);
  final span = 0.25 * math.min(w, h);
  final t0 = _Line(normal, center - span, 0), t1 = _Line(normal, center + span, 0);
  final dir = _Pt(math.cos(angle * math.pi / 180), math.sin(angle * math.pi / 180));

  final u = <double>[], v = <double>[];
  for (final l in lines) {
    final p = _intersectLines(l, t0), q = _intersectLines(l, t1);
    if (p == null || q == null) continue;
    u.add(p.x * dir.x + p.y * dir.y);
    v.add(q.x * dir.x + q.y * dir.y);
  }
  final n = u.length;
  if (n < 6) return const [];

  final tol = 0.012 * math.max(w, h);
  final minGap = 0.02 * math.min(w, h);
  final order = List.generate(n, (i) => i)..sort((a, b) => u[a].compareTo(u[b]));
  final p0 = Float64List(9), p1 = Float64List(9);
  final best = <(double, _GridFit)>[];
  const keep = 8;
  bool sameAs(_GridFit fit) {
    for (var k = 0; k < 9; k++) {
      if ((fit._p0[k] - p0[k]).abs() > tol || (fit._p1[k] - p1[k]).abs() > tol) return false;
    }
    return true;
  }

  // u = (a·k + b) / (c·k + 1) through three (k, u) pairs.
  bool solve(List<int> ks, List<double> us, Float64List out) {
    final m = [
      for (var r = 0; r < 3; r++) [ks[r].toDouble(), 1.0, -ks[r] * us[r], us[r]],
    ];
    if (!_gauss(m)) return false;
    final a = m[0][3], b = m[1][3], c = m[2][3];
    for (var k = 0; k < 9; k++) {
      final den = c * k + 1;
      if (den.abs() < 1e-6) return false;
      out[k] = (a * k + b) / den;
    }
    return true;
  }

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      for (var l = j + 1; l < n; l++) {
        final tri = [order[i], order[j], order[l]];
        final tu = [for (final x in tri) u[x]];
        final tv = [for (final x in tri) v[x]];
        for (var ka = 0; ka < 7; ka++) {
          for (var kb = ka + 1; kb < 8; kb++) {
            for (var kc = kb + 1; kc < 9; kc++) {
              final ks = [ka, kb, kc];
              if (!solve(ks, tu, p0) || !solve(ks, tv, p1)) continue;
              var increasing = true;
              for (var k = 1; k < 9 && increasing; k++) {
                if (p0[k] - p0[k - 1] < minGap || p1[k] - p1[k - 1] < minGap) increasing = false;
              }
              if (!increasing) continue;
              var inliers = 0;
              var residual = 0.0;
              for (var k = 0; k < 9; k++) {
                var nearest = double.infinity;
                for (var x = 0; x < n; x++) {
                  final d = math.max((u[x] - p0[k]).abs(), (v[x] - p1[k]).abs());
                  if (d < nearest) nearest = d;
                }
                if (nearest < tol) {
                  inliers++;
                  residual += nearest;
                }
              }
              if (inliers < 6) continue;
              final score = inliers - residual / (tol * 9 + 1);
              if (best.length == keep && score <= best.last.$1) continue;
              final same = best.indexWhere((e) => sameAs(e.$2));
              if (same >= 0) {
                if (score <= best[same].$1) continue;
                best.removeAt(same);
              }
              best.add((score, _GridFit(t0, t1, dir, List.of(p0), List.of(p1), inliers)));
              best.sort((x, y) => y.$1.compareTo(x.$1));
              if (best.length > keep) best.removeLast();
            }
          }
        }
      }
    }
  }
  return [for (final (_, fit) in best) fit];
}

/// Solves the 3×3 system in [m] (augmented, row-major) in place: the
/// solution ends up in the last column. False if singular.
bool _gauss(List<List<double>> m) {
  final rows = m.length;
  for (var c = 0; c < rows; c++) {
    var pivot = c;
    for (var r = c + 1; r < rows; r++) {
      if (m[r][c].abs() > m[pivot][c].abs()) pivot = r;
    }
    if (m[pivot][c].abs() < 1e-9) return false;
    final tmp = m[c];
    m[c] = m[pivot];
    m[pivot] = tmp;
    for (var r = 0; r < rows; r++) {
      if (r == c) continue;
      final f = m[r][c] / m[c][c];
      for (var k = c; k < m[r].length; k++) {
        m[r][k] -= f * m[c][k];
      }
    }
  }
  for (var r = 0; r < rows; r++) {
    m[r][rows] /= m[r][r];
  }
  return true;
}

// ---------------------------------------------------------------------------
// Homography and warp

/// Maps board coordinates (0..1, 0..1) to image points.
class _Homography {
  _Homography(this.h);

  final List<double> h;

  _Pt map(double x, double y) {
    final d = h[6] * x + h[7] * y + h[8];
    return _Pt((h[0] * x + h[1] * y + h[2]) / d, (h[3] * x + h[4] * y + h[5]) / d);
  }

  static _Homography? fromCorners(List<(double, double, _Pt)> corners) {
    final m = <List<double>>[];
    for (final (x, y, p) in corners) {
      m.add([x, y, 1, 0, 0, 0, -p.x * x, -p.x * y, p.x]);
      m.add([0, 0, 0, x, y, 1, -p.y * x, -p.y * y, p.y]);
    }
    if (!_gauss(m)) return null;
    return _Homography([for (final row in m) row[8], 1]);
  }
}

/// A homography from the board square whose x runs left to right and y top
/// to bottom in the photo, as the board appears in it.
_Homography? _orientedHomography(List<(double, double, _Pt)> corners) {
  var c = corners;
  var hom = _Homography.fromCorners(c);
  if (hom == null) return null;
  final o = hom.map(0, 0), ex = hom.map(1, 0), ey = hom.map(0, 1);
  if ((ex.x - o.x).abs() < (ey.x - o.x).abs()) {
    c = [for (final (x, y, p) in c) (y, x, p)];
  }
  hom = _Homography.fromCorners(c);
  if (hom == null) return null;
  final o2 = hom.map(0, 0), ex2 = hom.map(1, 0), ey2 = hom.map(0, 1);
  final flipX = ex2.x < o2.x, flipY = ey2.y < o2.y;
  c = [for (final (x, y, p) in c) (flipX ? 1 - x : x, flipY ? 1 - y : y, p)];
  return _Homography.fromCorners(c);
}

img.Image _warp(img.Image source, _Homography hom) {
  final src = source.convert(format: img.Format.uint8, numChannels: 3);
  final bytes = src.getBytes(order: img.ChannelOrder.rgb);
  final sw = src.width, sh = src.height;
  final outBytes = Uint8List(rectifiedSide * rectifiedSide * 3);
  const total = 1 + 2 * _margin;
  for (var y = 0; y < rectifiedSide; y++) {
    final by = y / rectifiedSide * total - _margin;
    for (var x = 0; x < rectifiedSide; x++) {
      final bx = x / rectifiedSide * total - _margin;
      final p = hom.map(bx, by);
      final o = (y * rectifiedSide + x) * 3;
      if (!(p.x >= 0 && p.y >= 0 && p.x < sw - 1 && p.y < sh - 1)) {
        outBytes[o] = outBytes[o + 1] = outBytes[o + 2] = 0;
        continue;
      }
      // Bilinear.
      final x0 = p.x.floor(), y0 = p.y.floor();
      final fx = p.x - x0, fy = p.y - y0;
      final i00 = (y0 * sw + x0) * 3, i10 = i00 + 3, i01 = i00 + sw * 3, i11 = i01 + 3;
      for (var ch = 0; ch < 3; ch++) {
        final top = bytes[i00 + ch] * (1 - fx) + bytes[i10 + ch] * fx;
        final bottom = bytes[i01 + ch] * (1 - fx) + bytes[i11 + ch] * fx;
        outBytes[o + ch] = (top * (1 - fy) + bottom * fy).round();
      }
    }
  }
  return img.Image.fromBytes(
    width: rectifiedSide,
    height: rectifiedSide,
    bytes: outBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
}
