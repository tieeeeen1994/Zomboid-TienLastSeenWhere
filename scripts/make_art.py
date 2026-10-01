"""Builds the mod's icon, poster, Workshop preview and the floor arrow texture.

    python3 scripts/make_art.py

Needs Pillow. Reads from the local Project Zomboid install, writes:
  Contents/mods/TienLastSeenWhere/42/icon.png                                 128x128
  Contents/mods/TienLastSeenWhere/42/poster.png                               512x512
  Contents/mods/TienLastSeenWhere/42/media/textures/TienLastSeenWhere_Arrow.png  256x128
  preview.png                                                                  512x512
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MOD = os.path.join(REPO, "Contents", "mods", "TienLastSeenWhere", "42")
UI = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/"
    "Project Zomboid.app/Contents/Java/media/ui"
)

LENS = os.path.join(UI, "Sidebar", "128", "Search_On_128.png")

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


def main():
    textures = os.path.join(MOD, "media", "textures")
    os.makedirs(textures, exist_ok=True)
    arrow_texture().save(os.path.join(textures, "TienLastSeenWhere_Arrow.png"))
    art(128).convert("RGB").save(os.path.join(MOD, "icon.png"))
    poster = art(512).convert("RGB")
    poster.save(os.path.join(MOD, "poster.png"))
    poster.save(os.path.join(REPO, "preview.png"))
    print("Wrote the arrow texture, icon.png, poster.png and preview.png")


if __name__ == "__main__":
    main()
