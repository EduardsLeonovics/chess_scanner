"""Draws ChessGeek's own piece sets (Geo, Ink, Bubble) for chessground.

Every piece is built from simple shapes in a unit square (x right, y down),
rendered at 1024 px with an outline, then saved as WebP at chessground's
sizes (128 px base plus 2.0x, 3.0x and 4.0x). These sets are original work
released with the app under the GPL, so they're safe in an ad-supported app.

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
# Ink: slender classical shapes, two-tier base, banded details.

def ink(role):
    base = [rrect(0.25, 0.83, 0.75, 0.90, 0.03), rrect(0.30, 0.77, 0.70, 0.84, 0.02)]
    bands = [line((0.31, 0.835), (0.69, 0.835), w=0.014)]
    if role == 'P':
        return base + [flare(0.53, 0.78, 0.055, 0.17), ellipse(0.5, 0.53, 0.115, 0.03),
                       ellipse(0.5, 0.40, 0.10)], bands + [line((0.36, 0.53), (0.64, 0.53), w=0.012)]
    if role == 'R':
        top = poly((0.31, 0.19), (0.39, 0.19), (0.39, 0.25), (0.46, 0.25), (0.46, 0.19), (0.54, 0.19),
                   (0.54, 0.25), (0.61, 0.25), (0.61, 0.19), (0.69, 0.19), (0.67, 0.36), (0.33, 0.36))
        return base + [top, poly((0.36, 0.36), (0.64, 0.36), (0.66, 0.77), (0.34, 0.77))], bands + [
            line((0.35, 0.36), (0.65, 0.36), w=0.014), line((0.35, 0.68), (0.65, 0.68), w=0.012)]
    if role == 'B':
        return base + [flare(0.58, 0.78, 0.06, 0.17), ellipse(0.5, 0.57, 0.13, 0.03),
                       mitre(0.18, 0.57, 0.125), ellipse(0.5, 0.15, 0.04)], bands + [
            line((0.46, 0.42), (0.56, 0.30), w=0.016), line((0.37, 0.57), (0.63, 0.57), w=0.012)]
    if role == 'N':
        head = poly((0.33, 0.77), (0.36, 0.62), (0.45, 0.53), (0.37, 0.52), (0.27, 0.50), (0.21, 0.45),
                    (0.22, 0.39), (0.30, 0.33), (0.38, 0.25), (0.40, 0.14), (0.46, 0.20), (0.50, 0.15),
                    (0.55, 0.22), (0.65, 0.27), (0.71, 0.40), (0.72, 0.58), (0.69, 0.77))
        return base + [head], bands + [
            ('ellipse', (0.37, 0.33, 0.02, 0.02)), line((0.25, 0.44), (0.29, 0.44), w=0.012),
            line((0.56, 0.26), (0.64, 0.34), (0.67, 0.48), (0.66, 0.62), w=0.012)]
    if role == 'Q':
        crown = poly((0.30, 0.26), (0.39, 0.42), (0.43, 0.22), (0.5, 0.40), (0.57, 0.22), (0.61, 0.42),
                     (0.70, 0.26), (0.64, 0.50), (0.36, 0.50))
        balls = [ellipse(x, y, 0.03) for x, y in ((0.30, 0.24), (0.43, 0.19), (0.57, 0.19), (0.70, 0.24))]
        return base + [poly((0.40, 0.50), (0.60, 0.50), (0.66, 0.77), (0.34, 0.77)), crown,
                       ellipse(0.5, 0.15, 0.04)] + balls, bands + [
            line((0.37, 0.50), (0.63, 0.50), w=0.014), line((0.36, 0.69), (0.64, 0.69), w=0.012)]
    if role == 'K':
        return base + [poly((0.40, 0.46), (0.60, 0.46), (0.66, 0.77), (0.34, 0.77)),
                       poly((0.33, 0.33), (0.67, 0.33), (0.62, 0.47), (0.38, 0.47)),
                       rrect(0.475, 0.09, 0.525, 0.33), rrect(0.42, 0.15, 0.58, 0.20)], bands + [
            line((0.37, 0.47), (0.63, 0.47), w=0.014), line((0.36, 0.69), (0.64, 0.69), w=0.012),
            line((0.36, 0.40), (0.64, 0.40), w=0.012)]


# ---------------------------------------------------------------------------
# Bubble: chunky, rounded, glossy.

def bubble(role):
    base = [rrect(0.20, 0.74, 0.80, 0.90, 0.07)]
    if role == 'P':
        return base + [ellipse(0.5, 0.64, 0.17, 0.14), ellipse(0.5, 0.38, 0.15)], []
    if role == 'R':
        return base + [rrect(0.30, 0.38, 0.70, 0.78, 0.05), rrect(0.24, 0.16, 0.76, 0.42, 0.07)], [
            line((0.42, 0.17), (0.42, 0.26), w=0.04), line((0.58, 0.17), (0.58, 0.26), w=0.04)]
    if role == 'B':
        return base + [ellipse(0.5, 0.68, 0.16, 0.10), mitre(0.14, 0.64, 0.18), ellipse(0.5, 0.13, 0.055)], [
            line((0.46, 0.45), (0.57, 0.32), w=0.035)]
    if role == 'N':
        head = poly((0.28, 0.78), (0.32, 0.60), (0.40, 0.54), (0.28, 0.54), (0.19, 0.50), (0.17, 0.40),
                    (0.26, 0.31), (0.38, 0.24), (0.42, 0.13), (0.50, 0.21), (0.62, 0.22), (0.74, 0.33),
                    (0.79, 0.52), (0.76, 0.78))
        return base + [head, ellipse(0.24, 0.45, 0.075, 0.065)], [
            ('ellipse', (0.37, 0.33, 0.035, 0.035)), ('ellipse', (0.21, 0.44, 0.015, 0.015))]
    if role == 'Q':
        balls = [ellipse(x, y, 0.065) for x, y in ((0.25, 0.30), (0.40, 0.21), (0.60, 0.21), (0.75, 0.30))]
        return base + [rrect(0.27, 0.44, 0.73, 0.78, 0.09), poly((0.25, 0.30), (0.40, 0.22), (0.5, 0.40),
                                                                  (0.60, 0.22), (0.75, 0.30), (0.71, 0.50),
                                                                  (0.29, 0.50))] + balls, []
    if role == 'K':
        return base + [rrect(0.27, 0.40, 0.73, 0.78, 0.09), rrect(0.44, 0.08, 0.56, 0.42, 0.04),
                       rrect(0.34, 0.16, 0.66, 0.28, 0.04)], []


STYLES = {
    'geo': dict(make=geo, outline=0.022,
                colors={'w': ('#fbfbf8', '#1c1c1c', '#1c1c1c'), 'b': ('#2a2a2c', '#0b0b0b', '#e9e9e4')}),
    'ink': dict(make=ink, outline=0.014,
                colors={'w': ('#ffffff', '#111111', '#111111'), 'b': ('#1a1a1a', '#000000', '#f2f2f2')}),
    'bubble': dict(make=bubble, outline=0.03, gloss=True,
                   colors={'w': ('#fff6e3', '#3b2f22', '#3b2f22'), 'b': ('#33363d', '#111214', '#e8e6e0')}),
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

    if spec.get('gloss'):
        gloss = Image.new('L', (S, S), 0)
        ImageDraw.Draw(gloss).ellipse([px(0.28), px(0.10), px(0.52), px(0.40)], fill=110 if color == 'w' else 70)
        gloss = gloss.filter(ImageFilter.GaussianBlur(px(0.04)))
        out.paste('#ffffff', (0, 0), ImageChops.multiply(gloss, mask))

    layer = Image.new('L', (S, S), 0)
    dl = ImageDraw.Draw(layer)
    for shape in details:
        draw_shape(dl, shape, 255)
    out.paste(detail, (0, 0), ImageChops.multiply(layer, mask))
    return out


def main():
    previews = []
    for style in STYLES:
        for color in 'wb':
            for role in 'KQRBNP':
                image = render(style, color, role)
                previews.append(image.resize((96, 96), Image.LANCZOS))
                for folder, size in SIZES.items():
                    target = os.path.join(OUT, style, folder)
                    os.makedirs(target, exist_ok=True)
                    image.resize((size, size), Image.LANCZOS).save(
                        os.path.join(target, f'{color}{role}.webp'), lossless=True)
    if '--preview' in sys.argv:
        path = sys.argv[sys.argv.index('--preview') + 1]
        rows = len(STYLES) * 2
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
