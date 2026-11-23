#!/usr/bin/env bash
# Runs every test suite that exists; skips (with a printed reason) the ones whose tool/files are missing.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
ROOT=$PWD
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17 2>/dev/null)}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
UV="${UV:-$HOME/.local/bin/uv}"; [ -x "$UV" ] || UV=$(command -v uv || true)  # absolute path: rtk rewrites `uv` output
# GRADLE_USER_HOME is inherited if the caller set it (~/.gradle is read-only in agent sandboxes); never set here.
mkdir -p build/reports
NAMES=(); RESULTS=()

# run <suite> <report-file|-> <dir> <cmd...>; runs all suites even if one fails
run() {
  local name=$1 rep=$2 dir=$3; shift 3
  echo "=== $name ==="
  if [ "$rep" = - ]; then (cd "$dir" && "$@"); rc=$?
  else (cd "$dir" && "$@") 2>&1 | tee "$ROOT/$rep"; rc=${PIPESTATUS[0]}; fi
  NAMES+=("$name"); if [ $rc -eq 0 ]; then RESULTS+=(PASS); else RESULTS+=("FAIL($rc)"); fi
}
skip() { echo "SKIP $1: $2"; NAMES+=("$1"); RESULTS+=("SKIP"); }

# Kotlin (JUnit XML: build/app/test-results/testDebugUnitTest/ at repo root)
if [ ! -x android/gradlew ]; then skip kotlin "android/gradlew missing"
elif [ -z "$JAVA_HOME" ]; then skip kotlin "JDK 17 not found"
else
  # ~/.gradle is read-only in agent sandboxes: fall back to a fresh home under gitignored build/ (slow first run)
  if [ -z "${GRADLE_USER_HOME:-}" ]; then
    GH="$HOME/.gradle"; [ -d "$GH" ] || GH="$HOME"
    if [ -w "$GH" ]; then echo "gradle home: ~/.gradle (default)"
    else export GRADLE_USER_HOME="$ROOT/build/gradle-home"; mkdir -p "$GRADLE_USER_HOME"; fi
  fi
  [ -n "${GRADLE_USER_HOME:-}" ] && echo "gradle home: $GRADLE_USER_HOME"
  run kotlin build/reports/kotlin.txt android ./gradlew -PskipDependencyChecks=true :app:testDebugUnitTest
  if [ "${RESULTS[${#RESULTS[@]}-1]}" != PASS ]; then echo "--- kotlin failed, last 30 lines ---"; tail -n 30 build/reports/kotlin.txt; fi
  echo "note: android/app/build/rules_preds.jsonl now holds the smoke-CSV output; regenerate the ML heldout export with RULES_EVAL_CSV."
fi

# Flutter (JSON events -> build/reports/flutter_test.jsonl)
if ! command -v flutter >/dev/null; then skip flutter "flutter not installed"
elif [ ! -f pubspec.yaml ] || ! ls test/*_test.dart >/dev/null 2>&1; then skip flutter "no pubspec.yaml or test/*_test.dart"
else run flutter build/reports/flutter_test.jsonl . flutter test --reporter json; fi

# Python
if [ -z "$UV" ]; then skip pytest "uv not found"
elif [ ! -f ml/pyproject.toml ]; then skip pytest "ml/pyproject.toml missing"
else run pytest build/reports/pytest.txt ml "$UV" run pytest -q -rA; fi

# Node (file glob, not a directory: newer Node rejects directories)
if ! command -v node >/dev/null; then skip node "node not installed"
elif ! ls dashboard/test/*.test.mjs >/dev/null 2>&1; then skip node "no dashboard/test/*.test.mjs"
else run node build/reports/node.tap . node --test --test-reporter=tap dashboard/test/*.test.mjs; fi

echo; echo "=== summary ==="
FAILED=0
for i in "${!NAMES[@]}"; do
  printf '%-10s %s\n' "${NAMES[$i]}" "${RESULTS[$i]}"
  case ${RESULTS[$i]} in FAIL*) FAILED=1;; esac
done
exit $FAILED
