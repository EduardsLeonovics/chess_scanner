"""Draws ChessHive's own piece sets for chessground: Geo and Ink.

Every piece is built from simple shapes in a unit square (x right, y down):
smooth turned profiles (a Staunton body is the same curve mirrored), a
spline for the knight's head, plus circles and rounded rectangles. Each is
rendered at 1024 px in its style (flat with an outline, shaded, wood,
glass or pixel art) and saved as WebP at chessground's sizes (128 px base
plus 2.0x, 3.0x and 4.0x). The sets are original work released with the
app under the GPL, so they're safe in an ad-supported app.

Run from app/: python tool/make_piece_sets.py
Writes third_party/chessground/assets/piece_sets/<set>/ and, with
--preview PATH, a contact sheet of all sets on light and dark squares.
"""

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024  # working resolution
OUT = os.path.join('third_party', 'chessground', 'assets', 'piece_sets')
SIZES = {'': 128, '2.0x': 256, '3.0x': 384, '4.0x': 512}


# ---------------------------------------------------------------------------
# Shapes. Body shapes form the silhouette; details are drawn on top.

def poly(*pts):
    return ('poly', pts)


def ellipse(cx, cy, rx, ry=None):
    return ('ellipse', (cx, cy, rx, rx if ry is None else ry))


def rrect(x0, y0, x1, y1, r=0.0):
    return ('rrect', (x0, y0, x1, y1, r))


def line(*pts, w=0.02):
    return ('line', (pts, w))


def trapezoid(top_y, top_half, bottom_y, bottom_half, cx=0.5):
    return poly((cx - top_half, top_y), (cx + top_half, top_y),
                (cx + bottom_half, bottom_y), (cx - bottom_half, bottom_y))


def flare(top_y, bottom_y, top_half, bottom_half, cx=0.5, steps=12):
    """A Staunton body: narrow at the top, curving out to a wide foot."""
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        y = top_y + (bottom_y - top_y) * t
        half = top_half + (bottom_half - top_half) * t * t
        left.append((cx - half, y))
        right.append((cx + half, y))
    return poly(*right, *reversed(left))


def mitre(top_y, bottom_y, half, cx=0.5, steps=16):
    """A bishop's mitre: pointed at the top, widest below the middle,
    narrowing to a neck at the bottom."""
    left, right = [], []
    for i in range(steps + 1):
        t = i / steps
        y = top_y + (bottom_y - top_y) * t
        w = half * math.sin(math.pi * t * 0.88) ** 0.7
        left.append((cx - w, y))
        right.append((cx + w, y))
    return poly(*right, *reversed(left))


def _catmull(points, closed=False, steps=10):
    """Points on a Catmull-Rom spline through [points]."""
    n = len(points)
    out = []
    segments = n if closed else n - 1
    for i in range(segments):
        p0 = points[(i - 1) % n] if closed else points[max(i - 1, 0)]
        p1 = points[i % n]
        p2 = points[(i + 1) % n]
        p3 = points[(i + 2) % n] if closed else points[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
                for k in range(2)))
    if not closed:
        out.append(points[-1])
    return out


def lathe(profile, cx=0.5):
    """A turned body: [profile] is (y, half width) from top to bottom,
    joined by a smooth curve and mirrored around the centre line."""
    curve = _catmull([(w, y) for y, w in profile])
    right = [(cx + w, y) for w, y in curve]
    left = [(cx - w, y) for w, y in reversed(curve)]
    return poly(*right, *left)


def spline(*pts):
    """A smooth closed outline through [pts]."""
    return poly(*_catmull(list(pts), closed=True))


def px(v):
    return v * S


def draw_shape(draw, shape, fill, width_scale=1.0):
    kind, a = shape
    if kind == 'poly':
        draw.polygon([(px(x), px(y)) for x, y in a], fill=fill)
    elif kind == 'ellipse':
        cx, cy, rx, ry = a
        draw.ellipse([px(cx - rx), px(cy - ry), px(cx + rx), px(cy + ry)], fill=fill)
    elif kind == 'rrect':
        x0, y0, x1, y1, r = a
        draw.rounded_rectangle([px(x0), px(y0), px(x1), px(y1)], radius=px(r), fill=fill)
    elif kind == 'line':
        pts, w = a
        width = max(1, round(px(w) * width_scale))
        draw.line([(px(x), px(y)) for x, y in pts], fill=fill, width=width, joint='curve')
        # Round caps.
        for x, y in (pts[0], pts[-1]):
            r = width / 2
            draw.ellipse([px(x) - r, px(y) - r, px(x) + r, px(y) + r], fill=fill)


