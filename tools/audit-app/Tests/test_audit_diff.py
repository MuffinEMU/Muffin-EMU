#!/usr/bin/env python3
"""Tests for audit_diff.py, run by the audit workflow's checks job against the sample report the Swift
logic tests write (AUDIT_SAMPLE_OUT), so the diff is exercised on the real writer's output.

    python3 Tests/test_audit_diff.py path/to/sample-report.json
"""
import copy
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DIFF = os.path.join(HERE, "..", "audit_diff.py")
failures = 0


def check(cond, what):
    global failures
    if not cond:
        failures += 1
        print("FAIL:", what)


def run(a, b, *extra):
    with tempfile.TemporaryDirectory() as d:
        pa, pb = os.path.join(d, "a.json"), os.path.join(d, "b.json")
        json.dump(a, open(pa, "w"))
        json.dump(b, open(pb, "w"))
        md, js = os.path.join(d, "o.md"), os.path.join(d, "o.json")
        p = subprocess.run([sys.executable, DIFF, pa, pb, "--markdown", md, "--json", js, *extra], capture_output=True, text=True)
        return p.returncode, p.stdout, (json.load(open(js)) if os.path.exists(js) else None), p.stderr


def main(sample):
    base = json.load(open(sample))
    tests = {t["id"]: t for t in base["tests"]}
    check("bs.a" in tests and "bs.b" in tests, "sample has the two tests")

    # Identical reports: nothing to say, exit 0.
    code, out, js, err = run(base, copy.deepcopy(base))
    check(code == 0 and "No differences" in out, f"identical reports differ? code={code}\n{out}{err}")

    # A regression and an improvement at once.
    cur = copy.deepcopy(base)
    a = next(t for t in cur["tests"] if t["id"] == "bs.a")
    b = next(t for t in cur["tests"] if t["id"] == "bs.b")
    a["result"] = "fail"
    a["reason"] = "red: black"
    a["checkpoints"][0]["expectations"][0].update({"pass": False, "measured": "black", "values": {"maxDiff": 255}})
    b["result"] = "pass"
    b["reason"] = "ok"
    b["checkpoints"][0]["expectations"][0].update({"pass": True, "measured": "red", "values": {"maxDiff": 0}})
    cur["build"]["muffinSha"] = "fedcba9876543210"
    code, out, js, err = run(base, cur)
    check(code == 1, "a regression exits 1")
    check(any(r["test"] == "bs.a" and r["what"] == "pass -> fail" for r in js["regressions"]), "bs.a is reported as a regression")
    check(any(r["test"] == "bs.b" and r["what"] == "fail -> pass" for r in js["improvements"]), "bs.b is reported as an improvement")
    check(any("MuffinEMU commit" in c for c in js["context"]), "the commit difference is listed")
    check("Regressions" in out and "bs.a" in out, "the Markdown names the regression")
    code, _, _, _ = run(base, cur, "--fail-on", "never")
    check(code == 0, "--fail-on never always exits 0")

    # Behaviour change with both passing: a measured value moved.
    cur = copy.deepcopy(base)
    a = next(t for t in cur["tests"] if t["id"] == "bs.a")
    a["checkpoints"][0]["expectations"][0]["values"]["maxDiff"] = 40
    code, out, js, err = run(base, cur)
    check(code == 0 and any("maxDiff moved" in c["what"] for c in js["changes"]), "a moved measurement is changed behaviour")
    code, _, _, _ = run(base, cur, "--fail-on", "change")
    check(code == 1, "--fail-on change exits 1 on changed behaviour")

    # Anomalies, performance, counters.
    cur = copy.deepcopy(base)
    a = next(t for t in cur["tests"] if t["id"] == "bs.a")
    a["anomalies"].append({"id": "counter.gpu_error", "kind": "gpu_error", "severity": "fail", "subsystem": "render.gpu", "message": "The GPU reported an error", "evidence": ["x"]})
    a["performance"]["frameIntervals"]["fps"] = 40.0
    a["performance"]["frameIntervals"]["p99Ms"] = 60.0
    a["performance"]["footprintPeakMB"] = 900.0
    a["snapshotDelta"] = {"gpuMemory": {"texturesEvicted": 50}}
    code, out, js, err = run(base, cur)
    check(any(x["subsystem"] == "render.gpu" for x in js["newAnomalies"]), "a new anomaly is listed")
    check(any(r["test"] == "bs.a" and "new failing anomaly" in r["what"] for r in js["regressions"]), "a new failing anomaly on a passing test is a regression")
    check(any("frame rate" in p["what"] for p in js["performance"]), "an fps drop is flagged")
    check(any("99th percentile" in p["what"] for p in js["performance"]), "a p99 rise is flagged")
    check(any("peak memory" in p["what"] for p in js["performance"]), "a memory rise is flagged")
    check(any(c["counter"] == "gpuMemory.texturesEvicted" for c in js["counters"]), "a counter that started moving is listed")
    check(code == 1, "performance regressions exit 1")

    # Not like for like.
    cur = copy.deepcopy(base)
    cur["device"]["machine"] = "iPhone17,1"
    cur["config"]["renderer"] = "vulkan"
    code, out, js, err = run(base, cur)
    check(any("device differs" in n for n in js["notComparable"]) and any("renderer differs" in n for n in js["notComparable"]), "a different device and renderer are called out")

    # Not a report.
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "x.json")
        json.dump({"hello": 1}, open(p, "w"))
        r = subprocess.run([sys.executable, DIFF, p, p], capture_output=True, text=True)
        check(r.returncode != 0, "a non-report is refused")

    print(f"test_audit_diff: {'FAILED' if failures else 'all checks passed'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
