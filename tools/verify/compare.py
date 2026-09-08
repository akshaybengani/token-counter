#!/usr/bin/env python3
"""Compares the reference output against the providers' output, field by field.

Turns the harness from two blocks a human eyeballs into a verdict. Writes a
machine-readable result so a tagged test can assert it, which keeps AC emission in
one place (the Swift emitter) rather than adding a second one here.

Claude Code is allowed to have grown between the two runs, because the session
running this spends tokens while it runs. Every other provider must match exactly.
"""
import json
import re
import sys

FIELDS = ["input", "output", "cacheWrite", "cacheRead", "calls"]
# Only Claude Code can accrue usage between the reference run and the provider run.
GROWING = {"CLAUDE"}
# A wider gap than this means something other than live drift.
DRIFT_TOLERANCE = 0.02


def parse(text):
    out = {}
    for line in text.splitlines():
        match = re.match(r"^([A-Z]+)\s+(.*)$", line.strip())
        if not match:
            continue
        name, rest = match.group(1), match.group(2)
        if "=" not in rest:
            continue
        fields = dict(re.findall(r"(\w+)=(-?\d+)", rest))
        if not fields:
            continue
        out[name] = {k: int(v) for k, v in fields.items()}
    return out


def compare(reference, providers):
    findings = []
    shared = sorted(set(reference) & set(providers))
    if not shared:
        return [{"provider": "-", "field": "-", "ok": False,
                 "detail": "no providers appeared in both outputs, so nothing was compared"}]

    for name in shared:
        for field in FIELDS:
            if field not in reference[name] or field not in providers[name]:
                continue
            expected, actual = reference[name][field], providers[name][field]
            if actual == expected:
                findings.append({"provider": name, "field": field, "ok": True,
                                 "detail": f"{actual}"})
                continue
            if name in GROWING and actual >= expected:
                slack = max(1, int(abs(expected) * DRIFT_TOLERANCE))
                ok = (actual - expected) <= slack
                findings.append({"provider": name, "field": field, "ok": ok,
                                 "detail": f"{expected} -> {actual}, drift {actual - expected}"
                                           f" (allowed {slack})"})
                continue
            findings.append({"provider": name, "field": field, "ok": False,
                             "detail": f"expected {expected}, got {actual}"})
    return findings


def main():
    reference = parse(open(sys.argv[1]).read())
    providers = parse(open(sys.argv[2]).read())
    out_path = sys.argv[3]
    cutoff = sys.argv[4] if len(sys.argv) > 4 else "unknown"

    findings = compare(reference, providers)
    failures = [f for f in findings if not f["ok"]]
    ok = not failures

    result = {
        "ok": ok,
        "cutoff": cutoff,
        "providers_compared": sorted(set(reference) & set(providers)),
        "comparisons": len(findings),
        "failures": failures,
    }
    with open(out_path, "w") as handle:
        json.dump(result, handle, indent=2)

    print(f"    compared {len(findings)} figures across {len(result['providers_compared'])} providers: "
          f"{', '.join(result['providers_compared'])}")
    if ok:
        print("    every figure agrees (Claude Code within live-drift tolerance)")
    else:
        print(f"    {len(failures)} MISMATCHED:")
        for f in failures:
            print(f"      {f['provider']}.{f['field']}: {f['detail']}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
