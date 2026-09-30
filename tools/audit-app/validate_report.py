#!/usr/bin/env python3
"""validate_report.py REPORT.json [...] - validates reports against schema/report.schema.json (needs `pip install jsonschema`)."""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main(paths):
    import jsonschema
    schema = json.load(open(os.path.join(HERE, "schema", "report.schema.json")))
    jsonschema.Draft7Validator.check_schema(schema)
    v = jsonschema.Draft7Validator(schema)
    bad = 0
    for p in paths:
        errs = list(v.iter_errors(json.load(open(p))))
        for e in errs[:20]:
            print(f"{p}: {'/'.join(str(x) for x in e.path)}: {e.message[:200]}")
        bad += len(errs)
        if not errs:
            print(f"{p}: valid")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]) if len(sys.argv) > 1 else 2)
