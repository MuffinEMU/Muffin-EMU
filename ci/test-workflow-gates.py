#!/usr/bin/env python3
# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

# MuffinEMU — code by the MuffinEMU Development Team.
# Copyright (c) 2026 MuffinEMU Development Team.
# SPDX-License-Identifier: MPL-2.0
# This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

"""Which publishing steps and jobs of build-ios-app.yml run for each kind of trigger.

It takes the REAL `if:` expressions from the workflow, the REAL channel decision
(ci/decide-channel.sh run as a subprocess), and evaluates them for every scenario, so the claims
"a feature-branch dispatch cannot publish nightly", "a main build can", "an experimental dispatch
publishes only experimental-*" are checked against the workflow as written, not against a description
of it. Run: python3 ci/test-workflow-gates.py
"""
import os, re, subprocess, sys
import yaml

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
wf = yaml.safe_load(open(os.path.join(ROOT, ".github/workflows/build-ios-app.yml")))
jobs = wf["jobs"]
build = jobs["build-app"]


def evaluate(expr, ctx):
    expr = " ".join(str(expr).split())
    # names like steps.channel.outputs.channel, needs.build-app.outputs.channel, github.ref
    def sub(m):
        return f"ctx.get({m.group(0)!r}, '')"
    py = re.sub(r"(?<![\w.'])(?:github|needs|steps|inputs|env)(?:\.[\w\-]+)+", sub, expr)
    py = py.replace("&&", " and ").replace("||", " or ")
    py = re.sub(r"!(?!=)", " not ", py)
    return bool(eval(py, {"ctx": ctx}))


def decide(event, ref, ref_name, channel_input="", name=""):
    env = dict(os.environ, EVENT=event, REF=ref, REF_NAME=ref_name, SHA="a" * 40, INPUT_CHANNEL=channel_input,
               INPUT_NAME=name, GITHUB_OUTPUT="/dev/stdout")
    p = subprocess.run([os.path.join(ROOT, "ci/decide-channel.sh")], env=env, capture_output=True, text=True)
    if p.returncode != 0:
        return None
    out = dict(l.split("=", 1) for l in p.stdout.splitlines() if re.match(r"^[a-z_0-9]+=", l))
    return out["channel"]


stable_steps = [s for s in build["steps"] if "softprops/action-gh-release" in str(s.get("uses", ""))]
assert len(stable_steps) == 2, "expected exactly the publish step and its retry"
for s in stable_steps:
    assert s["with"]["tag_name"] != "nightly" and "nightly" not in str(s["with"]), "a build-app release step touches nightly"

failures = []


def check(name, cond, detail=""):
    print(("ok:   " if cond else "FAIL: ") + name + ("" if cond else f"  {detail}"))
    if not cond:
        failures.append(name)


def outcome(event, ref, ref_name, channel_input="", name=""):
    ch = decide(event, ref, ref_name, channel_input, name)
    if ch is None:
        return dict(channel=None, stable=False, nightly=False, experimental=False)
    ctx = {"github.event_name": event, "github.ref": ref, "steps.channel.outputs.channel": ch,
           "needs.build-app.outputs.channel": ch, "steps.publish.outcome": "failure", "env.MUFFIN_PUBLISH": "true"}
    return dict(
        channel=ch,
        stable=any(evaluate(s["if"], ctx) for s in stable_steps),
        nightly=evaluate(jobs["publish-nightly"]["if"], ctx),
        experimental=evaluate(jobs["publish-experimental"]["if"], ctx),
    )


