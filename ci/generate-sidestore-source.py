#!/usr/bin/env python3
"""Generate docs/apps.json and docs/trollstore.json - the MuffinEMU install sources.

Built from the repository's real GitHub releases rather than maintained by hand, so the
sources cannot drift from what is actually downloadable. Only numbered releases (vX.Y
tags) that carry the right IPA appear; test builds (auto-<sha>) never do.

apps.json serves the plain MuffinEMU.ipa: SideStore, AltStore and LiveContainer re-sign
with the user's own Apple ID, which strips any existing signature. trollstore.json serves
MuffinEMU-fakesigned.ipa, which carries the JIT entitlements inside its ad-hoc signature.

Usage:  python3 ci/generate-sidestore-source.py [--repo owner/name] [--out-dir docs]
Reads GITHUB_TOKEN from the environment when present (raises the API rate limit).
"""
import json, os, re, sys, urllib.request, argparse

PAGES = "https://kiddreads.github.io/MuffinEMU"
BUNDLE_ID = "com.kiddreads.MuffinEMU"
VERSION_TAG = re.compile(r"^v(\d+)\.(\d+)$")


def releases(repo, token):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/releases?per_page=100",
        headers={"Accept": "application/vnd.github+json",
                 **({"Authorization": f"Bearer {token}"} if token else {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def notes_for(rel):
    body = (rel.get("body") or "").strip()
    if not body:
        return rel["tag_name"]
    body = re.sub(r"\r\n", "\n", body)
    return body[:1500] + ("..." if len(body) > 1500 else "")


def build_source(rels, asset_name, ident, name, subtitle, app_subtitle, extra_note):
    versions = []
    for rel in rels:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        m = VERSION_TAG.match(rel["tag_name"])
        if not m:
            continue
        ipa = next((x for x in rel.get("assets", []) if x["name"] == asset_name), None)
        if not ipa:
            continue
        versions.append({
            "version": f"{m.group(1)}.{m.group(2)}",
            "key": (int(m.group(1)), int(m.group(2))),
            "date": rel["published_at"],
            "localizedDescription": notes_for(rel),
            "downloadURL": ipa["browser_download_url"],
            "size": ipa["size"],
            "minOSVersion": "15.0",
        })
    if not versions:
        return None
    versions.sort(key=lambda v: v["key"], reverse=True)
    for v in versions:
        del v["key"]
    return {
        "name": name,
        "identifier": ident,
        "subtitle": subtitle,
        "description": (
            "The install source for MuffinEMU, a Wii U emulator for iPhone and iPad built "
            "on Cemu. " + extra_note),
        "iconURL": f"{PAGES}/icon.png",
        "website": f"{PAGES}/",
        "tintColor": "E5652E",
        "apps": [{
            "name": "MuffinEMU",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "kiddreads",
            "subtitle": app_subtitle,
            "localizedDescription": (
                "MuffinEMU is a Wii U emulator for iPhone and iPad, iOS 15 and later, built "
                "on Cemu: PowerPC interpreters, an AArch64 recompiler, Cafe OS HLE and a "
                "native Metal renderer under a SwiftUI app with a measured Wii U GamePad "
                "layout. Some MeloCafe cores and bug fixes have been brought over to "
                "MuffinEMU.\n\n"
                + extra_note + "\n\n"
                "Bring your own games and keys. No copyrighted content is distributed here."),
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
    ap.add_argument("--repo", default="kiddreads/MuffinEMU")
    ap.add_argument("--out-dir", default="docs")
    a = ap.parse_args()

    rels = releases(a.repo, os.environ.get("GITHUB_TOKEN"))
    feeds = [
        ("apps.json", "MuffinEMU.ipa", "com.kiddreads.MuffinEMU.source", "MuffinEMU",
         "Wii U emulation for iPhone and iPad.",
         "Wii U emulator for iPhone and iPad",
         "This source serves the standard build for SideStore, AltStore and "
         "LiveContainer, which re-sign it with your own Apple ID at install."),
        ("trollstore.json", "MuffinEMU-fakesigned.ipa", "com.kiddreads.MuffinEMU.trollstore",
         "MuffinEMU (TrollStore)",
         "Wii U emulation for iPhone and iPad - TrollStore build.",
         "Wii U emulator - TrollStore build",
         "This source serves the ad-hoc signed build for TrollStore and jailbroken "
         "devices, with the JIT entitlements embedded so the recompiler can get "
         "executable memory. On SideStore or AltStore use the standard source instead - "
         "those re-sign at install and would strip these entitlements."),
    ]

    wrote = 0
    for fname, asset, ident, name, subtitle, app_subtitle, note in feeds:
        src = build_source(rels, asset, ident, name, subtitle, app_subtitle, note)
        if src is None:
            print(f"skipped {fname}: no numbered release carries {asset} yet")
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