# ---------------------------------------------------------------------------
# Geo: flat, geometric, bold outline.

def geo(role):
    base = [rrect(0.22, 0.79, 0.78, 0.88, 0.02)]
    if role == 'P':
        return base + [flare(0.48, 0.79, 0.07, 0.20), rrect(0.36, 0.43, 0.64, 0.49, 0.01),
                       ellipse(0.5, 0.29, 0.12)], [line((0.26, 0.79), (0.74, 0.79), w=0.018)]
    if role == 'R':
        top = [rrect(0.28, 0.20, 0.38, 0.34), rrect(0.45, 0.20, 0.55, 0.34), rrect(0.62, 0.20, 0.72, 0.34),
               rrect(0.28, 0.30, 0.72, 0.40)]
        return base + [trapezoid(0.40, 0.16, 0.79, 0.21)] + top, [
            line((0.26, 0.79), (0.74, 0.79), w=0.018), line((0.33, 0.40), (0.67, 0.40), w=0.018)]
    if role == 'B':
        return base + [trapezoid(0.56, 0.07, 0.79, 0.19), rrect(0.36, 0.53, 0.64, 0.59, 0.01),
                       ellipse(0.5, 0.40, 0.14, 0.17), poly((0.40, 0.30), (0.5, 0.17), (0.60, 0.30)),
                       ellipse(0.5, 0.15, 0.05)], [
            line((0.26, 0.79), (0.74, 0.79), w=0.018), line((0.47, 0.44), (0.58, 0.33), w=0.03)]
    if role == 'N':
        head = poly((0.30, 0.80), (0.33, 0.63), (0.43, 0.52), (0.31, 0.51), (0.21, 0.48), (0.16, 0.42),
                    (0.21, 0.34), (0.35, 0.25), (0.39, 0.13), (0.47, 0.22), (0.60, 0.23), (0.71, 0.33),
                    (0.77, 0.52), (0.75, 0.80))
        return base + [head], [
            line((0.26, 0.79), (0.74, 0.79), w=0.018), ('ellipse', (0.35, 0.33, 0.028, 0.028)),
            line((0.52, 0.27), (0.66, 0.37), (0.70, 0.55), w=0.02)]
    if role == 'Q':
        crown = poly((0.24, 0.30), (0.36, 0.47), (0.42, 0.24), (0.5, 0.45), (0.58, 0.24), (0.64, 0.47),
                     (0.76, 0.30), (0.70, 0.56), (0.30, 0.56))
        balls = [ellipse(x, y, 0.045) for x, y in ((0.24, 0.27), (0.42, 0.21), (0.58, 0.21), (0.76, 0.27))]
        return base + [trapezoid(0.56, 0.18, 0.79, 0.24), crown, ellipse(0.5, 0.16, 0.055)] + balls, [
            line((0.26, 0.79), (0.74, 0.79), w=0.018), line((0.32, 0.56), (0.68, 0.56), w=0.018)]
    if role == 'K':
        return base + [trapezoid(0.52, 0.17, 0.79, 0.23), rrect(0.30, 0.40, 0.70, 0.53, 0.03),
                       rrect(0.46, 0.10, 0.54, 0.40), rrect(0.38, 0.18, 0.62, 0.26)], [
            line((0.26, 0.79), (0.74, 0.79), w=0.018), line((0.33, 0.53), (0.67, 0.53), w=0.018)]


# ---------------------------------------------------------------------------
# Staunton: Ink's classic shapes, drawn as smooth turned profiles. [fat]
# widens everything.