M, F = "refs/heads/main", "refs/heads/feature/x"
SCENARIOS = [
    ("push to main",                                   outcome("push", M, "main"),                                   dict(stable=True,  nightly=True,  experimental=False)),
    ("dispatch on main",                               outcome("workflow_dispatch", M, "main", "artifacts-only"),    dict(stable=True,  nightly=True,  experimental=False)),
    ("dispatch on main, no inputs",                    outcome("workflow_dispatch", M, "main"),                      dict(stable=True,  nightly=True,  experimental=False)),
    ("dispatch on a feature branch, artifacts-only",   outcome("workflow_dispatch", F, "feature/x", "artifacts-only"), dict(stable=False, nightly=False, experimental=False)),
    ("dispatch on a feature branch, no inputs",        outcome("workflow_dispatch", F, "feature/x"),                 dict(stable=False, nightly=False, experimental=False)),
    ("dispatch on a feature branch, experimental",     outcome("workflow_dispatch", F, "feature/x", "experimental", "Shader cache"), dict(stable=False, nightly=False, experimental=True)),
    ("push to ios27-sdk (it used to overwrite nightly)", outcome("push", "refs/heads/ios27-sdk", "ios27-sdk"),       dict(stable=False, nightly=False, experimental=False)),
    ("push to some other branch",                      outcome("push", F, "feature/x"),                              dict(stable=False, nightly=False, experimental=False)),
    ("pull request",                                   outcome("pull_request", "refs/pull/7/merge", "7/merge"),      dict(stable=False, nightly=False, experimental=False)),
    ("a pull request whose head is named main",        outcome("pull_request", "refs/pull/7/merge", "main"),         dict(stable=False, nightly=False, experimental=False)),
    ("dispatch on main asking for experimental (refused outright)", outcome("workflow_dispatch", M, "main", "experimental"), dict(stable=False, nightly=False, experimental=False)),
    ("schedule",                                       outcome("schedule", M, "main"),                               dict(stable=False, nightly=False, experimental=False)),
]
for name, got, want in SCENARIOS:
    check(f"{name}: stable={want['stable']} nightly={want['nightly']} experimental={want['experimental']}",
          all(got[k] == v for k, v in want.items()), f"got {got}")

# A wrong channel value must not be enough on its own: the ref and event are checked directly too.
for ev, ref, ch, label in [("workflow_dispatch", F, "main", "feature branch + a (buggy) channel=main"),
                           ("pull_request", "refs/pull/7/merge", "main", "pull request + channel=main"),
                           ("push", "refs/heads/ios27-sdk", "main", "ios27-sdk + channel=main")]:
    ctx = {"github.event_name": ev, "github.ref": ref, "steps.channel.outputs.channel": ch, "needs.build-app.outputs.channel": ch,
           "steps.publish.outcome": "failure"}
    check(f"{label}: nightly still cannot publish", not evaluate(jobs["publish-nightly"]["if"], ctx))
    check(f"{label}: stable still cannot publish", not any(evaluate(s["if"], ctx) for s in stable_steps))
# The stable guard: a main build that is not strictly newer than the latest release (an old re-run) is
# marked MUFFIN_PUBLISH=false by "Choose the version", and then neither publish step runs.
ctx = {"github.event_name": "push", "github.ref": M, "steps.channel.outputs.channel": "main", "needs.build-app.outputs.channel": "main",
       "steps.publish.outcome": "failure", "env.MUFFIN_PUBLISH": "false"}
check("an old re-run of main (MUFFIN_PUBLISH=false): no numbered release, not even the retry", not any(evaluate(s["if"], ctx) for s in stable_steps))
check("...and its nightly is still decided by the nightly job's own guards", evaluate(jobs["publish-nightly"]["if"], ctx))
ctx = {"github.event_name": "push", "github.ref": M, "steps.channel.outputs.channel": "experimental", "needs.build-app.outputs.channel": "experimental"}
check("main + a (buggy) channel=experimental: nothing publishes", not evaluate(jobs["publish-nightly"]["if"], ctx) and not evaluate(jobs["publish-experimental"]["if"], ctx))

# Structure.
check("publish-nightly runs in the `nightly` environment", jobs["publish-nightly"].get("environment") == "nightly")
check("publish-nightly needs build-app", jobs["publish-nightly"]["needs"] == "build-app")
check("nothing else uses the nightly environment", [n for n, j in jobs.items() if j.get("environment") == "nightly"] == ["publish-nightly"])
check("the experimental job has no environment that could be confused with nightly", "environment" not in jobs["publish-experimental"])
text = open(os.path.join(ROOT, ".github/workflows/build-ios-app.yml")).read()
check("build-app no longer has a nightly step", "Update the rolling nightly" not in text and text.count("tag_name: nightly") == 0)
runs = [str(st.get("run", "")) for j in jobs.values() for st in j["steps"]]
check("the only step that runs ci/publish-nightly.sh is in publish-nightly",
      sum("publish-nightly.sh" in r for r in runs) == 1 and any("publish-nightly.sh" in str(st.get("run", "")) for st in jobs["publish-nightly"]["steps"]))
check("no step outside publish-nightly mentions the nightly release in a gh/softprops call",
      not any("nightly" in str(st) for st in build["steps"] if "release" in str(st).lower() and "notes" not in str(st.get("name", "")).lower()))

print("all workflow gate tests passed" if not failures else f"{len(failures)} workflow gate test(s) failed")
sys.exit(1 if failures else 0)
