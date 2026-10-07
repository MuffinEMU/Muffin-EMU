#!/usr/bin/env python3
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

"""Tests for ci/generate-sidestore-source.py: which release may appear in which feed, and that the
guards refuse to write a wrong one. No network: the GitHub API is replaced by a fake.

Run:  python3 ci/test-generator.py
"""
import importlib.util, json, os, sys, tempfile

spec = importlib.util.spec_from_file_location("gen", os.path.join(os.path.dirname(__file__), "generate-sidestore-source.py"))
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

BASE = "https://github.com/MuffinEMU/Muffin-EMU/releases/download"


def rel(tag, name, pre=False, published="2026-09-30T20:00:00Z", body="", assets=("MuffinEMU.ipa", "MuffinEMU-fakesigned.ipa")):
    return {"tag_name": tag, "name": name, "prerelease": pre, "draft": False, "published_at": published,
            "created_at": published, "body": body, "html_url": f"https://github.com/MuffinEMU/Muffin-EMU/releases/tag/{tag}",
            "assets": [{"name": a, "size": 1000, "browser_download_url": f"{BASE}/{tag}/{a}",
                        "updated_at": published} for a in assets]}


STABLE = [rel("v6.1", "MuffinEMU 6.1", body="## What changed\n\n- A thing\n"), rel("v6.0", "MuffinEMU 6.0")]
NIGHTLY = rel("nightly", "Nightly", pre=True, published="2026-09-16T23:34:20Z")
EXP1 = rel("auto-d0265b15c5152a0d7ede065ec77aad5954b68c99", "Experimental: Shader cache (feature/metal-binary-archive @ d0265b1)",
           pre=True, published="2026-09-30T21:29:22Z")
EXP2 = rel("auto-be1f2980aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Experimental: TouchLab (feature/touchlab-controls @ be1f298)",
           pre=True, published="2026-09-30T21:10:00Z")
EXP3 = rel("experimental-fix-x-1234567", "Experimental: Fix X (fix/x @ 1234567)", pre=True, published="2026-10-01T09:05:00Z",
           body="**Experimental build.** ...\n- **Based on:** main `abc1234` (v6.1), plus 2 commit(s) on the branch\n\n## What changed\n\n- Fixed X\n\n")
ROLLING = rel("experimental", "Experimental: latest - Fix X (fix/x @ 1234567)", pre=True, published="2026-10-01T09:06:00Z")
JUNK = rel("auto-ffffffffffffffffffffffffffffffffffffffff", "MuffinEMU test build ffff", pre=True)  # old-style test build, untitled as experimental


class FakeApi:
    """Branches: live unless listed in dead/merged. Nightly's tag sits on main unless told otherwise."""
    def __init__(self, dead=(), merged=(), nightly_status="behind"):
        self.dead, self.merged, self.nightly_status = set(dead), set(merged), nightly_status

    def __call__(self, repo, path, token, allow_404=False):
        if path.startswith("git/ref/tags/nightly"):
            return {"object": {"type": "commit", "sha": "a" * 40}}
        if path.startswith("compare/main..."):
            head = path.split("...", 1)[1]
            if head == "a" * 40:
                return {"status": self.nightly_status}
            return {"status": "behind" if head in self.merged else "ahead"}
        if path.startswith("branches/"):
            b = path[len("branches/"):]
            return None if b in self.dead else {"name": b}
        raise AssertionError("unexpected API call " + path)


def run(rels, api):
    gen.api = api
    out = tempfile.mkdtemp()
    gen.run("MuffinEMU/Muffin-EMU", None, rels, out)
    return out, {f: json.load(open(os.path.join(out, f))) for f in os.listdir(out)}


def expect_exit(fn, needle):
    try:
        fn()
    except SystemExit as e:
        assert needle in str(e.code), f"exit message {e.code!r} lacks {needle!r}"
        return
    raise AssertionError(f"expected the run to be refused ({needle})")


def urls(feed):
    return [v["downloadURL"] for v in feed["apps"][0]["versions"]]


ALL = STABLE + [NIGHTLY, EXP1, EXP2, EXP3, ROLLING, JUNK]

# 1. Each feed reads only its own channel.
out, f = run(ALL, FakeApi())
assert sorted(f) == ["apps.json", "experimental-trollstore.json", "experimental.json", "nightly-trollstore.json", "nightly.json", "trollstore.json"], sorted(f)
assert all("/v6." in u for u in urls(f["apps.json"])), urls(f["apps.json"])
assert urls(f["nightly.json"]) == [f"{BASE}/nightly/MuffinEMU.ipa"]
ex = urls(f["experimental.json"])
assert ex == [f"{BASE}/experimental-fix-x-1234567/MuffinEMU.ipa", f"{BASE}/auto-d0265b15c5152a0d7ede065ec77aad5954b68c99/MuffinEMU.ipa",
              f"{BASE}/auto-be1f2980aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/MuffinEMU.ipa"], ex   # newest first; no rolling, no junk
assert all("/experimental" not in json.dumps(f[n]) for n in ("apps.json", "trollstore.json", "nightly.json", "nightly-trollstore.json"))
assert all(x.endswith("MuffinEMU-fakesigned.ipa") for x in urls(f["experimental-trollstore.json"]))
print("ok: channels are separated; legacy auto-<sha> experiments are accepted by title; the rolling release and untitled test builds are not")

