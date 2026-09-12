import json, re, colorsys

real = json.load(open('/tmp/all31.json'))
P = 'src/ios/App/MuffinThemePresets.swift'
src = open(P).read()

# Autism Muffin's background is hand-authored (the multi-stop rainbow the owner
# asked for) - it is not derived from anything and must not be regenerated.
SKIP = {"autism-awareness"}

def hx(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16)/255.0 for i in (0, 2, 4))
def hs(t):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(v*255))) for v in t)

def rehue(target_hex, keep_hex, sat_floor=0.0):
    """Take hue+saturation from the icon, keep lightness from the existing preset.

    Copying the icon's lightness outright would put a near-black background
    behind light-mode text (the 'dark' theme's icon is #221410) and a near-white
    one behind dark-mode text. The hue is what was wrong; the lightness band was
    already tuned for legibility, so only the hue and chroma move.
    """
    th, ts, tl = colorsys.rgb_to_hls(*hx(target_hex))[0], colorsys.rgb_to_hls(*hx(target_hex))[2], None
    kh, kl, ks = colorsys.rgb_to_hls(*hx(keep_hex))
    s = max(ts, sat_floor)
    return hs(colorsys.hls_to_rgb(th, kl, s))

blocks = re.split(r'(?=    static let \w+ = MuffinThemeDefinition\()', src)
out, changed = [], []
for b in blocks:
    m = re.search(r'iconId:\s*"([^"]+)"', b)
    if not m or m.group(1) not in real or m.group(1) in SKIP:
        out.append(b); continue
    iid = m.group(1)
    r = real[iid]
    nb = b
    for field, target in (("backgroundTopLight", r['top']), ("backgroundBottomLight", r['bottom'])):
        cur = re.search(rf'{field}:\s*"(#\w{{6}})"', nb)
        if not cur: continue
        new = rehue(target, cur.group(1))
        nb = nb.replace(f'{field}: "{cur.group(1)}"', f'{field}: "{new}"', 1)
        changed.append((iid, field, cur.group(1), new))
    for field, target in (("backgroundTopDark", r['top']), ("backgroundBottomDark", r['bottom'])):
        cur = re.search(rf'{field}:\s*"(#\w{{6}})"', nb)
        if not cur: continue
        new = rehue(target, cur.group(1))
        nb = nb.replace(f'{field}: "{cur.group(1)}"', f'{field}: "{new}"', 1)
        changed.append((iid, field, cur.group(1), new))
    out.append(nb)

open(P, 'w').write("".join(out))
seen = {}
for iid, f, a, bb in changed:
    seen.setdefault(iid, []).append((f, a, bb))
for iid, ch in seen.items():
    lt = [c for c in ch if c[0] == "backgroundTopLight"]
    if lt: print(f"  {iid:22s} topLight {lt[0][1]} -> {lt[0][2]}")
print(f"\n  {len(seen)} themes re-hued, {len(changed)} colour fields updated (autism-awareness skipped)")
