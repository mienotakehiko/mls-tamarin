#!/usr/bin/env bash
# ============================================================
# Re-measure corrected-v2 stage3 with a MONOTONIC wall clock.
#
# Purpose:
#   The nine-stage replay produced an impossible negative wall time for
#   stage3 because the system wall clock moved backwards under WSL.
#   This script keeps /usr/bin/time -v for peak RSS, but measures elapsed
#   time independently with Python time.monotonic_ns().
#
# Runs stage3 L3 x 10 by default.
# ============================================================

set -euo pipefail

REPO_ROOT="${1:-$PWD}"
TAMARIN="${TAMARIN:-$HOME/tamarin-clean-1.12.0/bin/tamarin-prover-1.12.0-clean}"
REPS="${REPS:-10}"
BUDGET="${BUDGET:-3600}"
OUT="$REPO_ROOT/results/stage3_monotonic_repeat${REPS}"

cd "$REPO_ROOT"

die() { echo "ERROR: $*" >&2; exit 1; }

THEORY="theories/stages/stage3_private_pcs.spthy"
LEMMA="L3_post_compromise_security"

[[ -f metadata/stage_artifact_revision.txt ]] || die "artifact marker missing"
grep -q '^artifact_revision=corrected-v2-historical-stages$' \
  metadata/stage_artifact_revision.txt || die "wrong artifact revision"

[[ -f "$THEORY" ]] || die "missing theory: $THEORY"
[[ -x "$TAMARIN" ]] || die "Tamarin not executable: $TAMARIN"

# Pinned stage hash from corrected-v2 manifest.
EXPECTED_STAGE_SHA="$(
  awk '$2=="theories/stages/stage3_private_pcs.spthy"{print $1}' \
  metadata/stage_theory_sha256.txt
)"
ACTUAL_STAGE_SHA="$(sha256sum "$THEORY" | awk '{print $1}')"
[[ -n "$EXPECTED_STAGE_SHA" && "$ACTUAL_STAGE_SHA" == "$EXPECTED_STAGE_SHA" ]] || \
  die "stage3 SHA mismatch"

EXPECTED_BIN="$(awk '{print $1}' metadata/tamarin_binary_sha256.txt)"
RESOLVED_BIN="$(readlink -f "$TAMARIN")"
ACTUAL_BIN="$(sha256sum "$RESOLVED_BIN" | awk '{print $1}')"
[[ "$ACTUAL_BIN" == "$EXPECTED_BIN" ]] || die "Tamarin SHA mismatch"

rm -rf "$OUT"
mkdir -p "$OUT"

"$RESOLVED_BIN" -V > "$OUT/tamarin_version.txt" 2>&1
grep -Eq '1\.12\.0' "$OUT/tamarin_version.txt" || die "Tamarin 1.12.0 not reported"
grep -Eq '82780bb' "$OUT/tamarin_version.txt" || die "release revision 82780bb not reported"
if grep -Eiq 'with[[:space:]]+uncommitt?ed[[:space:]]+changes' \
  "$OUT/tamarin_version.txt"; then
  die "dirty Tamarin build marker detected"
fi

echo "============================================================"
echo "Stage3 monotonic re-measurement"
echo "============================================================"
echo "REPO_ROOT=$REPO_ROOT"
echo "TAMARIN=$RESOLVED_BIN"
echo "THEORY=$THEORY"
echo "THEORY_SHA256=$ACTUAL_STAGE_SHA"
echo "LEMMA=$LEMMA"
echo "REPS=$REPS"
echo

CSV="$OUT/stage3_repeat${REPS}.csv"
echo "rep,monotonic_wall_seconds,max_rss_kb,exit_code,verdict,steps,sources_step,wellformedness,warnings,tamarin_processing_time_raw" > "$CSV"

for i in $(seq 1 "$REPS"); do
  LOG="$OUT/stage3_run_${i}.log"
  TIME="$OUT/stage3_run_${i}.time.txt"
  MONO="$OUT/stage3_run_${i}.monotonic.txt"

  echo "[stage3] run $i/$REPS"

  # Python supplies the authoritative monotonic elapsed time.
  set +e
  python3 - "$RESOLVED_BIN" "$LEMMA" "$THEORY" "$BUDGET" "$LOG" "$TIME" "$MONO" <<'PY'
import subprocess
import sys
import time

tamarin, lemma, theory, budget, log_path, time_path, mono_path = sys.argv[1:]

cmd = [
    "/usr/bin/time", "-v", "-o", time_path,
    "timeout", "--kill-after=30s", f"{budget}s",
    tamarin, f"--prove={lemma}", theory
]

start = time.monotonic_ns()
with open(log_path, "wb") as log:
    cp = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
end = time.monotonic_ns()

