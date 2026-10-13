#!/usr/bin/env python3
"""
Generate a plugin's WP.org icon + banners in the hdwebmobile house style (matches the
hand-made assets of the live plugins, e.g. Invoices & Packing Slips / Product Options):

  banner-1544x500.png, banner-772x250.png  green diagonal gradient, ringed gradient disc with a
                                           white glyph on the left, bold uppercase title (ending
                                           in a period) + one-line tagline on the right
  icon-256x256.png, icon-128x128.png       white background, the same disc + glyph, title below
                                           in dark green

Screenshots are NOT generated here -- they are real wp-admin/storefront captures.

Usage:
  make-assets.py --slug hdwebmobile-foo --title "LOYALTY POINTS &|STORE CREDIT." \
      --tagline "Points customers earn and redeem. Balance computed from a ledger." --glyph star
  (| splits title lines; glyphs: star, coin, gift, tag, doc, check, cart, clock, calendar, calculator, user, shield)
"""
import argparse, math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

BOLD = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
REG = '/System/Library/Fonts/Supplemental/Arial.ttf'
BG_TL, BG_BR = (96, 178, 158), (2, 70, 55)        # banner background corners (sampled)
DISC_TL, DISC_BR = (78, 158, 139), (2, 70, 55)     # disc gradient (sampled)
RING = (255, 255, 255, 110)                        # pale ring
DARK = (2, 70, 55)
SS = 2                                             # supersampling factor


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def diag_gradient(w, h, c0, c1, power=0.8):
    """Top-left c0 -> bottom-right c1, reaching c1 well before the far corner (like the originals)."""
    img = Image.new('RGB', (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = min(1.0, ((x / w) * 0.85 + (y / h) * 0.35) / 0.75)
            px[x, y] = lerp(c0, c1, t ** power)
    return img


def disc(size):
    """Gradient-filled circle (RGBA) of diameter `size`."""
    g = Image.new('RGB', (size, size))
    px = g.load()
    for y in range(size):
        for x in range(size):
            t = min(1.0, max(0.0, (x + y) / (2 * size) * 1.6 - 0.15))
            px[x, y] = lerp(DISC_TL, DISC_BR, t)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(g, (0, 0), mask)
    return out


def draw_glyph(d, name, cx, cy, r, fill=(255, 255, 255), cut=DARK):
    """White pictogram centred at (cx, cy), roughly r px in 'radius'."""
    if name == 'star':
        pts = []
        for i in range(10):
            ang = -math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.42
            pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
        d.polygon(pts, fill=fill)
    elif name == 'coin':
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
        d.ellipse((cx - r * .72, cy - r * .72, cx + r * .72, cy + r * .72), outline=cut, width=max(2, int(r * .08)))
        draw_glyph(d, 'star', cx, cy, r * .45, fill=cut)
    elif name == 'gift':
        d.rectangle((cx - r * .85, cy - r * .2, cx + r * .85, cy + r * .9), fill=fill)
        d.rectangle((cx - r * .95, cy - r * .5, cx + r * .95, cy - r * .2), fill=fill)
        d.rectangle((cx - r * .1, cy - r * .5, cx + r * .1, cy + r * .9), fill=cut)
    elif name == 'tag':
        d.polygon([(cx - r, cy), (cx - r * .4, cy - r * .7), (cx + r, cy - r * .7), (cx + r, cy + r * .7), (cx - r * .4, cy + r * .7)], fill=fill)
        d.ellipse((cx - r * .55, cy - r * .12, cx - r * .31, cy + r * .12), fill=cut)
    elif name == 'doc':
        d.polygon([(cx - r * .7, cy - r), (cx + r * .25, cy - r), (cx + r * .7, cy - r * .55), (cx + r * .7, cy + r), (cx - r * .7, cy + r)], fill=fill)
        for k in range(3):
            y = cy - r * .1 + k * r * .3
            d.rectangle((cx - r * .45, y, cx + r * (.45 if k < 2 else .1), y + r * .07), fill=cut)
    elif name == 'check':
        w = int(r * .32)
        d.line([(cx - r * .8, cy), (cx - r * .2, cy + r * .6), (cx + r * .85, cy - r * .6)], fill=fill, width=w, joint='curve')
    elif name == 'cart':
        d.polygon([(cx - r, cy - r * .7), (cx - r * .6, cy - r * .7), (cx - r * .35, cy + r * .35), (cx + r * .8, cy + r * .35), (cx + r, cy - r * .45), (cx - r * .5, cy - r * .45)], fill=fill)
        for wx in (-.25, .6):
            d.ellipse((cx + r * wx - r * .15, cy + r * .5, cx + r * wx + r * .15, cy + r * .8), fill=fill)
    elif name == 'clock':
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
        w = max(3, int(r * .12))
        d.line([(cx, cy), (cx, cy - r * .65)], fill=cut, width=w)
        d.line([(cx, cy), (cx + r * .45, cy + r * .2)], fill=cut, width=w)
    elif name == 'calendar':
        d.rounded_rectangle((cx - r * .85, cy - r * .7, cx + r * .85, cy + r * .85), radius=r * .12, fill=fill)
        d.rectangle((cx - r * .85, cy - r * .7, cx + r * .85, cy - r * .35), fill=fill)
        d.rectangle((cx - r * .72, cy - r * .22, cx + r * .72, cy + r * .72), fill=cut)
        for rx in (-.45, .45):
            d.rounded_rectangle((cx + r * rx - r * .08, cy - r * .95, cx + r * rx + r * .08, cy - r * .55), radius=r * .05, fill=fill)
        w = max(3, int(r * .14))
        d.line([(cx - r * .35, cy + r * .25), (cx - r * .08, cy + r * .5), (cx + r * .4, cy - r * .02)], fill=fill, width=w, joint='curve')
    elif name == 'calculator':
        d.rounded_rectangle((cx - r * .72, cy - r, cx + r * .72, cy + r), radius=r * .14, fill=fill)
        d.rounded_rectangle((cx - r * .54, cy - r * .82, cx + r * .54, cy - r * .38), radius=r * .06, fill=cut)
        k = r * .26
        for row in range(3):
            for col in range(3):
                x0 = cx - r * .54 + col * (k + r * .14)
                y0 = cy - r * .2 + row * (k + r * .1)
                d.rounded_rectangle((x0, y0, x0 + k, y0 + k), radius=r * .05, fill=cut)
    elif name == 'user':
        d.ellipse((cx - r * .4, cy - r, cx + r * .4, cy - r * .2), fill=fill)
        d.pieslice((cx - r * .85, cy - r * .1, cx + r * .85, cy + r * 1.5), 180, 360, fill=fill)
    elif name == 'shield':
        d.polygon([(cx, cy - r), (cx + r * .8, cy - r * .65), (cx + r * .7, cy + r * .3), (cx, cy + r), (cx - r * .7, cy + r * .3), (cx - r * .8, cy - r * .65)], fill=fill)
    else:
        sys.exit(f'unknown glyph {name}')


def fit_font(path, lines, max_w, start, draw):
    size = start
    while size > 10:
        f = ImageFont.truetype(path, size)
        if all(draw.textlength(l, font=f) <= max_w for l in lines):
            return f
        size -= 1
    return ImageFont.truetype(path, size)


def banner(title_lines, tagline, glyph):
    W, H = 1544 * SS, 500 * SS
    img = diag_gradient(1544, 500, BG_TL, BG_BR).resize((W, H), Image.BICUBIC).convert('RGBA')
    cx, cy = 322 * SS, 250 * SS
    # ring
    ring = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse((cx - 211 * SS, cy - 211 * SS, cx + 211 * SS, cy + 211 * SS), outline=RING, width=3 * SS)
    img = Image.alpha_composite(img, ring)
    dsc = disc(360 * SS)
    img.alpha_composite(dsc, (cx - 180 * SS, cy - 180 * SS))
    d = ImageDraw.Draw(img)
    draw_glyph(d, glyph, cx, cy, 92 * SS)
    # text block, vertically centred around y=250 like the originals
    x0, max_w = 615 * SS, (1544 - 615 - 70) * SS        # keep >= 70px right margin (clipping lesson)
    tf = fit_font(BOLD, title_lines, max_w, 66 * SS, d)
    gf = fit_font(REG, [tagline], max_w, 28 * SS, d)
    line_h = int(tf.size * 1.18)
    block = line_h * len(title_lines) + int(gf.size * 1.9)
    y = cy - block // 2 - 6 * SS
    for l in title_lines:
        d.text((x0, y), l, font=tf, fill=(255, 255, 255))
        y += line_h
    d.text((x0 + 4 * SS, y + int(gf.size * 0.55)), tagline, font=gf, fill=(240, 248, 246))
    return img.convert('RGB').resize((1544, 500), Image.LANCZOS)


def icon(title_lines, glyph):
    S = 256 * SS
    img = Image.new('RGBA', (S, S), (255, 255, 255, 255))
    dsc = disc(184 * SS)
    img.alpha_composite(dsc, ((S - 184 * SS) // 2, 12 * SS))
    d = ImageDraw.Draw(img)
    draw_glyph(d, glyph, S // 2, 12 * SS + 92 * SS, 46 * SS)
    f = fit_font(BOLD, title_lines, 236 * SS, 16 * SS, d)
    y = 204 * SS if len(title_lines) > 1 else 214 * SS
    for l in title_lines:
        w = d.textlength(l, font=f)
        d.text(((S - w) / 2, y), l, font=f, fill=DARK)
        y += int(f.size * 1.2)
    return img.convert('RGB').resize((256, 256), Image.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--slug', required=True)
    ap.add_argument('--title', required=True, help='uppercase, | between lines, end with a period')
    ap.add_argument('--tagline', required=True)
    ap.add_argument('--glyph', default='star')
    ap.add_argument('--out', help='output dir (default: <plugins>/<slug>/assets)')
    a = ap.parse_args()
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
    out = a.out or os.path.join(root, 'wp-content', 'plugins', a.slug, 'assets')
    os.makedirs(out, exist_ok=True)
    lines = a.title.split('|')
    b = banner(lines, a.tagline, a.glyph)
    b.save(os.path.join(out, 'banner-1544x500.png'))
    b.resize((772, 250), Image.LANCZOS).save(os.path.join(out, 'banner-772x250.png'))
    i = icon(lines, a.glyph)
    i.save(os.path.join(out, 'icon-256x256.png'))
    i.resize((128, 128), Image.LANCZOS).save(os.path.join(out, 'icon-128x128.png'))
    print('wrote banner-1544x500, banner-772x250, icon-256x256, icon-128x128 to', out)


if __name__ == '__main__':
    main()
