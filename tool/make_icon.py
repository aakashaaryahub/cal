"""Draws the VoxLink app icon: white sound bars on the pink-to-violet brand gradient."""
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops

# Run from the project root: python tool/make_icon.py assets/icon
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

SIZE = 1024
SS = 4  # supersampling for smooth edges
PINK = (0xFF, 0x4D, 0x8D)
VIOLET = (0x7B, 0x5C, 0xFF)
BARS = [0.40, 0.70, 1.0, 0.70, 0.40]  # relative heights, tallest in the middle


def gradient(size):
    """Diagonal brand gradient, top-left pink to bottom-right violet, with a soft light."""
    small = 256
    g = Image.new('RGB', (small, small))
    px = g.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(PINK, VIOLET))
    g = g.resize((size, size), Image.BICUBIC)
    # Gentle glow in the upper left so the flat gradient has some depth.
    glow = Image.new('L', (size, size), 0)
    ImageDraw.Draw(glow).ellipse([-size * 0.35, -size * 0.45, size * 0.75, size * 0.55], fill=34)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.14))
    white = Image.new('RGB', (size, size), (255, 255, 255))
    return Image.composite(white, g, glow)


def bars_mask(size, span):
    """White bars as an alpha mask; `span` is the tallest bar's height as a share of `size`."""
    s = size * SS
    m = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(m)
    tallest = s * span
    width = tallest * 0.155
    gap = width * 0.62
    total = len(BARS) * width + (len(BARS) - 1) * gap
    x = (s - total) / 2
    for h in BARS:
        bh = tallest * h
        top = (s - bh) / 2
        d.rounded_rectangle([x, top, x + width, top + bh], radius=width / 2, fill=255)
        x += width + gap
    return m.resize((size, size), Image.LANCZOS)


def with_bars(base, span, shadow=True):
    size = base.size[0]
    mask = bars_mask(size, span)
    out = base.convert('RGBA')
    if shadow:
        # Soft violet shadow just below the bars.
        sh = mask.filter(ImageFilter.GaussianBlur(size * 0.022))
        sh = ImageChops.offset(sh, 0, round(size * 0.018)).point(lambda v: v * 0.45)
        out = Image.composite(Image.new('RGBA', (size, size), (60, 20, 120, 255)), out, sh)
    out = Image.composite(Image.new('RGBA', (size, size), (255, 255, 255, 255)), out, mask)
    return out


bg = gradient(SIZE)

# Full-bleed square: iOS (it rounds the corners itself) and legacy Android icons.
with_bars(bg, span=0.48).convert('RGB').save(os.path.join(OUT, 'icon.png'))

# Android adaptive icon layers. The launcher crops the 108dp canvas to as little
# as a 66dp circle, so the bars stay well inside the middle.
bg.save(os.path.join(OUT, 'icon_background.png'))
ADAPTIVE_SPAN = 0.31
mask = bars_mask(SIZE, ADAPTIVE_SPAN)
white = Image.new('RGBA', (SIZE, SIZE), (255, 255, 255, 255))
white.putalpha(mask)
# Foreground: white bars plus the same soft shadow, on transparency.
sh = mask.filter(ImageFilter.GaussianBlur(SIZE * 0.016))
sh = ImageChops.offset(sh, 0, round(SIZE * 0.013)).point(lambda v: v * 0.45)
fg = Image.new('RGBA', (SIZE, SIZE), (60, 20, 120, 0))
fg.putalpha(sh)
fg = Image.alpha_composite(fg, white)
fg.save(os.path.join(OUT, 'icon_foreground.png'))
# Android 13 themed icons: shape only, recolored by the system.
white.save(os.path.join(OUT, 'icon_monochrome.png'))

# Preview: how it looks as a rounded app icon and as an adaptive circle.
prev = Image.new('RGB', (1500, 640), (18, 18, 32))
sq = with_bars(bg, 0.48).resize((480, 480), Image.LANCZOS)
rmask = Image.new('L', (480 * SS, 480 * SS), 0)
ImageDraw.Draw(rmask).rounded_rectangle([0, 0, 480 * SS, 480 * SS], radius=480 * SS * 0.22, fill=255)
prev.paste(sq, (60, 80), rmask.resize((480, 480), Image.LANCZOS))
adaptive = Image.alpha_composite(bg.convert('RGBA'), fg).resize((480, 480), Image.LANCZOS)
cmask = Image.new('L', (480 * SS, 480 * SS), 0)
# 72/108 of the canvas is what a circular launcher shows.
inset = 480 * SS * (1 - 72 / 108) / 2
ImageDraw.Draw(cmask).ellipse([inset, inset, 480 * SS - inset, 480 * SS - inset], fill=255)
cm = cmask.resize((480, 480), Image.LANCZOS)
adaptive_big = adaptive.resize((round(480 * 108 / 72),) * 2, Image.LANCZOS)
off = (adaptive_big.size[0] - 480) // 2
circle = adaptive_big.crop((off, off, off + 480, off + 480))
cm_full = Image.new('L', (480 * SS, 480 * SS), 0)
ImageDraw.Draw(cm_full).ellipse([0, 0, 480 * SS, 480 * SS], fill=255)
prev.paste(circle.convert('RGB'), (580, 80), cm_full.resize((480, 480), Image.LANCZOS))
small = with_bars(bg, 0.48).resize((96, 96), Image.LANCZOS)
sm = Image.new('L', (96 * SS, 96 * SS), 0)
ImageDraw.Draw(sm).rounded_rectangle([0, 0, 96 * SS, 96 * SS], radius=96 * SS * 0.22, fill=255)
prev.paste(small, (1160, 272), sm.resize((96, 96), Image.LANCZOS))
tiny = with_bars(bg, 0.48).resize((48, 48), Image.LANCZOS)
tm = Image.new('L', (48 * SS, 48 * SS), 0)
ImageDraw.Draw(tm).rounded_rectangle([0, 0, 48 * SS, 48 * SS], radius=48 * SS * 0.22, fill=255)
prev.paste(tiny, (1300, 296), tm.resize((48, 48), Image.LANCZOS))
prev.save(os.path.join(OUT, 'preview.png'))
print('ok')