def staunton(role, fat=1.0):
    def w(v):
        return v * fat

    def base(top):
        # A stepped foot: a wide plinth with a smaller ring on it.
        return [rrect(0.5 - w(0.27), 0.835, 0.5 + w(0.27), 0.905, 0.025),
                lathe([(top, w(0.17)), (top + 0.03, w(0.2)), (0.84, w(0.23))])]

    if role == 'P':
        body = lathe([(0.47, w(0.06)), (0.58, w(0.075)), (0.68, w(0.12)), (0.76, w(0.18))])
        return base(0.76) + [body, ellipse(0.5, 0.49, w(0.13), 0.035), ellipse(0.5, 0.345, w(0.12))], \
            [line((0.5 - w(0.2), 0.835), (0.5 + w(0.2), 0.835), w=0.012),
             line((0.5 - w(0.11), 0.49), (0.5 + w(0.11), 0.49), w=0.01)]
    if role == 'R':
        tower = lathe([(0.37, w(0.13)), (0.5, w(0.12)), (0.66, w(0.14)), (0.76, w(0.19))])
        top = poly((0.5 - w(0.2), 0.17), (0.5 - w(0.12), 0.17), (0.5 - w(0.12), 0.235),
                   (0.5 - w(0.04), 0.235), (0.5 - w(0.04), 0.17), (0.5 + w(0.04), 0.17),
                   (0.5 + w(0.04), 0.235), (0.5 + w(0.12), 0.235), (0.5 + w(0.12), 0.17),
                   (0.5 + w(0.2), 0.17), (0.5 + w(0.19), 0.33), (0.5 - w(0.19), 0.33))
        return base(0.76) + [tower, top, rrect(0.5 - w(0.17), 0.31, 0.5 + w(0.17), 0.39, 0.01)], \
            [line((0.5 - w(0.2), 0.835), (0.5 + w(0.2), 0.835), w=0.012),
             line((0.5 - w(0.16), 0.33), (0.5 + w(0.16), 0.33), w=0.012),
             line((0.5 - w(0.13), 0.39), (0.5 + w(0.13), 0.39), w=0.012),
             line((0.5 - w(0.16), 0.70), (0.5 + w(0.16), 0.70), w=0.01)]
    if role == 'B':
        body = lathe([(0.58, w(0.065)), (0.66, w(0.08)), (0.72, w(0.13)), (0.77, w(0.18))])
        head = lathe([(0.17, 0.0), (0.2, w(0.05)), (0.27, w(0.105)), (0.37, w(0.135)), (0.47, w(0.12)),
                      (0.55, w(0.06)), (0.565, 0.0)])
        return base(0.77) + [body, head, ellipse(0.5, 0.575, w(0.135), 0.035), ellipse(0.5, 0.145, w(0.045))], \
            [line((0.5 - w(0.2), 0.835), (0.5 + w(0.2), 0.835), w=0.012),
             line((0.5 - w(0.12), 0.575), (0.5 + w(0.12), 0.575), w=0.01),
             line((0.5 - w(0.03), 0.42), (0.5 + w(0.06), 0.29), w=0.018)]
    if role == 'N':
        def k(x):  # widen around the centre
            return 0.5 + (x - 0.5) * fat
        head = spline((k(0.32), 0.78), (k(0.34), 0.66), (k(0.41), 0.57), (k(0.44), 0.52), (k(0.36), 0.51),
                      (k(0.27), 0.505), (k(0.2), 0.47), (k(0.17), 0.42), (k(0.21), 0.37),
                      (k(0.31), 0.30), (k(0.37), 0.23), (k(0.39), 0.14), (k(0.45), 0.19), (k(0.5), 0.15),
                      (k(0.54), 0.21), (k(0.64), 0.25), (k(0.73), 0.36), (k(0.77), 0.52),
                      (k(0.75), 0.68), (k(0.72), 0.78))
        return base(0.76) + [head], \
            [line((0.5 - w(0.2), 0.835), (0.5 + w(0.2), 0.835), w=0.012),
             ('ellipse', (k(0.355), 0.31, 0.022, 0.022)),
             line((k(0.21), 0.435), (k(0.25), 0.44), w=0.012),
             line((k(0.55), 0.24), (k(0.66), 0.33), (k(0.70), 0.47), (k(0.69), 0.62), w=0.012)]
    if role == 'Q':
        body = lathe([(0.5, w(0.1)), (0.6, w(0.11)), (0.7, w(0.15)), (0.77, w(0.2))])
        crown = poly((0.5 - w(0.22), 0.25), (0.5 - w(0.12), 0.44), (0.5 - w(0.085), 0.21), (0.5, 0.42),
                     (0.5 + w(0.085), 0.21), (0.5 + w(0.12), 0.44), (0.5 + w(0.22), 0.25),
                     (0.5 + w(0.15), 0.52), (0.5 - w(0.15), 0.52))
        balls = [ellipse(0.5 + w(dx), y, w(0.035)) for dx, y in
                 ((-0.22, 0.235), (-0.085, 0.19), (0.085, 0.19), (0.22, 0.235))]
        return base(0.77) + [body, crown, ellipse(0.5, 0.52, w(0.155), 0.035), ellipse(0.5, 0.135, w(0.045))] \
            + balls, [line((0.5 - w(0.2), 0.835), (0.5 + w(0.2), 0.835), w=0.012),
                      line((0.5 - w(0.14), 0.52), (0.5 + w(0.14), 0.52), w=0.012),
                      line((0.5 - w(0.13), 0.68), (0.5 + w(0.13), 0.68), w=0.01)]
    if role == 'K':
        body = lathe([(0.47, w(0.11)), (0.58, w(0.11)), (0.7, w(0.15)), (0.77, w(0.2))])
        head = lathe([(0.27, w(0.13)), (0.33, w(0.17)), (0.42, w(0.15)), (0.48, w(0.12))])
        return base(0.77) + [body, head, ellipse(0.5, 0.485, w(0.15), 0.035),
                             rrect(0.5 - w(0.025), 0.08, 0.5 + w(0.025), 0.28, 0.008),
                             rrect(0.5 - w(0.075), 0.13, 0.5 + w(0.075), 0.175, 0.008)], \
            [line((0.5 - w(0.2), 0.835), (0.5 + w(0.2), 0.835), w=0.012),
             line((0.5 - w(0.14), 0.485), (0.5 + w(0.14), 0.485), w=0.012),
             line((0.5 - w(0.14), 0.33), (0.5 + w(0.14), 0.33), w=0.01),
             line((0.5 - w(0.13), 0.68), (0.5 + w(0.13), 0.68), w=0.01)]


