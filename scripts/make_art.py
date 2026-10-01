"""Builds the mod's icon, poster, Workshop preview and the floor arrow texture.

    python3 scripts/make_art.py

Needs Pillow. Reads from the local Project Zomboid install, writes:
  Contents/mods/TienLastSeenWhere/42/icon.png                                 128x128
  Contents/mods/TienLastSeenWhere/42/poster.png                               512x512
  Contents/mods/TienLastSeenWhere/42/media/textures/TienLastSeenWhere_Arrow.png  256x128
  Contents/mods/TienLastSeenWhere/42/media/ui/Sidebar/<size>/TienLastSeenWhere_Off|On_<size>.png
                                   sidebar button (a map pin with an eye, drawn here),
                                   48/64/80/96/128 wide like the game's own
  preview.png                                                                  512x512
"""

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MOD = os.path.join(REPO, "Contents", "mods", "TienLastSeenWhere", "42")
UI = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/"
    "Project Zomboid.app/Contents/Java/media/ui"
)

LENS = os.path.join(UI, "Sidebar", "128", "Search_On_128.png")
SIDEBAR_SIZES = (48, 64, 80, 96, 128)

BG_TOP = (40, 46, 38)
BG_BOTTOM = (14, 16, 13)
TILE_A = (78, 92, 70)
TILE_B = (86, 101, 77)
TILE_LINE = (58, 70, 53)
ARROW = (255, 215, 80)
ARROW_RIM = (255, 242, 180)
GLOW = (255, 214, 140)

ARROW_SHAPE = [(0.0, 0.36), (0.56, 0.36), (0.56, 0.06), (1.0, 0.5), (0.56, 0.94), (0.56, 0.64), (0.0, 0.64)]


def load(path):
    if not os.path.exists(path):
        raise SystemExit("Missing game image: " + path)
    return Image.open(path).convert("RGBA")


def trim(img):
    box = img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    return img.crop(box) if box else img


def backdrop(size):
    img = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)) + (255,))
    return img


def glow(size, cx, cy, radius, alpha):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=GLOW + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.45))


