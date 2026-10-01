#!/usr/bin/env python3
"""audit_diff.py - compare two MuffinEMU Audit reports (muffinaudit.report/1) and list what changed.

    audit_diff.py KNOWN_GOOD.json CURRENT.json [--markdown out.md] [--json out.json]
                  [--fail-on regression|change|never] [--fps-drop-pct 10] [--p99-rise-pct 25]
                  [--memory-rise-pct 15] [--measure-shift 8]

Exit status: 0 when nothing regressed, 1 when something did (what counts is --fail-on), 2 when the files
cannot be compared (not reports, or different schema versions).

What it compares, test by test (matched by test id):
  * the verdict: pass -> fail is a regression, fail -> pass an improvement, other moves are changes
  * each checkpoint expectation and whole-test check by name: a flip, and a measured value that moved
    by more than --measure-shift even though both sides passed ("changed behaviour")
  * the listener's answers to the questionnaire, by question id
  * anomalies the audit detected on its own (new, resolved)
  * performance: present-interval statistics and memory footprint
  * the movement of the core's counters over the test (texture evictions, command-buffer errors, ...)
It also says plainly when the two reports are not like for like (different device, renderer, CPU mode or
catalogue), because then a difference is not necessarily a regression.
"""
import argparse
import json
import sys


def load(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict) or not str(data.get("schema", "")).startswith("muffinaudit.report/"):
        raise SystemExit(f"{path}: not a MuffinEMU Audit report (no muffinaudit.report schema field)")
    return data


def tests_by_id(report):
    """id -> list of test records (several when the run repeated the test)."""
    out = {}
    for t in report.get("tests", []):
        out.setdefault(t["id"], []).append(t)
    return out


def verdict(records):
    """One verdict for a test that may have run several times: the worst one, with the pass rate."""
    rank = {"error": 3, "fail": 2, "skip": 0, "pass": 1}
    worst = max(records, key=lambda r: rank.get(r["result"], 0))
    passed = sum(1 for r in records if r["result"] == "pass")
    return worst["result"], passed, len(records), worst


def exp_index(record):
    """(checkpoint, expectation name) -> result, taking the last run of a checkpoint name."""
    idx = {}
    for cp in record.get("checkpoints", []):
        for e in cp.get("expectations", []):
            idx[(cp["name"], e["name"])] = e
    return idx


def check_index(record):
    return {c["name"]: c for c in record.get("checks", [])}


def answer_index(record):
    return {a["questionId"]: a for a in record.get("answers", [])}


def anomaly_key(a):
    return (a.get("id", ""), a.get("subsystem", ""))


def pct(new, old):
    return 0.0 if not old else (new - old) / old * 100.0


def flatten_numbers(obj, prefix=""):
    out = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            out.update(flatten_numbers(v, f"{prefix}{k}."))
    elif isinstance(obj, bool):
        pass
    elif isinstance(obj, (int, float)):
        out[prefix[:-1]] = float(obj)
    return out


COUNTER_KEYS = (
    "gpuThread.drawableFailures", "gpuThread.erroredCommandBuffers", "gpuThread.timeouts", "gpuThread.cbErrorStreak",
    "gpuMemory.texturesEvicted", "gpuMemory.evictionPasses", "perf.pipelineSyncCompiles", "perf.shaderCompiles",
    "perf.pipelineCompiles", "perf.jitInvalidations", "perf.jitArenaAllocFails",
    "audio.underrunCallbacks", "audio.underrunFrames", "audio.discontinuities", "audio.feedRejects", "audio.silentCallbacks",
)


