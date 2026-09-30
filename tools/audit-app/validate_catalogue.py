#!/usr/bin/env python3
"""validate_catalogue.py - checks the test catalogue (Catalogue/suite-*.json) against its JSON Schema and against
the guest program it drives, so a typo in a catalogue file fails CI instead of producing a test that silently
measures nothing.

    validate_catalogue.py [--catalogue DIR] [--guest DIR] [--schema FILE]

It checks that every guest test exists in the guest's test tables, every parameter the catalogue passes is one the
guest reads, every checkpoint name is one the guest raises, every expectation is inside the frame, test ids are
unique, and there is exactly one calibration test.
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BUTTONS = {"A", "B", "X", "Y", "L", "R", "ZL", "ZR", "PLUS", "MINUS", "UP", "DOWN", "LEFT", "RIGHT", "STICK_L", "STICK_R"}


def guest_facts(guest_dir):
    tests, params, literal_cps, prefix_cps = set(), set(), set(), set()
    for path in glob.glob(os.path.join(guest_dir, "*.c")):
        src = open(path, encoding="utf-8").read()
        tests |= set(re.findall(r'\{\s*"([a-z0-9_]+)"\s*,\s*Test[A-Za-z0-9]+\s*\}', src))
        params |= set(re.findall(r'Param(?:Int|Str)\(\s*ctx\s*,\s*"([A-Za-z0-9_]+)"', src))
        literal_cps |= set(re.findall(r'HoldScene\(\s*ctx\s*,\s*"([^"]+)"', src))
        prefix_cps |= {m for m in re.findall(r'snprintf\(\s*name\s*,\s*sizeof\(name\)\s*,\s*"([^"%]+)%', src)}
    return tests, params, literal_cps, prefix_cps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalogue", default=os.path.join(HERE, "Catalogue"))
    ap.add_argument("--guest", default=os.path.join(HERE, "guest"))
    ap.add_argument("--schema", default=os.path.join(HERE, "schema", "suite.schema.json"))
    opts = ap.parse_args()

    errors = []
    files = sorted(p for p in glob.glob(os.path.join(opts.catalogue, "*.json")) if not p.endswith("anomaly-patterns.json"))
    if not files:
        print("no suite files found in", opts.catalogue)
        return 1

    validator = None
    try:
        import jsonschema
        schema = json.load(open(opts.schema))
        jsonschema.Draft7Validator.check_schema(schema)
        validator = jsonschema.Draft7Validator(schema)
    except ImportError:
        print("note: jsonschema is not installed; only the built-in structural checks run")

    g_tests, g_params, g_literal, g_prefix = guest_facts(opts.guest)
    if not g_tests:
        errors.append(f"found no test table entries in {opts.guest}/*.c")
    seen, calibration = {}, []
    total = 0
    for path in files:
        name = os.path.basename(path)
        try:
            suite = json.load(open(path))
        except ValueError as e:
            errors.append(f"{name}: not valid JSON: {e}")
            continue
        if validator:
            for e in validator.iter_errors(suite):
                errors.append(f"{name}: {'/'.join(str(p) for p in e.path)}: {e.message[:200]}")
        for t in suite.get("tests", []):
            total += 1
            tid = t.get("id", "?")
            if tid in seen:
                errors.append(f"{name}: duplicate test id {tid} (also in {seen[tid]})")
            seen[tid] = name
            if "calibration" in t.get("tags", []):
                calibration.append(tid)
            if t.get("kind") == "guest":
                g = t.get("guest", {})
                if g.get("test") not in g_tests:
                    errors.append(f"{tid}: guest test '{g.get('test')}' is not in the guest's test tables {sorted(g_tests)}")
                for k in g.get("params", {}):
                    if k not in g_params:
                        errors.append(f"{tid}: parameter '{k}' is never read by the guest (known: {sorted(g_params)})")
            elif t.get("kind") == "host" and t.get("host", {}).get("action") not in ("reboot_cycle",):
                errors.append(f"{tid}: unknown host action {t.get('host', {}).get('action')}")
            for cp in t.get("checkpoints", []):
                n = cp["name"]
                ok = (n in g_literal) or (n.endswith("*") and any(p.startswith(n[:-1]) or n[:-1].startswith(p) for p in g_prefix)) \
                    or any(n.startswith(p) for p in g_prefix)
                if not ok:
                    errors.append(f"{tid}: checkpoint '{n}' is never raised by the guest (literal: {sorted(g_literal)}, formatted prefixes: {sorted(g_prefix)})")
                for e in cp.get("expect", []):
                    r = e.get("rect")
                    if r and not (len(r) == 4 and r[0] >= 0 and r[1] >= 0 and r[2] > 0 and r[3] > 0 and r[0] + r[2] <= 1.0001 and r[1] + r[3] <= 1.0001):
                        errors.append(f"{tid}/{n}/{e.get('name', e['type'])}: rect {r} is outside the frame")
            for c in t.get("checks", []):
                if c["type"] == "audio_window" and c.get("step") not in (1, 2, 3, 4):
                    errors.append(f"{tid}: audio_window step must be 1..4 (the guest's sweep steps)")
            for s in t.get("script", []):
                if s["action"] == "press" and s.get("button", "A").upper() not in BUTTONS:
                    errors.append(f"{tid}: script presses unknown button {s.get('button')}")
            for q in t.get("questionnaire", []):
                if q["type"] == "yesno" and q.get("bad") not in ("yes", "no"):
                    errors.append(f"{tid}: yesno question {q['id']} needs bad: yes|no")
                if q["type"] == "choice" and not q.get("options"):
                    errors.append(f"{tid}: choice question {q['id']} has no options")
    if len(calibration) != 1:
        errors.append(f"exactly one test must carry the 'calibration' tag, found {calibration}")

    if errors:
        print(f"validate_catalogue: {len(errors)} problem(s)")
        for e in errors:
            print(" -", e)
        return 1
    print(f"validate_catalogue: {len(files)} suite file(s), {total} tests OK (guest tests, parameters and checkpoint names all exist in the guest)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
