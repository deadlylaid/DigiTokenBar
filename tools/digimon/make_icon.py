"""Build assets/AppIcon.icns for DigiTokenBar.

The icon is the plain spotted egg the app draws before hatching (DigimonEggArt in
Sources/PokeTokenBar/Digimon/DigimonSprites.swift), on the pet scene's sky and ground.
It is drawn here in code; no Digimon artwork is used.

Usage: python3 -I tools/digimon/make_icon.py   (needs Pillow and macOS iconutil)
"""
import math
import pathlib
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "AppIcon.icns"

SPOT = (242, 140, 62)   # Agumon line egg color (DigimonLine.eggColorHex F28C3E)
RIM = (194, 112, 50)    # 0.8x, as DigimonEggArt.colors does
SKY_TOP, SKY_BOTTOM, GROUND = (232, 240, 251), (248, 244, 234), (235, 227, 207)


def draw_egg(size=64):
    """Same pixels as DigimonEggArt.bitmap(size: 64)."""
    rx, ry = 11 * size / 64, 14 * size / 64
    cx = (size - 1) / 2
    cy = size - 1 - ry + 0.5

    def inside(px, py):
        dy = (py - cy) / ry
        k = 1 - 0.22 * (-dy) if py < cy else 1
        dx = (px - cx) / (rx * k)
        return dx * dx + dy * dy <= 1

    spots = [(-0.41, -0.32, 0.25), (0.45, 0.21, 0.31), (-0.64, 0.46, 0.2), (0.5, -0.64, 0.18)]
    im = Image.new("RGBA", (size, size))
    for py in range(size):
        for px in range(size):
            if not inside(px, py):
                continue
            edge = not (inside(px - 1, py) and inside(px + 1, py) and inside(px, py - 1) and inside(px, py + 1))
            nx, ny = (px - cx) / rx, (py - cy) / ry
            col = (231, 221, 199) if nx * 0.6 + ny * 0.8 > 0.55 else (251, 246, 234)
            for ox, oy, r in spots:
                d = math.hypot(px - (cx + ox * rx), py - (cy + oy * ry))
                rr = max(r * rx, 1.0)
                if d <= rr:
                    col = RIM if d > rr - 1 else SPOT
            if -0.7 < nx < -0.3 and -0.75 < ny < -0.3:
                col = (255, 255, 255)
            if edge:
                col = (43, 43, 53)
            im.putpixel((px, py), col + (255,))
    return im.crop(im.getbbox())


def icon_1024():
    S = 1024
    inset, side, radius = 100, 824, 185          # macOS icon grid: 824 pt body, ~22% corner
    ground_y = inset + int(side * 0.78)
    body = Image.new("RGBA", (side, side))
    px = body.load()
    for y in range(side):
        gy = inset + y
        if gy >= ground_y:
            c = GROUND
        else:
            t = y / (ground_y - inset)
            c = tuple(round(SKY_TOP[i] + (SKY_BOTTOM[i] - SKY_TOP[i]) * t) for i in range(3))
        for x in range(side):
            px[x, y] = c + (255,)
    mask = Image.new("L", (side, side))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, side - 1, side - 1), radius=radius, fill=255)
    canvas = Image.new("RGBA", (S, S))
    canvas.paste(body, (inset, inset), mask)

    egg = draw_egg()
    scale = 18
    egg = egg.resize((egg.width * scale, egg.height * scale), Image.NEAREST)
    ex = (S - egg.width) // 2
    ey = ground_y + 26 - egg.height
    shadow = Image.new("RGBA", (S, S))
    ImageDraw.Draw(shadow).ellipse((ex + 40, ground_y + 6, ex + egg.width - 40, ground_y + 46), fill=(60, 50, 30, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(egg, (ex, ey))
    return canvas


def main():
    big = icon_1024()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for pt in (16, 32, 128, 256, 512):
            for mult in (1, 2):
                px = pt * mult
                name = f"icon_{pt}x{pt}{'@2x' if mult == 2 else ''}.png"
                big.resize((px, px), Image.LANCZOS).save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT)], check=True)
    print("wrote", OUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
