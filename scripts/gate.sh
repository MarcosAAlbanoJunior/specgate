#!/usr/bin/env bash
# specgate gate: build + tests + lint (+ optional coverage minimum).
#
# Usage:
#   gate.sh               run the gate in the current directory
#   gate.sh --stop-hook   run as a Claude Code Stop hook (reads hook JSON on stdin)
#
# Exit codes: 0 = green, 1 = gate failed, 2 = (hook mode) block Claude from stopping.
# Overrides come from <project>/specgate.config: GATE_CMD, LINT_CMD, COVERAGE_MIN.

set -u

MAX_HOOK_BLOCKS=3
MAX_OUTPUT_LINES=40

HOOK_MODE=0
[ "${1:-}" = "--stop-hook" ] && HOOK_MODE=1

# --- Resolve project directory ------------------------------------------------
if [ "$HOOK_MODE" = 1 ]; then
  INPUT="$(cat)"
  PROJECT_DIR=""
  if command -v jq >/dev/null 2>&1; then
    PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
  fi
  PROJECT_DIR="${PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
else
  PROJECT_DIR="$PWD"
fi
cd "$PROJECT_DIR" || exit 0

# --- Hook mode only acts while a spec is being implemented --------------------
# specs/.active is created by /specgate:spec. specs/.implementing is created by
# /specgate:implement, so the hook stays silent while the spec is awaiting approval.
if [ "$HOOK_MODE" = 1 ]; then
  [ -f specs/.active ] && [ -f specs/.implementing ] || exit 0
fi

# --- Config -------------------------------------------------------------------
GATE_CMD=""
LINT_CMD=""
COVERAGE_MIN=""
# shellcheck disable=SC1091
[ -f specgate.config ] && . ./specgate.config

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# --- Helpers ------------------------------------------------------------------
# Print only the relevant part of a failed step's output.
print_failure() {
  local name="$1"
  echo "GATE FAILED at step: $name"
  if grep -qE '\[ERROR\]|FAIL|FAILED|error:|Error:|panic:|✖|✕|AssertionError' "$TMP"; then
    grep -E '\[ERROR\]|FAIL|FAILED|error:|Error:|panic:|✖|✕|AssertionError|expected|Expected|--- ' "$TMP" \
      | grep -vE 'Re-run Maven|For more information|\[ERROR\] *$|help-1|dump files|To see the full stack|surefire-reports|COMPILATION ERROR :|^\[ERROR\] -> \[Help' \
      | head -n "$MAX_OUTPUT_LINES"
  else
    tail -n "$MAX_OUTPUT_LINES" "$TMP"
  fi
}

# run_step <name> <command string>; returns non-zero on failure after printing the error.
run_step() {
  local name="$1" cmd="$2"
  if ! bash -c "$cmd" >"$TMP" 2>&1; then
    print_failure "$name"
    return 1
  fi
  return 0
}

check_coverage() {
  local actual="" report=""
  case "$STACK" in
    maven|gradle)
      for report in target/site/jacoco/jacoco.csv build/reports/jacoco/test/jacocoTestReport.csv; do
        [ -f "$report" ] && break || report=""
      done
      if [ -z "$report" ]; then
        echo "GATE FAILED at step: coverage"
        echo "COVERAGE_MIN is set but no JaCoCo CSV report was found (configure the jacoco plugin with the csv report)."
        return 1
      fi
      actual="$(awk -F, 'NR>1 {m+=$8; c+=$9} END {if (m+c>0) printf "%.1f", 100*c/(m+c); else print 0}' "$report")"
      ;;
    go)
      if ! go test -coverprofile="$TMP.cover" ./... >"$TMP" 2>&1; then
        print_failure coverage
        return 1
      fi
      actual="$(go tool cover -func="$TMP.cover" | awk '/^total:/ {gsub("%","",$3); print $3}')"
      rm -f "$TMP.cover"
      ;;
    npm)
      if [ ! -f coverage/coverage-summary.json ] || ! command -v jq >/dev/null 2>&1; then
        echo "GATE FAILED at step: coverage"
        echo "COVERAGE_MIN needs coverage/coverage-summary.json (json-summary reporter) and jq."
        return 1
      fi
      actual="$(jq -r '.total.lines.pct' coverage/coverage-summary.json)"
      ;;
    *)
      echo "GATE FAILED at step: coverage"
      echo "COVERAGE_MIN is set but the stack is unknown; set GATE_CMD and check coverage yourself."
      return 1
      ;;
  esac
  if awk -v a="$actual" -v m="$COVERAGE_MIN" 'BEGIN {exit !(a+0 < m+0)}'; then
    echo "GATE FAILED at step: coverage"
    echo "Line coverage ${actual}% is below COVERAGE_MIN=${COVERAGE_MIN}%."
    return 1
  fi
  return 0
}

