#!/usr/bin/env python3
"""Muffin business cards - ten different muffins, one per card.

Avery 8371 geometry was read out of the customer's own template PDF, not
guessed: cards are 252x144pt at x=54/306, y=612/468/324/180/36, with 0.75in
side and 0.5in top/bottom margins and no gutters.

Each card carries a different app icon and is painted in that icon's own theme
colours, pulled from MuffinThemePresets.swift. Text colour flips to suit the
background's luminance, because the set spans Diamond Ice and Double Chocolate.

Raw PDF by hand - this machine has no reportlab, no PIL and no disk to spare.
An 8-bit non-interlaced RGB PNG is already a valid PDF image stream (PDF's
/Predictor 15 IS the PNG predictor), so icons embed byte-for-byte with no
decode and no quality loss.
"""
import json, struct, zlib

REPO = "/Users/kiddreads/cemu-ios-muffin"
PW, PH = 612.0, 792.0
CW, CH = 252.0, 144.0
COLS = [54.0, 306.0]
ROWS = [612.0, 468.0, 324.0, 180.0, 36.0]
M, ICON, COL_X = 15.0, 72.0, 108.0

ORDER = ["original", "double-chocolate", "blueberry-blast", "strawberry", "lemon-zest",
         "fix-the-world", "autism-awareness", "pro-gold-vip", "pro-holographic", "pro-diamond-ice"]

TAGLINES = {
    "original":         "Wii U emulation, native on iOS",
    "double-chocolate": "Wii U emulation, native on iOS",
    "blueberry-blast":  "Wii U emulation, native on iOS",
    "strawberry":       "Wii U emulation, native on iOS",
    "lemon-zest":       "Wii U emulation, native on iOS",
    "fix-the-world":    "Wii U emulation, native on iOS",
    "autism-awareness": "Wii U emulation, native on iOS",
    "pro-gold-vip":     "Wii U emulation, native on iOS",
    "pro-holographic":  "Wii U emulation, native on iOS",
    "pro-diamond-ice":  "Wii U emulation, native on iOS",
}

# Colours are SAMPLED FROM THE ICON PIXELS (ci/sample-icon-colors.py), not read
# from MuffinThemePresets.swift. The presets are flat two-stop derivations that
# lost most of what the artwork does - they had Fix the World as peach-to-brown
# when it is actually peach-to-purple, and Holographic as blue when it is a pink
# and lilac iridescent. Names still come from the presets; colour comes from the
# only thing that cannot be wrong about an icon, which is the icon.
REAL = json.load(open("/tmp/real-colors.json"))
NAMES = {k: v["name"] for k, v in json.load(open("/tmp/themes.json")).items()}


def hx(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16) / 255.0, int(h[2:4], 16) / 255.0, int(h[4:6], 16) / 255.0)


def rel_lum(c):
    """WCAG relative luminance - sRGB decoded to linear light."""
    def f(v):
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(x) for x in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = rel_lum(a), rel_lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def readable(fg, bg, target=4.0):
    """Push fg away from bg until it clears `target` contrast.

    Each theme's accent was picked to sit on the APP's surfaces, not on a card
    painted in that same theme - so on its own background several of them very
    nearly vanished (Strawberry's green on pink, Lemon Zest's teal on yellow).
    Hue is preserved; only lightness moves, and only as far as it must.
    """
    if contrast(fg, bg) >= target:
        return fg
    # Pick the direction that ACTUALLY gains more contrast, rather than guessing
    # from a luminance threshold. A mid-orange card sits right on the old 0.4
    # cutoff, so accents there were being driven to white and arriving washed
    # out on a light background - the wrong way entirely.
    goal = (0.0, 0.0, 0.0) if contrast(fg, bg) < contrast((0.0, 0.0, 0.0), bg) \
        and contrast((0.0, 0.0, 0.0), bg) >= contrast((1.0, 1.0, 1.0), bg) else (1.0, 1.0, 1.0)
    best = fg
    for i in range(1, 21):
        cand = mix(fg, goal, i / 20.0)
        best = cand
        if contrast(cand, bg) >= target:
            break
    return best


