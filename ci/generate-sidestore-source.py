#!/usr/bin/env python3
"""Generate the MuffinEMU install sources in docs/.

Built from the repository's real GitHub releases rather than maintained by hand, so the
sources cannot drift from what is actually downloadable. There are three channels and each
feed reads from exactly one kind of release:

  stable        apps.json, trollstore.json        numbered releases (vX.Y tags) only
  nightly       nightly.json, nightly-trollstore  the `nightly` release, and only if its tag points
                                                  at a commit on main
  experimental  experimental.json,                per-experiment releases only: pre-releases titled
                experimental-trollstore.json      "Experimental: ..." whose tag is
                                                  experimental-<slug>-<sha7> (or the legacy
                                                  auto-<sha> of the first two). Never the rolling
                                                  `experimental` release, never nightly, never vX.Y.

Nothing is written unless every guard passes (see check_guards): a stable or nightly feed that
mentions an experimental URL, an experimental feed that mentions nightly or a numbered release, a
feed entry whose release title does not match its channel, or a nightly that is not on main, fails
the run and leaves the published feeds as they were.

apps.json serves the plain MuffinEMU.ipa: SideStore, AltStore and LiveContainer re-sign
with the user's own Apple ID, which strips any existing signature. trollstore.json serves
MuffinEMU-fakesigned.ipa, which carries the JIT entitlements inside its ad-hoc signature.

Usage:  python3 ci/generate-sidestore-source.py [--repo owner/name] [--out-dir docs]
Reads GITHUB_TOKEN from the environment when present (raises the API rate limit).
"""
import json, os, re, sys, urllib.request, urllib.error, urllib.parse, argparse

PAGES = "https://muffinemu.github.io/MuffinEMU"
BUNDLE_ID = "com.kiddreads.MuffinEMU"
VERSION_TAG = re.compile(r"^v(\d+)\.(\d+)$")
NIGHTLY_NOTE = (
    'This source serves the nightly build: the newest code, rebuilt on every change and not tested. It has the same bundle identifier as the standard build, so installing it replaces a standard install and keeps your games, saves and settings. Add it only if you want the newest build rather than the one known to work.')


EXPERIMENTAL_TAG = re.compile(r"^experimental-[a-z0-9-]+-[0-9a-f]{7}$")
# The first two experiments were published before the experimental-<slug>-<sha7> scheme and were
# retitled "Experimental: ..." by hand. They are accepted by title rather than re-tagged: a release's
# tag is what its download URLs are made of, so re-tagging would break links already shared.
LEGACY_EXPERIMENTAL_TAG = re.compile(r"^auto-[0-9a-f]{40}$")
EXPERIMENTAL_TITLE = re.compile(r"^Experimental: (.+) \((.+) @ ([0-9a-f]{7,40})\)$")
EXPERIMENTAL_KEEP = 10
EXPERIMENTAL_NOTE = (
    'These are unfinished test builds, published by hand to try out work in progress. Each one replaces an installed MuffinEMU: it has the same bundle identifier as the standard build, so your games, saves and settings carry over. They can crash or misbehave. For normal play use the Stable source instead.')