run_gate() {
  # Stack detection.
  STACK="unknown"
  local build_cmd="" test_cmd="" lint_cmd=""
  if [ -f pom.xml ]; then
    STACK="maven"
    local mvn="mvn"; [ -x ./mvnw ] && mvn="./mvnw"
    test_cmd="$mvn -q -B verify"
  elif [ -f build.gradle ] || [ -f build.gradle.kts ]; then
    STACK="gradle"
    local gr="gradle"; [ -x ./gradlew ] && gr="./gradlew"
    test_cmd="$gr -q --console=plain build"
  elif [ -f package.json ]; then
    STACK="npm"
    local pm="npm"; [ -f pnpm-lock.yaml ] && pm="pnpm"
    grep -q '"build"' package.json && build_cmd="$pm run build"
    grep -q '"test"' package.json && test_cmd="$pm test"
    grep -q '"lint"' package.json && lint_cmd="$pm run lint"
  elif [ -f go.mod ]; then
    STACK="go"
    build_cmd="go build ./..."
    test_cmd="go test ./..."
    lint_cmd="go vet ./..."
  fi

  if [ -n "$GATE_CMD" ]; then
    run_step "GATE_CMD" "$GATE_CMD" || return 1
  elif [ "$STACK" = "unknown" ]; then
    echo "GATE FAILED at step: detect"
    echo "No Maven, Gradle, npm/pnpm or Go project found in $PWD. Set GATE_CMD in specgate.config."
    return 1
  else
    [ -n "$build_cmd" ] && { run_step "build" "$build_cmd" || return 1; }
    [ -n "$test_cmd" ] && { run_step "test" "$test_cmd" || return 1; }
  fi

  lint_cmd="${LINT_CMD:-$lint_cmd}"
  [ -n "$lint_cmd" ] && { run_step "lint" "$lint_cmd" || return 1; }

  [ -n "$COVERAGE_MIN" ] && { check_coverage || return 1; }
  return 0
}

# --- Main ---------------------------------------------------------------------
if [ "$HOOK_MODE" = 0 ]; then
  if run_gate; then
    echo "GATE PASSED"
    exit 0
  fi
  exit 1
fi

# Hook mode: block Stop on failure, but give up after MAX_HOOK_BLOCKS so a
# stuck run is handed to the human instead of looping.
COUNTER=specs/.gate-fails
OUT="$(run_gate 2>&1)"
if [ $? -eq 0 ]; then
  rm -f "$COUNTER"
  exit 0
fi

FAILS=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$FAILS" >"$COUNTER"
if [ "$FAILS" -gt "$MAX_HOOK_BLOCKS" ]; then
  # Allow the stop; the human decides. Counter stays so the next stop is also allowed.
  printf '{"systemMessage":"specgate: gate still failing after %s blocked stops; handing back to the human."}\n' "$MAX_HOOK_BLOCKS"
  exit 0
fi
{
  echo "specgate Stop hook: gate is red (block $FAILS/$MAX_HOOK_BLOCKS). Fix this before finishing:"
  echo "$OUT"
} >&2
exit 2