def diff(a, b, opts):
    res = {"regressions": [], "improvements": [], "changes": [], "newAnomalies": [], "resolvedAnomalies": [],
           "performance": [], "counters": [], "context": [], "notComparable": []}

    # ---- context: is this like for like?
    for label, pa, pb in (
        ("device", a["device"].get("machine"), b["device"].get("machine")),
        ("OS", a["device"].get("systemVersion"), b["device"].get("systemVersion")),
        ("renderer", a["config"].get("renderer"), b["config"].get("renderer")),
        ("CPU mode", a["config"].get("cpuModeReported"), b["config"].get("cpuModeReported")),
        ("GamePad surface", a["config"].get("padSurface"), b["config"].get("padSurface")),
        ("attended", a["config"].get("attended"), b["config"].get("attended")),
        ("frame readback", a["config"].get("captureAvailable"), b["config"].get("captureAvailable")),
        ("catalogue", a["tool"].get("catalogueHash"), b["tool"].get("catalogueHash")),
    ):
        if pa != pb:
            res["notComparable"].append(f"{label} differs: {pa} vs {pb}")
    ba, bb = a["build"], b["build"]
    for label, key in (("MuffinEMU ref", "muffinRef"), ("MuffinEMU commit", "muffinSha"), ("MuffinEMU version", "muffinVersion"),
                       ("core fingerprint", "coreFingerprint"), ("guest build", "guestBuild"), ("audit app", "auditAppBuild")):
        if ba.get(key) != bb.get(key):
            res["context"].append(f"{label}: {ba.get(key)} -> {bb.get(key)}")

    ta, tb = tests_by_id(a), tests_by_id(b)
    for tid in sorted(set(ta) | set(tb)):
        if tid not in tb:
            res["notComparable"].append(f"{tid} is only in the known-good report")
            continue
        if tid not in ta:
            res["notComparable"].append(f"{tid} is only in the current report")
            continue
        va, pa_, na, worst_a = verdict(ta[tid])
        vb, pb_, nb, worst_b = verdict(tb[tid])
        title = tb[tid][0].get("title", tid)
        rate_a, rate_b = f"{pa_}/{na}", f"{pb_}/{nb}"

        # verdict
        if va == "pass" and vb in ("fail", "error"):
            res["regressions"].append({"test": tid, "title": title, "what": f"{va} -> {vb}", "reason": worst_b.get("reason", ""),
                                       "passRate": f"{rate_a} -> {rate_b}", "subsystems": worst_b.get("subsystems", [])})
        elif va in ("fail", "error") and vb == "pass":
            res["improvements"].append({"test": tid, "title": title, "what": f"{va} -> {vb}", "was": worst_a.get("reason", ""), "passRate": f"{rate_a} -> {rate_b}"})
        elif va != vb:
            res["changes"].append({"test": tid, "title": title, "what": f"verdict {va} -> {vb}", "detail": worst_b.get("reason", "")})
        elif va == vb == "pass" and na > 1 and nb > 1 and pa_ / na != pb_ / nb:
            res["changes"].append({"test": tid, "title": title, "what": f"pass rate {rate_a} -> {rate_b}", "detail": ""})
        elif va == vb and va in ("fail", "error") and worst_a.get("reason") != worst_b.get("reason"):
            res["changes"].append({"test": tid, "title": title, "what": "still failing, for a different reason",
                                   "detail": f"{worst_a.get('reason', '')}  ->  {worst_b.get('reason', '')}"})

        ra, rb = ta[tid][-1], tb[tid][-1]

        # expectations and checks
        ea, eb = exp_index(ra), exp_index(rb)
        for key in sorted(set(ea) & set(eb)):
            x, y = ea[key], eb[key]
            label = f"{key[0]}/{key[1]}"
            if x["pass"] and not y["pass"] and y.get("severity") == "fail":
                res["regressions"].append({"test": tid, "title": title, "what": f"expectation {label} now fails", "reason": y.get("measured", ""), "subsystems": rb.get("subsystems", [])})
            elif not x["pass"] and y["pass"] and x.get("severity") == "fail":
                res["improvements"].append({"test": tid, "title": title, "what": f"expectation {label} now passes", "was": x.get("measured", "")})
            else:
                for vk in sorted(set(x.get("values", {})) & set(y.get("values", {}))):
                    if vk in ("inconclusive", "confidence"):
                        continue
                    shift = y["values"][vk] - x["values"][vk]
                    if abs(shift) > opts.measure_shift and x["pass"] == y["pass"]:
                        res["changes"].append({"test": tid, "title": title, "what": f"{label}: {vk} moved {x['values'][vk]:.1f} -> {y['values'][vk]:.1f}",
                                               "detail": "both runs " + ("passed" if x["pass"] else "failed")})
                        break
        for key in sorted(set(ea) - set(eb)):
            res["notComparable"].append(f"{tid}: checkpoint expectation {key[0]}/{key[1]} is only in the known-good report")
        ca, cb = check_index(ra), check_index(rb)
        for name in sorted(set(ca) & set(cb)):
            x, y = ca[name], cb[name]
            if x["pass"] and not y["pass"] and y.get("severity") == "fail":
                res["regressions"].append({"test": tid, "title": title, "what": f"check {name} now fails", "reason": y.get("summary", ""), "subsystems": rb.get("subsystems", [])})
            elif not x["pass"] and y["pass"] and x.get("severity") == "fail":
                res["improvements"].append({"test": tid, "title": title, "what": f"check {name} now passes", "was": x.get("summary", "")})
            elif x["pass"] != y["pass"]:
                res["changes"].append({"test": tid, "title": title, "what": f"check {name}: {'pass' if x['pass'] else 'warn/fail'} -> {'pass' if y['pass'] else 'warn/fail'}", "detail": y.get("summary", "")})

        # the listener
        qa, qb = answer_index(ra), answer_index(rb)
        for qid in sorted(set(qa) & set(qb)):
            if qa[qid]["bad"] != qb[qid]["bad"] or qa[qid]["answer"] != qb[qid]["answer"]:
                row = {"test": tid, "title": title, "what": f"answer to '{qb[qid]['question']}': {qa[qid]['answer']} -> {qb[qid]['answer']}", "detail": ""}
                if not qa[qid]["bad"] and qb[qid]["bad"] and qb[qid].get("severity") != "info":
                    row["reason"] = "the listener now reports a problem"
                    row["subsystems"] = rb.get("subsystems", [])
                    res["regressions"].append(row)
                elif qa[qid]["bad"] and not qb[qid]["bad"]:
                    res["improvements"].append({"test": tid, "title": title, "what": row["what"], "was": "reported as a problem"})
                else:
                    res["changes"].append(row)

        # anomalies
        aa, ab = {anomaly_key(x): x for x in ra.get("anomalies", [])}, {anomaly_key(x): x for x in rb.get("anomalies", [])}
        for k in sorted(set(ab) - set(aa)):
            x = ab[k]
            res["newAnomalies"].append({"test": tid, "severity": x["severity"], "subsystem": x["subsystem"], "message": x["message"], "evidence": x.get("evidence", [])[:2]})
            if x["severity"] == "fail" and vb == "pass":
                res["regressions"].append({"test": tid, "title": title, "what": f"new failing anomaly: {x['subsystem']}", "reason": x["message"], "subsystems": rb.get("subsystems", [])})
        for k in sorted(set(aa) - set(ab)):
            x = aa[k]
            res["resolvedAnomalies"].append({"test": tid, "severity": x["severity"], "subsystem": x["subsystem"], "message": x["message"]})

        # performance
        pfa, pfb = ra.get("performance", {}), rb.get("performance", {})
        fa, fb = pfa.get("frameIntervals"), pfb.get("frameIntervals")
        if fa and fb and fa.get("count", 0) >= 30 and fb.get("count", 0) >= 30:
            if fa["fps"] > 0 and pct(fb["fps"], fa["fps"]) < -opts.fps_drop_pct:
                res["performance"].append({"test": tid, "what": f"frame rate {fa['fps']:.1f} -> {fb['fps']:.1f} fps ({pct(fb['fps'], fa['fps']):+.0f}%)", "regression": True})
            if fa["p99Ms"] > 0 and pct(fb["p99Ms"], fa["p99Ms"]) > opts.p99_rise_pct and fb["p99Ms"] - fa["p99Ms"] > 4:
                res["performance"].append({"test": tid, "what": f"99th percentile frame time {fa['p99Ms']:.1f} -> {fb['p99Ms']:.1f} ms", "regression": True})
            if fb.get("veryLong", 0) > fa.get("veryLong", 0) + 2:
                res["performance"].append({"test": tid, "what": f"frames over 2.5x the median {fa.get('veryLong', 0)} -> {fb.get('veryLong', 0)}", "regression": True})
        ma, mb = pfa.get("footprintPeakMB", 0), pfb.get("footprintPeakMB", 0)
        if ma > 0 and pct(mb, ma) > opts.memory_rise_pct and mb - ma > 50:
            res["performance"].append({"test": tid, "what": f"peak memory footprint {ma:.0f} -> {mb:.0f} MB", "regression": True})
        if pfa.get("availableMinMB", 0) > 0 and pfb.get("availableMinMB", 0) > 0 and pfb["availableMinMB"] < pfa["availableMinMB"] - 200:
            res["performance"].append({"test": tid, "what": f"lowest headroom before iOS would end the app {pfa['availableMinMB']:.0f} -> {pfb['availableMinMB']:.0f} MB", "regression": True})

        # counters
        na_, nb_ = flatten_numbers(ra.get("snapshotDelta") or {}), flatten_numbers(rb.get("snapshotDelta") or {})
        for k in COUNTER_KEYS:
            x, y = na_.get(k, 0.0), nb_.get(k, 0.0)
            if x == y:
                continue
            if (x == 0 and y > 0) or (x > 0 and y >= 3 * x and y - x >= 3):
                res["counters"].append({"test": tid, "counter": k, "was": x, "now": y})

    return res