# 2. Shape of the experimental feed.
app = f["experimental.json"]["apps"][0]
assert app["name"] == "MuffinEMU Experimental" and app["bundleIdentifier"] == "com.kiddreads.MuffinEMU"
assert "unfinished test builds" in app["localizedDescription"] and "Stable" in app["localizedDescription"]
vs = [v["version"] for v in app["versions"]]
assert vs == ["2026.10.1.0905", "2026.9.30.2129", "2026.9.30.2110"], vs
d0 = app["versions"][0]["localizedDescription"]
assert "Experiment: Fix X" in d0 and "Branch: fix/x" in d0 and "Commit: 1234567" in d0 and "Based on: main `abc1234` (v6.1)" in d0 and "- Fixed X" in d0, d0
assert [n["title"] for n in f["experimental.json"]["news"]][0] == "Experimental: Fix X"
print("ok: one app entry, every experiment a version newest first, sortable versions, per-version description, news per experiment")

# 3. Dead and merged branches drop out; the cap is 10.
out, f = run(ALL, FakeApi(dead={"feature/touchlab-controls"}, merged={"fix/x"}))
assert urls(f["experimental.json"]) == [f"{BASE}/auto-d0265b15c5152a0d7ede065ec77aad5954b68c99/MuffinEMU.ipa"]
many = [rel(f"experimental-b{i}-000000{i % 10}", f"Experimental: E{i} (b{i} @ 000000{i % 10})", pre=True,
            published=f"2026-10-{i + 1:02d}T10:00:00Z") for i in range(14)]
out, f = run(STABLE + many, FakeApi())
assert len(f["experimental.json"]["apps"][0]["versions"]) == 10
out, f = run(STABLE + [EXP1], FakeApi(dead={"feature/metal-binary-archive"}))
assert "experimental.json" not in f, "a feed with nothing live must not be written"
print("ok: dead and merged branches are dropped, capped at 10, an empty feed is not written")

# 4. The nightly must be on main.
expect_exit(lambda: run(ALL, FakeApi(nightly_status="diverged")), "not reachable from main")
expect_exit(lambda: run(ALL, FakeApi(nightly_status="ahead")), "not reachable from main")
run(ALL, FakeApi(nightly_status="identical"))
print("ok: a nightly whose commit is not on main stops the update")

# 5. The guards refuse, and write nothing.
def guard(feeds, rels, needle):
    expect_exit(lambda: gen.check_guards(feeds, rels), needle)

good = gen.build_source(STABLE, "MuffinEMU.ipa", "i", "n", "s", "a", "x")
bad = json.loads(json.dumps(good))
bad["apps"][0]["versions"][0]["downloadURL"] = f"{BASE}/experimental/MuffinEMU.ipa"
guard({"apps.json": ("stable", bad)}, STABLE + [ROLLING], "mentions an experimental URL")
gen.api = FakeApi()
exp = gen.build_experimental(ALL, "MuffinEMU/Muffin-EMU", None, "MuffinEMU.ipa", "i", "n", "s", "a", "x")
bad = json.loads(json.dumps(exp)); bad["apps"][0]["versions"][0]["downloadURL"] = f"{BASE}/nightly/MuffinEMU.ipa"
guard({"experimental.json": ("experimental", bad)}, ALL, "points at nightly")
bad = json.loads(json.dumps(exp)); bad["apps"][0]["versions"][0]["downloadURL"] = f"{BASE}/v6.1/MuffinEMU.ipa"
guard({"experimental.json": ("experimental", bad)}, ALL, "numbered release")
bad = json.loads(json.dumps(exp)); bad["apps"][0]["versions"][0]["downloadURL"] = f"{BASE}/experimental/MuffinEMU.ipa"
guard({"experimental.json": ("experimental", bad)}, ALL, "rolling `experimental`")
# title prefix vs channel: an experiment-looking tag whose release is not titled Experimental
wrong = rel("experimental-oops-1234567", "MuffinEMU 9.9", pre=True)
bad = json.loads(json.dumps(exp)); bad["apps"][0]["versions"][0]["downloadURL"] = f"{BASE}/experimental-oops-1234567/MuffinEMU.ipa"
guard({"experimental.json": ("experimental", bad)}, ALL + [wrong], "not an experiment")
badstable = json.loads(json.dumps(good)); badstable["apps"][0]["versions"][0]["downloadURL"] = f"{BASE}/v6.1/MuffinEMU.ipa"
guard({"apps.json": ("stable", badstable)}, [rel("v6.1", "Experimental: sneaky (x @ 1234567)")], "not a numbered MuffinEMU release")
nightly_bad = gen.build_nightly([rel("nightly", "MuffinEMU 7.0", pre=True)], "MuffinEMU.ipa", "i", "n", "s", "a", "x")
guard({"nightly.json": ("nightly", nightly_bad)}, [rel("nightly", "MuffinEMU 7.0", pre=True)], "not Nightly")
print("ok: every guard refuses")

# 6. A refused run writes nothing.
out = tempfile.mkdtemp()
gen.api = FakeApi()
leak = rel("v6.2", "Experimental: leaked (x @ 1234567)")   # an experiment published under a version tag
expect_exit(lambda: gen.run("MuffinEMU/Muffin-EMU", None, [leak, NIGHTLY], out), "REFUSING")
assert os.listdir(out) == [], os.listdir(out)
print("ok: a refused run leaves the existing feeds untouched")
print("all generator tests passed")
