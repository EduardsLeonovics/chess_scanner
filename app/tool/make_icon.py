"""Draws the ChessGeek app icon: an exact 8x8 board under a magnifying glass.

The geometry is redrawn from scratch; the knight silhouette is taken from
the original artwork (screenshots/5.png). Outputs:

  app/assets/icon/app_icon.png             1024 full-bleed (iOS, legacy Android)
  app/assets/icon/app_icon_foreground.png  1024 transparent, for the Android
                                           adaptive icon (board inside the safe zone)
  branding/play_store_icon_512.png         Google Play listing icon
  branding/app_store_icon_1024.png         App Store listing icon

    python app/tool/make_icon.py
    dart run flutter_launcher_icons      (from app/)
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "screenshots" / "5.png"
ICON_DIR = ROOT / "app" / "assets" / "icon"
BRANDING = ROOT / "branding"

BLUE = (73, 176, 253)  # #49B0FD
LIGHT = (246, 251, 254)  # #F6FBFE

SIZE = 1024
SS = 4  # supersampling factor for smooth edges
S = SIZE * SS

# Layout as fractions of the icon size, measured from the original artwork.
MARGIN = 0.0625  # blue frame around the board
BOARD_RADIUS = 0.16  # rounded board corners
LENS_CENTER = (0.496, 0.463)
RING_OUTER = 0.213  # white ring, outer radius
RING_WIDTH = 0.038
GAP = 0.02  # blue gap between ring and board
HANDLE_ANGLE = 45  # degrees, towards bottom-right
HANDLE_START = 0.235  # from lens centre
HANDLE_END = 0.43
HANDLE_WIDTH = 0.058
NECK_WIDTH = 0.034

# The original's frame is ~895 px wide, so knight pixels scale by this much.
ORIGINAL_FRAME = 895
ORIGINAL_LENS_CENTER = (624, 594)
ORIGINAL_LENS_RADIUS = 150


def px(f):
    return f * S


def knight_mask():
    """White knight silhouette from the original, as an alpha mask at S scale."""
    im = np.asarray(Image.open(SOURCE).convert("RGB")).astype(float)
    cx, cy = ORIGINAL_LENS_CENTER
    r = ORIGINAL_LENS_RADIUS
    crop = im[cy - r : cy + r, cx - r : cx + r]
    # Whiteness: 0 at the lens blue, 1 at the light colour (keeps anti-aliasing).
    blue, light = np.array(BLUE, float), np.array(LIGHT, float)
    t = ((crop - blue) @ (light - blue)) / ((light - blue) @ (light - blue))
    t = np.clip(t, 0, 1)
    yy, xx = np.mgrid[-r:r, -r:r]
    t[np.hypot(xx, yy) > r - 4] = 0  # stay inside the lens
    scale = SIZE / ORIGINAL_FRAME * SS
    mask = Image.fromarray((t * 255).astype(np.uint8)).resize(
        (round(2 * r * scale),) * 2, Image.LANCZOS
    )
    # Re-sharpen the upscaled edge into a clean ~1 px ramp.
    mask = mask.filter(ImageFilter.GaussianBlur(SS * 0.6))
    a = np.asarray(mask).astype(float) / 255
    a = np.clip((a - 0.5) * 2.2 + 0.5, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8))


def rounded_mask(box, radius):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def draw_icon(frame=True):
    """The icon; without [frame] only the board and magnifier, on transparency."""
    # Transparent pixels carry the blue so edges don't fringe dark when resized.
    img = Image.new("RGBA", (S, S), (*BLUE, 255 if frame else 0))

    # 8x8 board, a8 (top-left) light like a real board.
    x0 = y0 = px(MARGIN)
    side = S - 2 * x0
    sq = side / 8
    board = Image.new("RGBA", (S, S), (*BLUE, 255))
    d = ImageDraw.Draw(board)
    for row in range(8):
        for col in range(8):
            if (row + col) % 2 == 0:
                d.rectangle(
                    [x0 + col * sq, y0 + row * sq, x0 + (col + 1) * sq - 1, y0 + (row + 1) * sq - 1],
                    fill=LIGHT,
                )
    img.paste(board, (0, 0), rounded_mask([x0, y0, x0 + side - 1, y0 + side - 1], px(BOARD_RADIUS)))

    d = ImageDraw.Draw(img)
    cx, cy = px(LENS_CENTER[0]), px(LENS_CENTER[1])
    ux, uy = np.cos(np.radians(HANDLE_ANGLE)), np.sin(np.radians(HANDLE_ANGLE))

    def handle(width, start, end, colour):
        w = px(width)
        a = (cx + ux * px(start), cy + uy * px(start))
        b = (cx + ux * px(end), cy + uy * px(end))
        d.line([a, b], fill=colour, width=round(w))
        for p in (a, b):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=colour)

    def circle(radius, colour):
        r = px(radius)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=colour)

    gap = GAP
    # Blue outline (the gap) behind ring and handle, then the white shapes.
    handle(HANDLE_WIDTH + 2 * gap, HANDLE_START, HANDLE_END, BLUE)
    circle(RING_OUTER + gap, BLUE)
    handle(NECK_WIDTH, RING_OUTER - 0.01, HANDLE_START + 0.02, LIGHT)
    handle(HANDLE_WIDTH, HANDLE_START, HANDLE_END, LIGHT)
    circle(RING_OUTER, LIGHT)
    circle(RING_OUTER - RING_WIDTH, BLUE)

    knight = knight_mask()
    kx, ky = round(cx - knight.width / 2), round(cy - knight.height / 2)
    img.paste(Image.new("RGBA", knight.size, (*LIGHT, 255)), (kx, ky), knight)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    BRANDING.mkdir(parents=True, exist_ok=True)
    icon = draw_icon().convert("RGB")
    icon.save(ICON_DIR / "app_icon.png")
    icon.save(BRANDING / "app_store_icon_1024.png")
    icon.resize((512, 512), Image.LANCZOS).save(BRANDING / "play_store_icon_512.png")

    # Adaptive icon: launchers mask the outer third, so shrink the artwork
    # until the whole board sits inside the always-visible circle. No frame:
    # the background layer supplies the blue around it.
    fg = Image.new("RGBA", (SIZE, SIZE), (*BLUE, 0))
    small = draw_icon(frame=False).resize((round(SIZE * 0.54),) * 2, Image.LANCZOS)
    offset = (SIZE - small.width) // 2
    fg.paste(small, (offset, offset))
    fg.save(ICON_DIR / "app_icon_foreground.png")
    print("icons written to", ICON_DIR, "and", BRANDING)


if __name__ == "__main__":
    main()
