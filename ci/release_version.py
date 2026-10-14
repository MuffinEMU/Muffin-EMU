#!/usr/bin/env python3
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).
"""Release numbers: which tag is newest, and what the next release is called.

Releases are X.Y.Z. Each release adds 1 to Z, and .9 rolls over: 1.0.9 -> 1.1.0,
1.9.9 -> 2.0.0, so no part ever reaches 10. A point release adds a fourth part:
1.0.2 -> 1.0.2.1 -> 1.0.2.2, and does not change which X.Y.Z comes next.

Up to v10.1 releases were X.Y (v9.9, v10.0, v10.1) with point releases X.Y.Z (v7.7.1).
Those tags stay as they are, because download URLs are made of them. They are ordered
as if the digits of X had been split: v10.1 is 1.0.1, v9.9 is 0.9.9, v7.7.1 is 0.7.7.1.
So the release after v10.1 is 1.0.2.

The app version a user has installed is what SideStore compares, and an install of 10.1
reads as newer than 1.0.2. Those users have to install 1.0.2 by hand once; after that
updates are offered normally.

Usage (tags on stdin, one per line):
  release_version.py next    ->  "<next version> <newest tag>"
  release_version.py point   ->  "<next point version> <newest tag>"
Prints nothing when there is no numbered tag yet.
"""
import re
import sys

TAG = re.compile(r"^v(\d+)\.(\d+)(?:\.(\d+))?(?:\.(\d+))?$")
# The point releases of the X.Y scheme. A three-part tag not in this set is an X.Y.Z release.
LEGACY_POINT = {"v7.7.1", "v7.9.1", "v8.0.1", "v8.8.1", "v9.6.1"}


def key(tag):
    """(X, Y, Z, point) for a numbered release tag, None for any other tag."""
    m = TAG.match(tag)
    if not m:
        return None
    a, b, c, d = (int(g) if g is not None else None for g in m.groups())
    if c is None:
        return (a // 10, a % 10, b, 0)
    if d is None and tag in LEGACY_POINT:
        return (a // 10, a % 10, b, c)
    return (a, b, c, d or 0)


def name(k):
    return ".".join(str(n) for n in (k if k[3] else k[:3]))


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "next"
    tags = {t.strip(): key(t.strip()) for t in sys.stdin if key(t.strip())}
    if not tags:
        return
    prev = max(tags, key=tags.get)
    if mode == "point":
        x, y, z, p = tags[prev]
        nxt = (x, y, z, p + 1)
    else:
        x, y, z, _ = max(k for k in tags.values() if k[3] == 0)
        z += 1
        if z >= 10:
            y, z = y + 1, 0
        if y >= 10:
            x, y = x + 1, 0
        nxt = (x, y, z, 0)
    print(name(nxt), prev)


if __name__ == "__main__":
    main()
