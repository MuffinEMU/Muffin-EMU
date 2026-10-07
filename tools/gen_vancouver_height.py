#!/usr/bin/env python3
"""Bake homebrew/vancouver/source/vancouver_height.h (128x96 heightmap, one byte per cell).

Hand-shaped from the 40x30 sketch grid in tools/vancouver_grid.txt (W water, L land,
M mountain, P park). No SRTM or other dataset is used. Byte = park<<7 | height (0..127,
0 = sea level / water). Run: python3 tools/gen_vancouver_height.py
"""
import math, os
MW, MH, S = 128, 96, 3.2
here = os.path.dirname(os.path.abspath(__file__))
grid = open(os.path.join(here, "vancouver_grid.txt")).read().split()
def cell(x, y):
    return grid[min(len(grid) - 1, int(y / S))][min(len(grid[0]) - 1, int(x / S))]
def noise(x, y):
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 255) / 255.0 - 0.5
h = [[0.0] * MW for _ in range(MH)]
for y in range(MH):
    for x in range(MW):
        c = cell(x, y)
        if c == 'W':
            continue
        if c == 'M':
            d = 0
            while y + d < MH and cell(x, y + d) == 'M':
                d += 1
            v = 25 + min(d, 30) * 3.6 + noise(x, y) * 14  # d = cells to the mountain's south edge
        else:
            rise = 0 if y >= 62 else (62 - y) / 40.0   # Richmond/Delta flat
            v = 5 + 8 * rise + noise(x, y) * (0 if y >= 62 else 3)
        h[y][x] = v
# Burnaby Mountain
for y in range(MH):
    for x in range(MW):
        if cell(x, y) != 'W':
            h[y][x] += 45 * math.exp(-(((x - 77) ** 2 + (y - 32) ** 2) / 72.0))
for _ in range(3):  # smooth, land only
    n = [r[:] for r in h]
    for y in range(1, MH - 1):
        for x in range(1, MW - 1):
            if cell(x, y) != 'W':
                n[y][x] = sum(h[y + j][x + i] for j in (-1, 0, 1) for i in (-1, 0, 1)) / 9.0
    h = n
out = []
for y in range(MH):
    row = []
    for x in range(MW):
        c = cell(x, y)
        v = 0 if c == 'W' else max(3, min(127, int(round(h[y][x]))))
        row.append("0x%02X" % (v | (128 if c == 'P' else 0)))
    out.append(",".join(row) + ",")
open(os.path.join(here, "..", "homebrew", "vancouver", "source", "vancouver_height.h"), "w").write("\n".join(out) + "\n")
print("wrote", MW * MH, "bytes")