def api(repo, path, token, allow_404=False):
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/{path}",
        headers={"Accept": "application/vnd.github+json",
                 **({"Authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404 and allow_404:
            return None
        raise


def releases(repo, token):
    return api(repo, "releases?per_page=100", token)


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


def nightly_commit(repo, token):
    """The commit the `nightly` tag points at, or None if there is no such tag."""
    ref = api(repo, "git/ref/tags/nightly", token, allow_404=True)
    if not ref:
        return None
    obj = ref["object"]
    if obj["type"] == "tag":  # an annotated tag: one more hop to the commit
        obj = api(repo, f"git/tags/{obj['sha']}", token)["object"]
    return obj["sha"]


def check_nightly_on_main(repo, token):
    """Fail unless the nightly release's commit is on main.

    The nightly feeds exist to serve main's newest build. A build from any other ref that ended up
    under the `nightly` tag would otherwise be handed to everyone who added the source (it happened
    once, with two experimental branch builds). Reachable from main means the compare of main
    against the commit says the commit is behind main or identical to it.
    """
    sha = nightly_commit(repo, token)
    if sha is None:
        sys.exit("the nightly release exists but its tag does not: cannot verify it is on main")
    cmp = api(repo, f"compare/main...{sha}", token, allow_404=True)
    if not cmp or cmp.get("status") not in ("behind", "identical"):
        sys.exit(f"REFUSING to update the nightly feeds: the nightly release points at {sha}, which is "
                 f"not reachable from main (compare says {cmp and cmp.get('status')}). "
                 f"Nightly must be a build of main; fix the release, then re-run.")
    return sha


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
    src["news"] = news_for(rels)
    return src


def news_for(rels, count=1):
    """A news card for the latest numbered release.

    The caption is the first two "What changed" bullets, so it reads as the headline
    changes of that version rather than install instructions.
    """
    items = []
    for rel in rels:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        m = VERSION_TAG.match(rel["tag_name"])
        if not m:
            continue
        body = (rel.get("body") or "").replace("\r\n", "\n")
        bullets = [l[2:].strip() for l in body.split("\n") if l.startswith("- ")][:2]
        caption = " ".join(bullets) or "A new version of MuffinEMU is available."
        if len(caption) > 220:
            caption = caption[:217].rsplit(" ", 1)[0] + "..."
        version = f"{m.group(1)}.{m.group(2)}"
        items.append({
            "title": f"MuffinEMU {version}",
            "identifier": f"muffinemu-v{version}",
            "caption": caption,
            "date": (rel.get("published_at") or "")[:10],
            "tintColor": "E5652E",
            "url": rel.get("html_url"),
            "appID": BUNDLE_ID,
            "notify": False,
            "key": (int(m.group(1)), int(m.group(2))),
        })
    items.sort(key=lambda n: n["key"], reverse=True)
    for n in items:
        del n["key"]
    return items[:count]


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
            "developerName": "Void",
            "subtitle": app_subtitle,
            "localizedDescription": (
                "MuffinEMU, made by Void, is a Wii U emulator for iPhone and iPad (iOS 15 and later), built on Cemu.\n\n"
                "- Import games from Files: WUA, decrypted games, and encrypted dumps with your own keys.txt. "
                "DLC and updates install from the app.\n"
                "- Metal renderer by default, with Vulkan through MoltenVK as an option.\n"
                "- Runs on the interpreter out of the box, and on the faster recompiler when a JIT "
                "enabler such as StikDebug is attached.\n"
                "- An on-screen GamePad laid out from a real Wii U GamePad, with an optional analog stick, "
                "skins and a layout editor. Hardware controllers work alongside it.\n"
                "- Single screen, both screens, or the TV image on an external display.\n"
                "- Save states, graphic packs, and 31 app icons with matching themes.\n\n"
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


def experimental_releases(rels):
    """Eligible experimental releases, newest first: (release, name, branch, sha)."""
    out = []
    for r in rels:
        if r.get("draft") or not r.get("prerelease"):
            continue
        tag = r.get("tag_name", "")
        if not (EXPERIMENTAL_TAG.match(tag) or LEGACY_EXPERIMENTAL_TAG.match(tag)):
            continue
        m = EXPERIMENTAL_TITLE.match(r.get("name") or "")
        if not m:
            continue
        out.append((r, m.group(1), m.group(2), m.group(3)))
    out.sort(key=lambda t: t[0].get("published_at") or "", reverse=True)
    return out


def branch_is_live(repo, token, branch):
    """False if the branch is deleted or already merged into main (nothing on it that main lacks)."""
    quoted = urllib.parse.quote(branch, safe="/")
    if api(repo, f"branches/{quoted}", token, allow_404=True) is None:
        return False
    cmp = api(repo, f"compare/main...{quoted}", token, allow_404=True)
    return bool(cmp) and cmp.get("status") not in ("behind", "identical")


def experimental_version(rel):
    """YYYY.M.D.HHMM from when the release was published. Four parts, so it sorts above nightly's
    three-part date and above every vX.Y, and two experiments the same day still order."""
    t = rel.get("published_at") or rel.get("created_at") or "1970-01-01T00:00:00Z"
    date, _, clock = t.partition("T")
    y, mo, d = (date.split("-") + ["0", "0", "0"])[:3]
    return f"{int(y)}.{int(mo)}.{int(d)}.{clock[0:2]}{clock[3:5]}"


def experimental_description(rel, name, branch, sha):
    body = (rel.get("body") or "").replace("\r\n", "\n")
    m = re.search(r"\*\*Based on:\*\* (.+)", body)
    base = m.group(1).strip() if m else "main"
    notes = body.split("## What changed", 1)[1].strip() if "## What changed" in body else ""
    notes = notes.split("**Full changelog**")[0].strip()
    when = (rel.get("published_at") or "")[:16].replace("T", " ")
    head = (f"Experiment: {name}\nBranch: {branch}\nCommit: {sha[:7]}\nBased on: {base}\n"
            f"Published: {when} UTC")
    text = head + ("\n\n" + notes if notes else "")
    return text[:1500] + ("..." if len(text) > 1500 else "")


def build_experimental(rels, repo, token, asset_name, ident, name, subtitle, app_subtitle, extra_note):
    chosen = []
    for rel, xname, branch, sha in experimental_releases(rels):
        ipa = next((x for x in rel.get("assets", []) if x["name"] == asset_name), None)
        if not ipa:
            continue
        if not branch_is_live(repo, token, branch):
            continue
        chosen.append((rel, xname, branch, sha, ipa))
        if len(chosen) == EXPERIMENTAL_KEEP:
            break
    if not chosen:
        return None
    src = build_source_shell(ident, name, subtitle, app_subtitle, extra_note)
    src["apps"][0]["name"] = "MuffinEMU Experimental"
    src["apps"][0]["versions"] = [{
        "version": experimental_version(rel),
        "date": rel.get("published_at"),
        "localizedDescription": experimental_description(rel, xname, branch, sha),
        "downloadURL": ipa["browser_download_url"],
        "size": ipa["size"],
        "minOSVersion": "15.0",
    } for rel, xname, branch, sha, ipa in chosen]
    src["news"] = [{
        "title": f"Experimental: {xname}",
        "identifier": f"muffinemu-experimental-{sha[:7]}",
        "caption": f"{branch} @ {sha[:7]}. An unfinished test build; it replaces an installed MuffinEMU.",
        "date": (rel.get("published_at") or "")[:10],
        "tintColor": "E5652E",
        "url": rel.get("html_url"),
        "appID": BUNDLE_ID,
        "notify": False,
    } for rel, xname, branch, sha, ipa in chosen]
    return src


DOWNLOAD = re.compile(r"/releases/download/([^/]+)/")
ROLLING_EXPERIMENTAL_URL = "/releases/download/experimental/"


def check_guards(feeds, rels):
    """Every feed, before any is written. `feeds` maps file name -> (channel, source dict).

    The checks read the OUTPUT - the URLs and titles that would actually be published - not the
    builders' own logic, so a bug in a builder cannot vouch for itself.
    """
    titles = {r["tag_name"]: (r.get("name") or "") for r in rels}
    bad = []
    for fname, (channel, src) in feeds.items():
        text = json.dumps(src)
        if channel in ("stable", "nightly") and "/experimental" in text:
            bad.append(f"{fname}: a {channel} feed mentions an experimental URL")
        if channel == "experimental":
            if ROLLING_EXPERIMENTAL_URL in text:
                bad.append(f"{fname}: the experimental feed points at the rolling `experimental` release")
            if "/releases/download/nightly/" in text or re.search(r"/releases/download/v\d+\.\d+/", text):
                bad.append(f"{fname}: the experimental feed points at nightly or a numbered release")
        for v in src["apps"][0]["versions"]:
            m = DOWNLOAD.search(v["downloadURL"])
            tag = m.group(1) if m else ""
            title = titles.get(tag, "")
            if channel == "stable" and not (VERSION_TAG.match(tag) and title.startswith("MuffinEMU ")):
                bad.append(f"{fname}: entry {v['version']} is release '{tag}' titled '{title}', not a numbered MuffinEMU release")
            if channel == "nightly" and not (tag == "nightly" and title == "Nightly"):
                bad.append(f"{fname}: entry {v['version']} is release '{tag}' titled '{title}', not Nightly")
            if channel == "experimental" and not (
                    (EXPERIMENTAL_TAG.match(tag) or LEGACY_EXPERIMENTAL_TAG.match(tag)) and title.startswith("Experimental:")):
                bad.append(f"{fname}: entry {v['version']} is release '{tag}' titled '{title}', not an experiment")
    if bad:
        sys.exit("REFUSING to write the install sources:\n  " + "\n  ".join(bad))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="MuffinEMU/Muffin-EMU")
    ap.add_argument("--out-dir", default="docs")
    a = ap.parse_args()
    token = os.environ.get("GITHUB_TOKEN")
    rels = releases(a.repo, token)
    run(a.repo, token, rels, a.out_dir)


def run(repo, token, rels, out_dir):
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

    experimentals = [
        ("experimental.json", "MuffinEMU.ipa", "com.kiddreads.MuffinEMU.experimental",
         "MuffinEMU Experimental",
         "Unfinished test builds, for testers.",
         "Wii U emulator - experimental test builds",
         EXPERIMENTAL_NOTE),
        ("experimental-trollstore.json", "MuffinEMU-fakesigned.ipa",
         "com.kiddreads.MuffinEMU.experimental.trollstore",
         "MuffinEMU Experimental (TrollStore)",
         "Unfinished test builds - TrollStore.",
         "Wii U emulator - experimental TrollStore builds",
         EXPERIMENTAL_NOTE + " This one is the ad-hoc signed build, with the JIT entitlements "
         "embedded, for TrollStore and jailbroken devices."),
    ]

    built = {}   # file name -> (channel, source)
    absent = []  # feeds that have nothing to serve right now
    for fname, asset, ident, name, subtitle, app_subtitle, note in feeds:
        src = build_source(rels, asset, ident, name, subtitle, app_subtitle, note)
        if src is None:
            print(f"skipped {fname}: no numbered release carries {asset} yet")
            continue
        built[fname] = ("stable", src)

    # The nightly feeds are allowed to be absent - the rolling tag only exists once a
    # build has published it - so a missing one is reported and skipped rather than
    # failing the run and blocking the stable feeds from updating. A nightly that EXISTS but is
    # not on main is different: that stops the run.
    if any(r.get("tag_name") == "nightly" for r in rels):
        check_nightly_on_main(repo, token)
    for fname, asset, ident, name, subtitle, app_subtitle, note in nightlies:
        src = build_nightly(rels, asset, ident, name, subtitle, app_subtitle, note)
        if src is None:
            print(f"skipped {fname}: the nightly release does not carry {asset} yet")
            continue
        built[fname] = ("nightly", src)

    for fname, asset, ident, name, subtitle, app_subtitle, note in experimentals:
        src = build_experimental(rels, repo, token, asset, ident, name, subtitle, app_subtitle, note)
        if src is None:
            print(f"no {fname}: no live experiment carries {asset}")
            absent.append(fname)
            continue
        built[fname] = ("experimental", src)

    if not any(ch == "stable" for ch, _ in built.values()):
        sys.exit("no numbered feeds written")
    check_guards(built, rels)

    os.makedirs(out_dir, exist_ok=True)
    for fname, (channel, src) in built.items():
        out = os.path.join(out_dir, fname)
        with open(out, "w", encoding="utf-8") as f:
            json.dump(src, f, indent=2, ensure_ascii=False)
            f.write("\n")
        v = src["apps"][0]["versions"]
        print(f"wrote {out}: {channel}, {len(v)} version(s), newest {v[0]['version']}")
    # An experimental feed with nothing live in it is removed rather than left stale.
    for fname in absent:
        stale = os.path.join(out_dir, fname)
        if os.path.exists(stale):
            os.remove(stale)
            print(f"removed {stale}: no live experiments")


if __name__ == "__main__":
    main()
