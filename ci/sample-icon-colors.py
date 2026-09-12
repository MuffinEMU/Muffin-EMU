#!/usr/bin/env python3
"""Sample each app icon's REAL colours out of its own pixels.

MuffinThemePresets.swift holds two-stop derivations of these icons, not the
icons themselves - flat approximations that lost most of what the artwork
actually does. The icons are the ground truth, so read them.

Pure-Python PNG decode: zlib inflate, then undo the per-scanline filters
(None/Sub/Up/Average/Paeth). No PIL on this machine and no disk to install it.
"""
import json, struct, zlib

REPO = "/Users/kiddreads/cemu-ios-muffin"
ORDER = ["original", "double-chocolate", "blueberry-blast", "strawberry", "lemon-zest",
         "fix-the-world", "autism-awareness", "pro-gold-vip", "pro-holographic", "pro-diamond-ice"]


def path(iid):
    return (f"{REPO}/docs/icon.png" if iid == "original"
            else f"{REPO}/src/ios/Resources/Assets.xcassets/AltIcon-{iid}.appiconset/icon.png")


def decode(p):
    d = open(p, "rb").read()
    w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", d[16:29])
    assert (bd, ct, il) == (8, 2, 0), p
    idat, i = b"", 8
    while i < len(d):
        ln = struct.unpack(">I", d[i:i+4])[0]
        t = d[i+4:i+8]
        if t == b"IDAT": idat += d[i+8:i+8+ln]
        elif t == b"IEND": break
        i += 12 + ln
    raw = zlib.decompress(idat)
    bpp, stride = 3, w * 3
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = raw[pos]; pos += 1
        line = bytearray(raw[pos:pos+stride]); pos += stride
        if f == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x-bpp]) & 255
        elif f == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:
            for x in range(stride):
                a = line[x-bpp] if x >= bpp else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:
            for x in range(stride):
                a = line[x-bpp] if x >= bpp else 0
                b = prev[x]
                cc = prev[x-bpp] if x >= bpp else 0
                pp = a + b - cc
                pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-cc)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else cc)
                line[x] = (line[x] + pr) & 255
        out[y*stride:(y+1)*stride] = line
        prev = line
    return w, h, bytes(out)


def px(buf, w, x, y):
    i = (y * w + x) * 3
    return buf[i] / 255.0, buf[i+1] / 255.0, buf[i+2] / 255.0


def avg(buf, w, xs, ys):
    n = 0; r = g = b = 0.0
    for y in ys:
        for x in xs:
            p = px(buf, w, x, y); r += p[0]; g += p[1]; b += p[2]; n += 1
    return (r/n, g/n, b/n)


def dist(a, b):
    return ((a[0]-b[0])**2 + (a[1]-b[1])**2 + (a[2]-b[2])**2) ** 0.5


def sat(c):
    return max(c) - min(c)


def lum(c):
    return 0.299*c[0] + 0.587*c[1] + 0.114*c[2]


def hexs(c):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v*255))) for v in c)


res = {}
for iid in ORDER:
    w, h, buf = decode(path(iid))
    step = max(1, w // 256)
    # Corners, well outside the muffin, are pure background. Sampling the very
    # top-left and bottom-right captures the real gradient the artwork uses -
    # including diagonal ones, which a two-stop preset cannot express.
    top = avg(buf, w, range(int(w*0.03), int(w*0.18), step), range(int(h*0.03), int(h*0.18), step))
    bot = avg(buf, w, range(int(w*0.82), int(w*0.97), step), range(int(h*0.82), int(h*0.97), step))
    # Accent: the most saturated colour in the muffin itself that is clearly not
    # the background - blueberries, sprinkles, the pixel-square, the rainbow.
    hist = {}
    for y in range(int(h*0.28), int(h*0.80), step):
        for x in range(int(w*0.22), int(w*0.80), step):
            c = px(buf, w, x, y)
            dbg = max(abs(c[0]-top[0]), abs(c[1]-top[1]), abs(c[2]-top[2]))
            dbg2 = max(abs(c[0]-bot[0]), abs(c[1]-bot[1]), abs(c[2]-bot[2]))
            if min(dbg, dbg2) < 0.16:
                continue
            k = (round(c[0]*11), round(c[1]*11), round(c[2]*11))
            e = hist.setdefault(k, [0, 0.0, 0.0, 0.0])
            e[0] += 1; e[1] += c[0]; e[2] += c[1]; e[3] += c[2]
    # Weight chroma hard and frequency lightly. Weighting frequency more picked
    # the muffin's own brown body for Original and Blueberry Blast - the largest
    # region, but useless as an accent. An accent wants the blueberry navy, the
    # pixel-square violet, the strawberry red: small, vivid, characterful.
    best, score = None, -1.0
    for k, (n, r, g, b) in hist.items():
        c = (r/n, g/n, b/n)
        sc_ = sat(c)
        if sc_ < 0.22:
            continue
        if lum(c) > 0.93 or lum(c) < 0.06:
            continue
        # Distance from the background matters as much as chroma. The muffin's
        # own body is both large AND saturated, so on Original and Blueberry
        # Blast it kept winning - but a baked-orange accent on an orange card is
        # no accent at all. What we want is the colour that contrasts: the
        # blueberry navy, the pixel-square violet.
        d = min(dist(c, top), dist(c, bot))
        v = (sc_ ** 2.0) * (n ** 0.18) * (d ** 2.2)
        if v > score:
            score, best = v, c
    if best is None:
        best = bot if sat(bot) > sat(top) else top
    accent = best
    res[iid] = dict(top=hexs(top), bottom=hexs(bot), accent=hexs(accent))
    print(f"  {iid:20s} top={hexs(top)}  bottom={hexs(bot)}  accent={hexs(accent)}")

json.dump(res, open("/tmp/real-colors.json", "w"), indent=1)
print("  -> /tmp/real-colors.json")