def render_markdown(res, a, b):
    o = ["# MuffinEMU Audit: report comparison", ""]
    ba, bb = a["build"], b["build"]
    o.append(f"Known good: `{ba.get('muffinRef')}` @ `{str(ba.get('muffinSha'))[:10]}` (core `{str(ba.get('coreFingerprint'))[:12]}`), {a['device'].get('machine')}, run {a.get('createdAt')}")
    o.append(f"Current: `{bb.get('muffinRef')}` @ `{str(bb.get('muffinSha'))[:10]}` (core `{str(bb.get('coreFingerprint'))[:12]}`), {b['device'].get('machine')}, run {b.get('createdAt')}")
    o.append("")
    n = len(res["regressions"])
    o.append(f"**{n} regression(s), {len(res['improvements'])} improvement(s), {len(res['changes'])} changed behaviour(s), "
             f"{len(res['newAnomalies'])} new anomaly(ies), {len([p for p in res['performance'] if p['regression']])} performance change(s).**")
    o.append("")

    def section(title, rows, fmt):
        if not rows:
            return
        o.append(f"## {title}")
        o.append("")
        for r in rows:
            o.append("- " + fmt(r))
        o.append("")

    section("Not like for like", res["notComparable"], lambda r: r)
    section("What differs between the builds", res["context"], lambda r: r)
    section("Regressions", res["regressions"], lambda r: f"**{r['test']}** ({r['title']}): {r['what']}" + (f" - {r['reason']}" if r.get("reason") else "") + (f" [{', '.join(r.get('subsystems', []))}]" if r.get("subsystems") else ""))
    section("Improvements", res["improvements"], lambda r: f"**{r['test']}** ({r['title']}): {r['what']}" + (f" (was: {r['was']})" if r.get("was") else ""))
    section("Changed behaviour", res["changes"], lambda r: f"**{r['test']}** ({r['title']}): {r['what']}" + (f" - {r['detail']}" if r.get("detail") else ""))
    section("New anomalies", res["newAnomalies"], lambda r: f"**{r['test']}** [{r['severity']}] {r['subsystem']}: {r['message']}" + (f" ({'; '.join(r['evidence'])})" if r.get("evidence") else ""))
    section("Resolved anomalies", res["resolvedAnomalies"], lambda r: f"**{r['test']}** [{r['severity']}] {r['subsystem']}: {r['message']}")
    section("Performance", res["performance"], lambda r: f"**{r['test']}**: {r['what']}")
    section("Core counters that moved", res["counters"], lambda r: f"**{r['test']}**: {r['counter']} {r['was']:.0f} -> {r['now']:.0f}")
    if not any(res[k] for k in ("regressions", "improvements", "changes", "newAnomalies", "resolvedAnomalies", "performance", "counters")):
        o.append("No differences in behaviour, anomalies, performance or counters.")
    return "\n".join(o) + "\n"