def shadow(img, blur, alpha):
    mask = img.getchannel("A").point(lambda a: a * alpha // 255)
    black = Image.new("RGBA", img.size, (0, 0, 0, 0))
    black.putalpha(mask)
    pad = blur * 3
    out = Image.new("RGBA", (img.width + pad * 2, img.height + pad * 2), (0, 0, 0, 0))
    out.alpha_composite(black, (pad, pad))
    return out.filter(ImageFilter.GaussianBlur(blur)), pad


def arrow_texture():
    scale = 4
    w, h = 256 * scale, 128 * scale
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    margin = 10 * scale
    pts = [(margin + u * (w - 2 * margin), margin + v * (h - 2 * margin)) for u, v in ARROW_SHAPE]
    d.polygon(pts, fill=(255, 255, 255, 235), outline=(0, 0, 0, 200), width=6 * scale)
    return img.resize((256, 128), Image.LANCZOS)


def iso(cx, cy, tile, x, y):
    return cx + (x - y) * tile / 2, cy + (x + y) * tile / 4


def floor_scene(size, cx, cy, tile, radius):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for gx in range(-radius, radius + 1):
        for gy in range(-radius, radius + 1):
            if abs(gx) + abs(gy) > radius:
                continue
            corners = [iso(cx, cy, tile, gx + a, gy + b) for a, b in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5))]
            d.polygon(corners, fill=(TILE_A if (gx + gy) % 2 else TILE_B) + (255,), outline=TILE_LINE + (255,))
    angle = math.atan2(-1, 0.2)
    c, s = math.cos(angle), math.sin(angle)
    length, half = 2.4, 0.75
    shape = [((u - 0.25) * length, (v - 0.5) * 2 * half) for u, v in ARROW_SHAPE]
    pts = [iso(cx, cy, tile, u * c - v * s, u * s + v * c) for u, v in shape]
    d.polygon(pts, fill=ARROW + (235,), outline=ARROW_RIM + (255,), width=max(2, size // 128))
    return layer


def art(size):
    img = backdrop(size)
    tile = size * 0.22
    img.alpha_composite(floor_scene(size, size * 0.5, size * 0.66, tile, 3))
    lens = trim(load(LENS))
    target = round(size * 0.5)
    lens = lens.resize((target, round(lens.height * target / lens.width)), Image.LANCZOS)
    lx = round(size * 0.12)
    ly = round(size * 0.1)
    img.alpha_composite(glow(size, lx + lens.width // 2, ly + lens.height // 2, round(lens.width * 0.55), 90))
    sh, pad = shadow(lens, max(2, size // 64), 150)
    img.alpha_composite(sh, (lx - pad + size // 80, ly - pad + size // 50))
    img.alpha_composite(lens, (lx, ly))
    return img


SS = 4


def blend(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def vertical_gradient(size, top, bottom):
    img = Image.new("RGBA", size)
    d = ImageDraw.Draw(img)
    for y in range(size[1]):
        d.line([(0, y), (size[0], y)], fill=blend(top, bottom, y / max(1, size[1] - 1)) + (255,))
    return img


def grow(mask, px):
    """Round dilation (a disk, not a square): a square kernel turns the outline round a sharp
    tip into a flat, boxy end."""
    out = mask.copy()
    steps = max(24, px * 6)
    for i in range(steps):
        angle = 2 * math.pi * i / steps
        for radius in (px, px * 0.5):
            dx, dy = round(math.cos(angle) * radius), round(math.sin(angle) * radius)
            out = ImageChops.lighter(out, ImageChops.offset(mask, dx, dy))
    return out


def solid(size, colour):
    return Image.new("RGBA", size, colour)


def sidebar_icon(size, state):
    """A map pin with an eye, drawn in the sidebar's style: grey when off, coloured when on,
    outlined like the game's sidebar icons (a thin white line outside a black one)."""
    on = state == "On"
    w, h = size * SS, int(size * 0.75) * SS
    full = (w, h)
    img = Image.new("RGBA", full, (0, 0, 0, 0))
    cx = w / 2
    stroke = max(SS, round(size * SS / 56))
    pad = stroke * 2 + SS * 3
    top, tip = pad, h - pad
    r = 0.41 * (tip - top)
    cy = top + r

    mask = Image.new("L", full, 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    angle = math.asin(r / (tip - cy))
    d.polygon([(cx - r * math.cos(angle), cy + r * math.sin(angle)),
               (cx + r * math.cos(angle), cy + r * math.sin(angle)), (cx, tip)], fill=255)

    img.paste(solid(full, (255, 255, 255, 255)), (0, 0), grow(mask, stroke * 2))
    img.paste(solid(full, (12, 12, 12, 255)), (0, 0), grow(mask, stroke))
    if on:
        body = vertical_gradient(full, (238, 120, 70), (160, 45, 30))
    else:
        body = vertical_gradient(full, (215, 215, 215), (120, 120, 120))
    img.paste(body, (0, 0), mask)
    shine = Image.new("L", full, 0)
    ImageDraw.Draw(shine).ellipse([cx - r * 0.85, cy - r * 0.9, cx + r * 0.1, cy - r * 0.05], fill=70)
    shine = ImageChops.multiply(shine.filter(ImageFilter.GaussianBlur(3 * SS)), mask)
    img.paste(solid(full, (255, 255, 255, 255)), (0, 0), shine)

    ew, eh = r * 0.78, r * 0.46
    eye = Image.new("L", full, 0)
    outline = []
    for i in range(41):
        t = -1 + i / 20
        outline.append((cx + t * ew, cy - eh * (1 - t * t) ** 0.9))
    for i in range(41):
        t = 1 - i / 20
        outline.append((cx + t * ew, cy + eh * (1 - t * t) ** 0.9))
    ImageDraw.Draw(eye).polygon(outline, fill=255)
    img.paste(solid(full, (12, 12, 12, 255)), (0, 0), grow(eye, stroke))
    img.paste(solid(full, (250, 250, 250, 255) if on else (235, 235, 235, 255)), (0, 0), eye)

    ir = eh * 0.95
    iris = Image.new("L", full, 0)
    ImageDraw.Draw(iris).ellipse([cx - ir, cy - ir, cx + ir, cy + ir], fill=255)
    iris = ImageChops.multiply(iris, eye)
    if on:
        iris_fill = vertical_gradient(full, (120, 220, 235), (40, 130, 170))
    else:
        iris_fill = vertical_gradient(full, (170, 170, 170), (90, 90, 90))
    img.paste(iris_fill, (0, 0), iris)
    d = ImageDraw.Draw(img)
    pr = ir * 0.45
    d.ellipse([cx - pr, cy - pr, cx + pr, cy + pr], fill=(20, 20, 20, 255))
    gr = ir * 0.22
    gx, gy = cx - ir * 0.45, cy - ir * 0.45
    d.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=(255, 255, 255, 230))
    return img.resize((size, int(size * 0.75)), Image.LANCZOS)


def main():
    for size in SIDEBAR_SIZES:
        folder = os.path.join(MOD, "media", "ui", "Sidebar", str(size))
        os.makedirs(folder, exist_ok=True)
        for state in ("Off", "On"):
            sidebar_icon(size, state).save(os.path.join(folder, "TienLastSeenWhere_%s_%d.png" % (state, size)))
    textures = os.path.join(MOD, "media", "textures")
    os.makedirs(textures, exist_ok=True)
    arrow_texture().save(os.path.join(textures, "TienLastSeenWhere_Arrow.png"))
    art(128).convert("RGB").save(os.path.join(MOD, "icon.png"))
    poster = art(512).convert("RGB")
    poster.save(os.path.join(MOD, "poster.png"))
    poster.save(os.path.join(REPO, "preview.png"))
    print("Wrote the sidebar icons, the arrow texture, icon.png, poster.png and preview.png")


if __name__ == "__main__":
    main()
