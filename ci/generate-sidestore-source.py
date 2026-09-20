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
NIGHTLY_NOTE = (
    'This source serves the NIGHTLY build - the newest code, rebuilt on every change and tested by nobody. It shares its bundle identifier with the standard build, so installing it replaces a standard install and keeps your games, saves and settings; the two do not sit side by side. Add this source only if you want the newest build rather than the one known to work.')


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



def nightly_asset_date(rel, ipa):
    """When the nightly actually last changed.

    Deliberately the ASSET's updated_at, not the release's published_at. The nightly
    tag is reused by every build, and GitHub keeps published_at at the moment the
    release was first created - so it froze on the day the rolling tag was made and
    never moved again, while the IPA underneath it was replaced on every build. Reading
    it meant the feed advertised one version forever: SideStore compares versions to
    decide whether an update exists, saw the same string every time, and offered no
    nightly update at all no matter how much newer the download was.

    The asset is the thing that is actually replaced, so its timestamp is the one that
    tells the truth about what the download URL now serves.
    """
    return ipa.get("updated_at") or ipa.get("created_at") or rel.get("published_at") or rel.get("created_at") or ""


def nightly_version(rel, ipa):
    """A version string for the rolling nightly.

    Date-based, so it always sorts above any vX.Y and SideStore sees a newer nightly as
    an update. A nightly has no number of its own - the tag it lives on is reused by
    every build - so there is nothing else honest to put here.

    Day granularity, which means two nightlies built on the same day share a version and
    the second is not offered as an update. That is a known limit of the scheme rather
    than a bug in it; the alternative is inventing a build counter this script has no
    honest source for.
    """
    date = nightly_asset_date(rel, ipa)[:10]
    y, m, d = (date.split("-") + ["0", "0", "0"])[:3]
    return f"{int(y or 0)}.{int(m or 0)}.{int(d or 0)}"


def build_nightly(rels, asset_name, ident, name, subtitle, app_subtitle, extra_note):
    rel = next((r for r in rels if r.get("tag_name") == "nightly"), None)
    if not rel:
        return None
    ipa = next((x for x in rel.get("assets", []) if x["name"] == asset_name), None)
    if not ipa:
        return None
    src = build_source_shell(ident, name, subtitle, app_subtitle, extra_note)
    src["apps"][0]["name"] = "MuffinEMU Nightly"
    src["apps"][0]["versions"] = [{
        "version": nightly_version(rel, ipa),
        "date": nightly_asset_date(rel, ipa),
        "localizedDescription": notes_for(rel),
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": "15.0",
    }]
    return src

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
    src = build_source_shell(ident, name, subtitle, app_subtitle, extra_note)
    src["apps"][0]["versions"] = versions
    return src


def build_source_shell(ident, name, subtitle, app_subtitle, extra_note):
    """Everything about a feed except which versions are in it.

    Shared so the stable and nightly feeds cannot drift apart in their description,
    icon or tint - the only thing that should differ between them is the build they
    point at and the warning attached to it.
    """
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
            "versions": [],
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

    nightlies = [
        ("nightly.json", "MuffinEMU.ipa", "com.kiddreads.MuffinEMU.nightly",
         "MuffinEMU Nightly",
         "The newest MuffinEMU build, rebuilt on every change.",
         "Wii U emulator - nightly build",
         NIGHTLY_NOTE),
        ("nightly-trollstore.json", "MuffinEMU-fakesigned.ipa",
         "com.kiddreads.MuffinEMU.nightly.trollstore",
         "MuffinEMU Nightly (TrollStore)",
         "The newest MuffinEMU build - TrollStore.",
         "Wii U emulator - nightly TrollStore build",
         NIGHTLY_NOTE + " This one is the ad-hoc signed build, with the JIT entitlements "
         "embedded, for TrollStore and jailbroken devices."),
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
    # The nightly feeds are allowed to be absent - the rolling tag only exists once a
    # build has published it - so a missing one is reported and skipped rather than
    # failing the run and blocking the stable feeds from updating.
    for fname, asset, ident, name, subtitle, app_subtitle, note in nightlies:
        src = build_nightly(rels, asset, ident, name, subtitle, app_subtitle, note)
        if src is None:
            print(f"skipped {fname}: the nightly release does not carry {asset} yet")
            continue
        out = os.path.join(a.out_dir, fname)
        os.makedirs(a.out_dir, exist_ok=True)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(src, f, indent=2, ensure_ascii=False)
            f.write("\n")
        v = src["apps"][0]["versions"]
        print(f"wrote {out}: nightly {v[0]['version']} ({asset})")

    if not wrote:
        sys.exit("no numbered feeds written")


if __name__ == "__main__":
    main()
