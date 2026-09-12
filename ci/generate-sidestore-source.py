#!/usr/bin/env python3
"""Generate docs/apps.json - the SideStore/AltStore source for Muffin.

Built from the repository's real GitHub releases rather than maintained by hand,
so the source cannot drift from what is actually downloadable. A release only
appears if it genuinely carries a `Cemu.ipa` asset.

Deliberately publishes the PLAIN Cemu.ipa, never Cemu-fakesigned.ipa: SideStore
re-signs with the user's own Apple ID at install time, which strips an ad-hoc
signature anyway. The fake-signed build exists for TrollStore, which is a
different install path and not what a source feed is for.

Usage:  python3 ci/generate-sidestore-source.py [--repo owner/name] [--out docs/apps.json]
Reads GITHUB_TOKEN from the environment when present (raises the API rate limit).
"""
import json, os, re, sys, urllib.request, argparse

PAGES = "https://kiddreads.github.io/muffin-emu"

def releases(repo, token):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/releases?per_page=100",
        headers={"Accept": "application/vnd.github+json",
                 **({"Authorization": f"Bearer {token}"} if token else {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

def version_of(tag):
    """Derive the displayed version from a release tag.

    This repository has used two tagging schemes, and they are a single continuous
    sequence once you read them right:

      v1.35 ... v1.38, v2.0 ... v2.2   dotted, used first
      v33 ... v47                      flat, used after

    The flat numbers were always meant to be read as dotted - v2.2 is followed by
    v33, which is 3.3, and the sequence runs 2.2 -> 3.3 -> 4.0 -> 4.7 without a
    break. Shipping the flat form verbatim is what made the app report version "47",
    as though it were a mature product on its forty-seventh major release rather than
    pre-1.0 software that does not reliably play games yet.

    So: an already-dotted tag is used as it stands, and a flat one is split into
    major.minor (47 -> 4.7, 50 -> 5.0, and still correct past 100: 122 -> 12.2).
    Both schemes then sort against each other correctly, which they would not if the
    flat ones were left alone.

    Anything that is not vN-shaped falls back to the raw tag - a source with a
    missing version field is worse than an ugly one.
    """
    m = re.match(r"^v(\d+)\.(\d+)", tag)      # already dotted: keep it
    if m:
        return f"{m.group(1)}.{m.group(2)}"
    m = re.match(r"^v(\d+)", tag)               # flat: split it
    if m:
        n = int(m.group(1))
        return f"{n // 10}.{n % 10}"
    return tag.lstrip("v")


def notes_for(rel):
    body = (rel.get("body") or "").strip()
    if not body:
        # The tag's own slug is more informative than an empty string.
        slug = re.sub(r"^v\d+-?", "", rel["tag_name"]).replace("-", " ").strip()
        return slug.capitalize() or rel["tag_name"]
    # Keep it to something a phone-sized changelog box can show.
    body = re.sub(r"\r\n", "\n", body)
    return body[:1500] + ("..." if len(body) > 1500 else "")

def build_source(rels, asset_name, ident, name, subtitle, app_subtitle, extra_note):
    versions = []
    for rel in rels:
        if rel.get("draft"):
            continue
        tag = rel["tag_name"]
        if re.search(r"-[0-9a-f]{40}$", tag):
            continue
        ipa = next((x for x in rel.get("assets", []) if x["name"] == asset_name), None)
        if not ipa:
            continue
        versions.append({
            "version": version_of(tag),
            "date": rel["published_at"],
            "localizedDescription": notes_for(rel),
            "downloadURL": ipa["browser_download_url"],
            "size": ipa["size"],
            "minOSVersion": "15.0",
        })
    if not versions:
        return None
    versions.sort(key=lambda v: v["date"], reverse=True)
    seen, dedup = set(), []
    for v in versions:
        if v["version"] in seen:
            continue
        seen.add(v["version"]); dedup.append(v)
    versions = dedup
    return {
        "name": name,
        "identifier": ident,
        "subtitle": subtitle,
        "description": (
            "The source for Muffin - a genuine port of the Cemu Wii U emulator to iOS, "
            "built from source in the open. Work in progress, and honest about it: see "
            "STATUS.md in the repository for exactly what works and what does not. "
            + extra_note),
        "iconURL": f"{PAGES}/icon.png",
        "website": f"{PAGES}/",
        "tintColor": "E5652E",
        "apps": [{
            "name": "Muffin",
            "bundleIdentifier": "com.cemu.Cemu",
            "developerName": "kiddreads",
            "subtitle": app_subtitle,
            "localizedDescription": (
                "Muffin is the Cemu Wii U emulator, ported to iOS - iPhone and iPad, "
                "iOS 15 and later. The real C++ engine - PowerPC interpreter, ARM64 "
                "recompiler, the full Cafe OS HLE stack and Cemu's native Metal renderer "
                "- running under a SwiftUI shell.\n\n"
                "This is in-progress software. A picture reaches the screen for real "
                "titles, but it is not yet a correct one, and no title has been confirmed "
                "playable end to end. The project documents its own state honestly rather "
                "than claiming more than it delivers - read STATUS.md before installing.\n\n"
                + extra_note + "\n\n"
                "Bring your own games. No copyrighted content is distributed here."),
            "iconURL": f"{PAGES}/icon.png",
            "tintColor": "E5652E",
            "category": "games",
            "screenshotURLs": [],
            "versions": versions,
            "appPermissions": {"entitlements": [], "privacy": {}},
        }],
        "news": [],
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="kiddreads/muffin-emu")
    ap.add_argument("--out-dir", default="docs")
    a = ap.parse_args()

    rels = releases(a.repo, os.environ.get("GITHUB_TOKEN"))

    # Two feeds, because the two install paths genuinely need different files and
    # handing someone the wrong one fails in a way that is hard to diagnose.
    #
    # apps.json      -> Cemu.ipa            (SideStore / AltStore / LiveContainer)
    #   Unsigned on purpose. Those installers re-sign with the user's own Apple ID,
    #   which strips any signature already there, so shipping them a fake-signed build
    #   gains nothing and only risks confusing the re-signer.
    #
    # trollstore.json -> Cemu-fakesigned.ipa (TrollStore / jailbroken)
    #   Ad-hoc signed with the JIT entitlements genuinely embedded. Entitlements only
    #   exist inside a signature, so on the unsigned build dynamic-codesigning and
    #   allow-jit are simply absent - which is the difference between the recompiler
    #   being able to get executable memory and not.
    feeds = [
        ("apps.json", "Cemu.ipa", "com.kiddreads.muffin", "Muffin",
         "Wii U emulation on iOS, in the open.",
         "Wii U emulator for iPhone and iPad",
         "This source serves the standard build for SideStore, AltStore and "
         "LiveContainer, which re-sign it with your own Apple ID at install."),
        ("trollstore.json", "Cemu-fakesigned.ipa", "com.kiddreads.muffin.trollstore",
         "Muffin (TrollStore)",
         "Wii U emulation on iOS - TrollStore build.",
         "Wii U emulator - TrollStore build",
         "This source serves the ad-hoc signed build for TrollStore and jailbroken "
         "devices, with the JIT entitlements embedded so the recompiler can actually "
         "get executable memory. On SideStore or AltStore use the standard source "
         "instead - those re-sign at install and would strip these entitlements."),
    ]

    wrote = 0
    for fname, asset, ident, name, subtitle, app_subtitle, note in feeds:
        src = build_source(rels, asset, ident, name, subtitle, app_subtitle, note)
        if src is None:
            print(f"skipped {fname}: no release carries {asset} yet")
            continue
        out = os.path.join(a.out_dir, fname)
        os.makedirs(a.out_dir, exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(src, f, indent=2, ensure_ascii=False)
            f.write("\n")
        v = src["apps"][0]["versions"]
        print(f"wrote {out}: {len(v)} versions, newest v{v[0]['version']} ({asset})")
        wrote += 1
    if not wrote:
        sys.exit("no feeds written")


if __name__ == "__main__":
    main()