def main(argv=None):
    p = argparse.ArgumentParser(description="Compare two MuffinEMU Audit reports.")
    p.add_argument("known_good")
    p.add_argument("current")
    p.add_argument("--markdown")
    p.add_argument("--json")
    p.add_argument("--fail-on", choices=("regression", "change", "never"), default="regression")
    p.add_argument("--fps-drop-pct", type=float, default=10.0)
    p.add_argument("--p99-rise-pct", type=float, default=25.0)
    p.add_argument("--memory-rise-pct", type=float, default=15.0)
    p.add_argument("--measure-shift", type=float, default=8.0, help="a measured value (colour channel, level, ...) that moved by more than this is reported")
    opts = p.parse_args(argv)

    a, b = load(opts.known_good), load(opts.current)
    if a["schema"] != b["schema"]:
        print(f"cannot compare {a['schema']} with {b['schema']}", file=sys.stderr)
        return 2
    res = diff(a, b, opts)
    md = render_markdown(res, a, b)
    if opts.markdown:
        with open(opts.markdown, "w", encoding="utf-8") as f:
            f.write(md)
    if opts.json:
        with open(opts.json, "w", encoding="utf-8") as f:
            json.dump({"schema": "muffinaudit.diff/1", "knownGood": {"build": a["build"], "device": a["device"]}, "current": {"build": b["build"], "device": b["device"]}, **res}, f, indent=1)
    print(md)
    regressed = bool(res["regressions"]) or any(p["regression"] for p in res["performance"])
    changed = regressed or bool(res["changes"]) or bool(res["newAnomalies"]) or bool(res["counters"])
    if opts.fail_on == "never":
        return 0
    if opts.fail_on == "change":
        return 1 if changed else 0
    return 1 if regressed else 0


if __name__ == "__main__":
    sys.exit(main())
