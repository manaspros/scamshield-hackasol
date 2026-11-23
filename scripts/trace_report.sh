#!/usr/bin/env bash
# Maps BUILD_PLAN.md task IDs to pass/fail/blocked/not-run from the reports check.sh leaves behind.
# Exit 1 only if some task is `fail`. Test names must start with the task ID: T1_2_..., Dart T3_2_..., Python T1_8_...
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
exec /usr/bin/python3 -I - "$PWD" <<'PY'
import re, sys, glob, json, pathlib
import xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
ID = re.compile(r'(?<![A-Za-z0-9])T(\d+)_(\d+)_')
def tid(name):
    m = ID.search(name or "")
    return f"T{m[1]}.{m[2]}" if m else None
res = {}  # task -> [passed, failed]
def add(name, ok):
    t = tid(name)
    if t: res.setdefault(t, [0, 0])[0 if ok else 1] += 1
def lines(p):
    try: return pathlib.Path(p).read_text(errors="replace").splitlines()
    except OSError: return []

# Kotlin JUnit XML
# repo-root build/app first, android/app/build as fallback
xmls = glob.glob(str(root / "build/app/test-results/**/*.xml"), recursive=True) or \
       glob.glob(str(root / "android/app/build/test-results/**/*.xml"), recursive=True)
for f in xmls:
    try: tree = ET.parse(f)
    except ET.ParseError: continue
    for tc in tree.iter("testcase"):
        if tc.find("skipped") is not None: continue
        add(tc.get("name"), tc.find("failure") is None and tc.find("error") is None)
# Flutter --reporter json (one event per line); hidden = setUp/tearDown pseudo-tests
names = {}
for l in lines(root / "build/reports/flutter_test.jsonl"):
    try: e = json.loads(l)
    except ValueError: continue
    if e.get("type") == "testStart": names[e["test"]["id"]] = e["test"]["name"]
    elif e.get("type") == "testDone" and not e.get("hidden") and not e.get("skipped"):
        add(names.get(e["testID"]), e.get("result") == "success")
# pytest -rA short summary
for l in lines(root / "build/reports/pytest.txt"):
    m = re.match(r"(PASSED|FAILED|ERROR) (\S+)", l)
    if m: add(m[2], m[1] == "PASSED")
# node TAP
for l in lines(root / "build/reports/node.tap"):
    m = re.match(r"\s*(not ok|ok) \d+ - (.*)", l)
    if m and "# SKIP" not in m[2]: add(m[2], m[1] == "ok")

rows = []
for l in lines(root / "BUILD_PLAN.md"):
    m = re.match(r"- \[[ xX]\] (T\d+\.\d+)\b", l)
    if m: rows.append((m[1], "[BLOCKED" in l))
ids = {r[0] for r in rows}
rows += [(t, False) for t in sorted(res) if t not in ids]  # tests naming an ID the plan lacks
print(f"{'ID':<7}{'STATUS':<9}{'PASS':>5}{'FAIL':>5}")
bad = 0
for t, blocked in rows:
    p, f = res.get(t, [0, 0])
    s = "fail" if f else "pass" if p else "blocked" if blocked else "not-run"
    bad |= s == "fail"
    print(f"{t:<7}{s:<9}{p:>5}{f:>5}")
sys.exit(bad)
PY