def ink(role):
    return staunton(role)


# ---------------------------------------------------------------------------
# Rendering

STYLES = {
    'geo': dict(make=geo, outline=0.022,
                colors={'w': ('#fbfbf8', '#1c1c1c', '#1c1c1c'), 'b': ('#2a2a2c', '#0b0b0b', '#e9e9e4')}),
    'ink': dict(make=ink, outline=0.016,
                colors={'w': ('#ffffff', '#0e0e0e', '#0e0e0e'), 'b': ('#141414', '#000000', '#f4f4f4')}),
}


def render(style, color, role):
    spec = STYLES[style]
    body, details = spec['make'](role)
    fill, outline, detail = spec['colors'][color]

    mask = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(mask)
    for shape in body:
        draw_shape(d, shape, 255)

    # Outline: grow the silhouette by blurring and re-thresholding.
    radius = spec['outline'] * S
    grown = mask.filter(ImageFilter.GaussianBlur(radius / 2)).point(lambda v: 255 if v > 6 else 0)
    grown = grown.filter(ImageFilter.MaxFilter(int(radius) // 2 * 2 + 1))

    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    out.paste(outline, (0, 0), grown)
    out.paste(fill, (0, 0), mask)

    layer = Image.new('L', (S, S), 0)
    dl = ImageDraw.Draw(layer)
    for shape in details:
        draw_shape(dl, shape, 255)
    out.paste(detail, (0, 0), ImageChops.multiply(layer, mask))
    return out


def main():
    styles = [s for s in STYLES if '--only' not in sys.argv or s in sys.argv[sys.argv.index('--only') + 1].split(',')]
    previews = []
    for style in styles:
        for color in 'wb':
            for role in 'KQRBNP':
                image = render(style, color, role)
                previews.append(image.resize((96, 96), Image.LANCZOS))
                if '--no-write' in sys.argv:
                    continue
                for folder, size in SIZES.items():
                    target = os.path.join(OUT, style, folder)
                    os.makedirs(target, exist_ok=True)
                    image.resize((size, size), Image.LANCZOS).save(
                        os.path.join(target, f'{color}{role}.webp'), lossless=True)
    if '--preview' in sys.argv:
        path = sys.argv[sys.argv.index('--preview') + 1]
        rows = len(styles) * 2
        sheet = Image.new('RGBA', (12 * 96, rows * 96), (0, 0, 0, 255))
        sq = ImageDraw.Draw(sheet)
        for r in range(rows):
            for c in range(12):
                light = (r + c) % 2 == 0
                sq.rectangle([c * 96, r * 96, c * 96 + 95, r * 96 + 95],
                             fill=(240, 217, 181) if light else (181, 136, 99))
        # One row per style and colour; each piece twice, so it shows on
        # both a light and a dark square.
        for i, image in enumerate(previews):
            style_i, rest = divmod(i, 12)
            color_i, role_i = divmod(rest, 6)
            row = style_i * 2 + color_i
            sheet.alpha_composite(image, (role_i * 96, row * 96))
            sheet.alpha_composite(image, ((role_i + 6) * 96, row * 96))
        sheet.save(path)


if __name__ == '__main__':
    main()