def saturate(c, k):
    g = lum(c)
    return tuple(min(1.0, max(0.0, g + (v - g) * k)) for v in c)


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def mix(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def icon_path(iid):
    if iid == "original":
        return f"{REPO}/docs/icon.png"
    return f"{REPO}/src/ios/Resources/Assets.xcassets/AltIcon-{iid}.appiconset/icon.png"


def load_png(path):
    d = open(path, "rb").read()
    w, h, bd, ct, _, _, il = struct.unpack(">IIBBBBB", d[16:29])
    if (bd, ct, il) != (8, 2, 0):
        raise SystemExit(f"{path}: need 8-bit non-interlaced RGB, got bd={bd} ct={ct} il={il}")
    idat, i = b"", 8
    while i < len(d):
        ln = struct.unpack(">I", d[i:i+4])[0]
        t = d[i+4:i+8]
        if t == b"IDAT": idat += d[i+8:i+8+ln]
        elif t == b"IEND": break
        i += 12 + ln
    return w, h, idat


ICONS = {i: load_png(icon_path(i)) for i in ORDER}


def esc(t): return t.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")


class C:
    def __init__(self): self.o = []
    def __lshift__(self, s): self.o.append(s); return self
    def out(self): return "\n".join(self.o).encode("latin-1")
    def fill(self, c): self << f"{c[0]:.4f} {c[1]:.4f} {c[2]:.4f} rg"
    def rect(self, x, y, w, h, c):
        self.fill(c); self << f"{x:.2f} {y:.2f} {w:.2f} {h:.2f} re f"
    def text(self, x, y, f, s, c, t, sp=None):
        self.fill(c); self << "BT"
        if sp is not None: self << f"{sp:.2f} Tc"
        self << f"/{f} {s:.2f} Tf"; self << f"1 0 0 1 {x:.2f} {y:.2f} Tm"
        self << f"({esc(t)}) Tj"
        if sp is not None: self << "0 Tc"
        self << "ET"
    def circle(self, cx, cy, r, c):
        k = 0.5523 * r; self.fill(c)
        self << f"{cx-r:.2f} {cy:.2f} m"
        self << f"{cx-r:.2f} {cy+k:.2f} {cx-k:.2f} {cy+r:.2f} {cx:.2f} {cy+r:.2f} c"
        self << f"{cx+k:.2f} {cy+r:.2f} {cx+r:.2f} {cy+k:.2f} {cx+r:.2f} {cy:.2f} c"
        self << f"{cx+r:.2f} {cy-k:.2f} {cx+k:.2f} {cy-r:.2f} {cx:.2f} {cy-r:.2f} c"
        self << f"{cx-k:.2f} {cy-r:.2f} {cx-r:.2f} {cy-k:.2f} {cx-r:.2f} {cy:.2f} c"
        self << "f"
    def squircle_path(self, x, y, w, h, r):
        k = 0.5523 * r
        self << f"{x+r:.2f} {y:.2f} m"
        self << f"{x+w-r:.2f} {y:.2f} l"
        self << f"{x+w-r+k:.2f} {y:.2f} {x+w:.2f} {y+r-k:.2f} {x+w:.2f} {y+r:.2f} c"
        self << f"{x+w:.2f} {y+h-r:.2f} l"
        self << f"{x+w:.2f} {y+h-r+k:.2f} {x+w-r+k:.2f} {y+h:.2f} {x+w-r:.2f} {y+h:.2f} c"
        self << f"{x+r:.2f} {y+h:.2f} l"
        self << f"{x+r-k:.2f} {y+h:.2f} {x:.2f} {y+h-r+k:.2f} {x:.2f} {y+h-r:.2f} c"
        self << f"{x:.2f} {y+r:.2f} l"
        self << f"{x:.2f} {y+r-k:.2f} {x+r-k:.2f} {y:.2f} {x+r:.2f} {y:.2f} c"
    def roundrect(self, x, y, w, h, r, c):
        self.fill(c); self.squircle_path(x, y, w, h, r); self << "f"
    def icon(self, name, x, y, size, ring):
        # Ring first: every icon carries its own theme-coloured background, so on
        # a card painted in that same theme the badge would otherwise dissolve
        # into the card. The ring is what keeps it reading as an app icon.
        self.roundrect(x - 1.6, y - 1.6, size + 3.2, size + 3.2, size * 0.2237 + 1.6, ring)
        self << "q"; self.squircle_path(x, y, size, size, size * 0.2237); self << "W n"
        self << f"{size:.2f} 0 0 {size:.2f} {x:.2f} {y:.2f} cm"
        self << f"/Im_{name.replace('-', '_')} Do"
        self << "Q"
    def star(self, cx, cy, r, c):
        self.fill(c); i = r * 0.22
        self << f"{cx:.2f} {cy+r:.2f} m"
        self << f"{cx+i:.2f} {cy+i:.2f} {cx+i:.2f} {cy+i:.2f} {cx+r:.2f} {cy:.2f} c"
        self << f"{cx+i:.2f} {cy-i:.2f} {cx+i:.2f} {cy-i:.2f} {cx:.2f} {cy-r:.2f} c"
        self << f"{cx-i:.2f} {cy-i:.2f} {cx-i:.2f} {cy-i:.2f} {cx-r:.2f} {cy:.2f} c"
        self << f"{cx-i:.2f} {cy+i:.2f} {cx-i:.2f} {cy+i:.2f} {cx:.2f} {cy+r:.2f} c"
        self << "f"


def palette(iid):
    r = REAL[iid]
    top, bot, accent = hx(r["top"]), hx(r["bottom"]), hx(r["accent"])
    # Only a light lift, and saturation restored afterwards. Mixing hard toward
    # white desaturates, which turned Double Chocolate into grey taupe and made
    # the whole set drab. Dark themes stay dark; the ink flip below is what
    # keeps them readable rather than washing the colour out of them.
    base = saturate(mix(top, (1, 1, 1), 0.14), 1.12)
    deep = saturate(mix(bot, (1, 1, 1), 0.04), 1.12)
    mid = mix(base, deep, 0.5)
    ink = (0.11, 0.09, 0.07) if lum(mid) > 0.52 else (1.0, 0.99, 0.96)
    sub = readable(mix(ink, mid, 0.34), mid, 3.8)
    accent = readable(accent, mid, 4.2)
    second = readable(mix(accent, (1, 1, 1), 0.35) if lum(mid) < 0.5
                      else mix(accent, (0, 0, 0), 0.25), mid, 3.4)
    ring = mix(ink, (1, 1, 1), 0.74) if lum(mid) > 0.52 else mix(ink, mid, 0.22)
    return dict(top=base, bottom=deep, accent=accent, pink=second, ink=ink, sub=sub,
                ring=ring, name=NAMES.get(iid, iid))


def ribbon(c, p, y, h):
    seg = [p["accent"], p["pink"], mix(p["accent"], (1, 1, 1), 0.45),
           mix(p["pink"], (1, 1, 1), 0.5), p["accent"], p["pink"]]
    bw = CW / len(seg)
    for i, col in enumerate(seg):
        c.rect(i * bw, y, bw + 0.5, h, col)


def wash(c, p):
    N = 26
    for i in range(N):
        t = i / (N - 1.0)
        col = mix(p["top"], p["bottom"], t)
        c.rect(0, CH * (1.0 - (i + 1) / N), CW, CH / N + 0.6, col)


def front(c, x, y, iid):
    p = palette(iid)
    c << "q"; c << f"{x:.2f} {y:.2f} {CW:.2f} {CH:.2f} re W n"
    c << f"1 0 0 1 {x:.2f} {y:.2f} cm"
    wash(c, p)
    ribbon(c, p, CH - 6.5, 6.5)
    # Confetti only above the cap-height of "Muffin" and below the baseline
    # block - two bands no glyph reaches, so nothing can land on the type.
    for cx, cy, r, col in ((148, 132, 2.5, p["pink"]), (180, 127, 1.8, p["accent"]),
                           (212, 133, 2.2, p["accent"]), (238, 127, 1.7, p["pink"]),
                           (26, 20, 2.2, p["pink"]), (52, 13, 1.7, p["accent"])):
        c.circle(cx, cy, r, col)
    c.icon(iid, M, (CH - ICON) / 2.0, ICON, p["ring"])
    c.text(COL_X, 92, "Helvetica-Bold", 26, p["ink"], "Muffin")
    c.text(COL_X + 2, 76, "Helvetica-Bold", 10.0, p["accent"], "E M U", sp=1.4)
    c.rect(COL_X, 68, 44, 2.0, p["pink"])
    # No theme name. Each card already IS its theme - printing "Double Chocolate"
    # on a chocolate card labels what the reader can see, and it was the line
    # that made the block feel crowded. Dropping it lets the rest breathe.
    c.text(COL_X, 48, "Helvetica", 8.4, p["sub"], TAGLINES[iid])
    c.text(COL_X, 28, "Helvetica", 7.2, p["sub"], "iPad \267 iPhone \267 TrollStore \267 SideStore")
    c << "Q"


def back(c, x, y, iid):
    p = palette(iid)
    c << "q"; c << f"{x:.2f} {y:.2f} {CW:.2f} {CH:.2f} re W n"
    c << f"1 0 0 1 {x:.2f} {y:.2f} cm"
    wash(c, p)
    ribbon(c, p, CH - 6.5, 6.5)
    ribbon(c, p, 0, 3.0)
    c.icon(iid, M, CH - M - 44.0, 44.0, p["ring"])
    c.text(72, 104, "Helvetica-Bold", 14.5, p["ink"], "Muffin EMU")
    c.rect(72, 96, 30, 2.0, p["pink"])
    for i, (col, label) in enumerate([(p["accent"], "The Wii U, in your hands"),
                                      (p["pink"], "Metal renderer built for Apple GPUs"),
                                      (p["accent"], "Recompiler and interpreter, both first-class")]):
        yy = 78.0 - i * 14.5
        c.circle(76, yy + 2.5, 2.6, col)
        c.text(85, yy, "Helvetica", 7.6, p["sub"], label)
    panel = mix(p["ink"], p["bottom"], 0.12)
    c.roundrect(M, M, CW - 2 * M, 21.0, 5.0, panel)
    on = (1.0, 0.99, 0.96) if lum(panel) < 0.5 else (0.13, 0.10, 0.08)
    c.text(M + 9, M + 11.5, "Helvetica-Bold", 7.6, on, "kiddreads.github.io/cemu-ios-muffin")
    c.text(M + 9, M + 4.0, "Helvetica", 6.4, mix(on, panel, 0.35), "github.com/kiddreads/cemu-ios-muffin")
    c << "Q"


def img_obj(iid):
    w, h, data = ICONS[iid]
    return (f"<< /Type /XObject /Subtype /Image /Width {w} /Height {h} /ColorSpace /DeviceRGB "
            f"/BitsPerComponent 8 /Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 "
            f"/BitsPerComponent 8 /Columns {w} >> /Length {len(data)} >>\nstream\n").encode() + data + b"\nendstream"


def write_pdf(path, pages, page_w=PW, page_h=PH):
    """pages: list of Content objects. All icons are attached to every page."""
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    off = {}
    def emit(n, body):
        off[n] = len(out); out.extend(f"{n} 0 obj\n".encode()); out.extend(body); out.extend(b"\nendobj\n")

    n_pages = len(pages)
    first_content = 3 + n_pages
    first_img = first_content + n_pages + 2
    xo = " ".join(f"/Im_{i.replace('-', '_')} {first_img + k} 0 R" for k, i in enumerate(ORDER))
    res = (f"<< /Font << /Helvetica-Bold {first_content + n_pages} 0 R "
           f"/Helvetica {first_content + n_pages + 1} 0 R >> /XObject << {xo} >> >>").encode()

    emit(1, b"<< /Type /Catalog /Pages 2 0 R >>")
    kids = " ".join(f"{3+i} 0 R" for i in range(n_pages))
    emit(2, f"<< /Type /Pages /Kids [{kids}] /Count {n_pages} >>".encode())
    for i in range(n_pages):
        emit(3 + i, (f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {page_w:.0f} {page_h:.0f}] /Resources ".encode()
                     + res + f" /Contents {first_content + i} 0 R >>".encode()))
    for i, pg in enumerate(pages):
        data = zlib.compress(pg.out())
        emit(first_content + i, f"<< /Length {len(data)} /Filter /FlateDecode >>\nstream\n".encode() + data + b"\nendstream")
    emit(first_content + n_pages, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
    emit(first_content + n_pages + 1, b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    for k, iid in enumerate(ORDER):
        emit(first_img + k, img_obj(iid))

    total = first_img + len(ORDER)
    xref = len(out)
    out.extend(f"xref\n0 {total}\n".encode()); out.extend(b"0000000000 65535 f \n")
    for i in range(1, total):
        out.extend(f"{off[i]:010d} 00000 n \n".encode())
    out.extend(f"trailer\n<< /Size {total} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    open(path, "wb").write(out)
    return len(out)


def sheet(path):
    f, b = C(), C()
    slots = [(col, row) for row in ROWS for col in COLS]
    for iid, (cx, cy) in zip(ORDER, slots):
        front(f, cx, cy, iid)
    # Columns reversed on the back so long-edge duplex puts each back on its own
    # front; without this every card gets its neighbour's reverse.
    slots_b = [(col, row) for row in ROWS for col in reversed(COLS)]
    for iid, (cx, cy) in zip(ORDER, slots_b):
        back(b, cx, cy, iid)
    return write_pdf(path, [f, b])


def single(path, iid, face):
    c = C()
    (front if face == "front" else back)(c, 0.0, 0.0, iid)
    return write_pdf(path, [c], CW, CH)


if __name__ == "__main__":
    import sys
    if sys.argv[1] == "sheet":
        print("sheet:", sheet(sys.argv[2]), "bytes")
    else:
        print(single(sys.argv[3], sys.argv[1], sys.argv[2]), "bytes")