elapsed = (end - start) / 1_000_000_000
with open(mono_path, "w", encoding="utf-8") as f:
    f.write(f"{elapsed:.9f}\n")

sys.exit(cp.returncode)
PY
  RC=$?
  set -e

  MONO_WALL="$(cat "$MONO")"

  LINE="$(grep -E "^[[:space:]]*${LEMMA} .*:" "$LOG" | tail -1 || true)"
  VERDICT="unknown"
  if grep -q 'verified' <<<"$LINE"; then
    VERDICT="verified"
  elif grep -q 'falsified' <<<"$LINE"; then
    VERDICT="falsified"
  fi

  STEPS="$(
    grep -oE '\([0-9]+ steps\)' <<<"$LINE" |
    grep -oE '[0-9]+' | tail -1 || true
  )"
  [[ -n "$STEPS" ]] || STEPS="NA"

  RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TIME" | tail -1)"
  [[ -n "$RSS" ]] || RSS="NA"

  SOURCES="$(
    grep -oE 'Saturating Sources] Step [0-9]+' "$LOG" |
    grep -oE '[0-9]+' | tail -1 || true
  )"
  [[ -n "$SOURCES" ]] || SOURCES="NA"

  WF="failed"
  if grep -q 'All wellformedness checks were successful' "$LOG"; then
    WF="successful"
  fi

  WARN="clean"
  if grep -qE \
    'WARNING:|wellformedness checks failed|Fact arity|Fact multiplicity|Subterm Convergence Warning|Message Derivation Checks|Failed to derive' \
    "$LOG"; then
    WARN="present"
  fi

  PROC_RAW="$(
    grep -E 'processing time:' "$LOG" | tail -1 |
    sed -E 's/.*processing time:[[:space:]]*//' || true
  )"
  [[ -n "$PROC_RAW" ]] || PROC_RAW="NA"

  echo "$i,$MONO_WALL,$RSS,$RC,$VERDICT,$STEPS,$SOURCES,$WF,$WARN,$PROC_RAW" >> "$CSV"
done

python3 - "$CSV" > "$OUT/stage3_repeat${REPS}_summary.txt" <<'PY'
import csv
import statistics as st
import sys
from math import sqrt

path = sys.argv[1]
with open(path, newline="") as f:
    rows = list(csv.DictReader(f))

wall = [float(r["monotonic_wall_seconds"]) for r in rows]
rss = [float(r["max_rss_kb"]) for r in rows if r["max_rss_kb"] != "NA"]

print(f"Runs: {len(rows)}")
print(f"Verified: {sum(r['verdict']=='verified' for r in rows)}/{len(rows)}")
print("Steps observed:", ",".join(sorted(set(r["steps"] for r in rows))))
print("Sources steps observed:", ",".join(sorted(set(r["sources_step"] for r in rows))))
print("Wellformedness observed:", ",".join(sorted(set(r["wellformedness"] for r in rows))))
print("Warnings observed:", ",".join(sorted(set(r["warnings"] for r in rows))))
print("Exit codes observed:", ",".join(sorted(set(r["exit_code"] for r in rows))))

print(f"Monotonic wall mean: {st.mean(wall):.6f}")
print(f"Monotonic wall median: {st.median(wall):.6f}")
print(f"Monotonic wall stdev: {st.stdev(wall):.6f}" if len(wall) > 1 else "Monotonic wall stdev: NA")
print(f"Monotonic wall min: {min(wall):.6f}")
print(f"Monotonic wall max: {max(wall):.6f}")

if rss:
    print(f"RSS mean KB: {st.mean(rss):.1f}")
    print(f"RSS mean MiB: {st.mean(rss)/1024:.3f}")
    print(f"RSS stdev KB: {st.stdev(rss):.3f}" if len(rss) > 1 else "RSS stdev KB: NA")

ok = all(
    r["exit_code"] == "0"
    and r["verdict"] == "verified"
    and r["steps"] == "18"
    and r["wellformedness"] == "successful"
    and r["warnings"] == "clean"
    for r in rows
)
print(f"All expected and clean: {ok}")

# Keep Tamarin's own raw processing-time strings for audit. They may still
# become negative if the host wall clock is adjusted; monotonic time is the
# authoritative performance metric for this re-measurement.
print("Raw Tamarin processing times:", ",".join(r["tamarin_processing_time_raw"] for r in rows))
PY

cat "$OUT/stage3_repeat${REPS}_summary.txt"

if ! grep -q '^All expected and clean: True$' "$OUT/stage3_repeat${REPS}_summary.txt"; then
  die "one or more stage3 repetitions were not clean/expected"
fi

echo
echo "Results:"
echo "  $CSV"
echo "  $OUT/stage3_repeat${REPS}_summary.txt"
