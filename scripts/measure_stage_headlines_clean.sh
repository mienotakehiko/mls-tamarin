#!/usr/bin/env bash
# Measure headline lemmas for all nine staged theories with a pinned clean Tamarin.
# This script records observations even if they disagree with the shipped expectation.

set -euo pipefail

REPO_ROOT="${1:-$PWD}"
TAMARIN="${TAMARIN:-$HOME/tamarin-clean-1.12.0/bin/tamarin-prover-1.12.0-clean}"
OUT="$REPO_ROOT/results/stage_headline_measurement"
BUDGET="${BUDGET:-3600}"

cd "$REPO_ROOT"
mkdir -p "$OUT"

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -x "$TAMARIN" ]] || die "Tamarin not executable: $TAMARIN"

"$TAMARIN" -V > "$OUT/tamarin_version.txt" 2>&1
grep -Eq '1\.12\.0' "$OUT/tamarin_version.txt" || die "Tamarin 1.12.0 not reported"
grep -Eq '82780bb' "$OUT/tamarin_version.txt" || die "release revision 82780bb not reported"
if grep -Eiq 'with[[:space:]]+uncommitt?ed[[:space:]]+changes' "$OUT/tamarin_version.txt"; then
  die "dirty Tamarin build marker detected"
fi

EXPECTED_BIN=$(awk '{print $1}' metadata/tamarin_binary_sha256.txt)
ACTUAL_BIN=$(sha256sum "$(readlink -f "$TAMARIN")" | awk '{print $1}')
[[ "$ACTUAL_BIN" == "$EXPECTED_BIN" ]] || die "Tamarin binary SHA mismatch"

EXPECTED_MODEL=$(awk '{print $1}' metadata/model_sha256.txt)
ACTUAL_MODEL=$(sha256sum theories/mls_ratchet_tree_semantic_final.spthy | awk '{print $1}')
[[ "$ACTUAL_MODEL" == "$EXPECTED_MODEL" ]] || die "final model SHA mismatch"

{
  echo "tamarin=$(readlink -f "$TAMARIN")"
  echo "tamarin_sha256=$ACTUAL_BIN"
  echo "final_model_sha256=$ACTUAL_MODEL"
  echo "run_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  cat "$OUT/tamarin_version.txt"
} > "$OUT/reproducibility_metadata.txt"

# stage|theory|headline lemma|shipped expected
stages=(
  "stage1|theories/stages/stage1_private_kdf.spthy|L1_baseline_secrecy|verified"
  "stage1c|theories/stages/stage1c_public_kdf_control.spthy|L1_baseline_secrecy|falsified"
  "stage2|theories/stages/stage2_private_fs.spthy|L2_forward_secrecy|verified"
  "stage3|theories/stages/stage3_private_pcs.spthy|L3_post_compromise_security|verified"
  "stage4_p1|theories/stages/stage4_p1_public_unauth_kp.spthy|L1_baseline_secrecy|falsified"
  "stage4_p2|theories/stages/stage4_p2_public_valid_kp.spthy|L1_baseline_secrecy|verified"
  "stage5|theories/stages/stage5_public_fs.spthy|L2_forward_secrecy|verified"
  "stage6_v1|theories/stages/stage6_v1_simplified_pcs.spthy|L3_post_compromise_security|falsified"
  "stage7_v2|theories/stages/stage7_v2_copath_pcs.spthy|L3_post_compromise_security|verified"
)

echo "stage,theory,lemma,expected,observed,status,steps,wall_seconds,max_rss_kb,exit_code,sources_step,warnings,theory_sha256" \
  > "$OUT/stage_headline_results.csv"

printf "%-10s %-30s %-10s %-10s %-10s %-8s %-9s %-10s %s\n" \
  "stage" "lemma" "expected" "observed" "status" "steps" "wall(s)" "RSS(MiB)" "warnings"

FAILS=0

for entry in "${stages[@]}"; do
  IFS='|' read -r NAME THEORY LEMMA EXPECTED <<<"$entry"
  [[ -f "$THEORY" ]] || { echo "missing $THEORY" >&2; FAILS=$((FAILS+1)); continue; }

  THEORY_SHA=$(sha256sum "$THEORY" | awk '{print $1}')
  LOG="$OUT/${NAME}.log"
  TIME="$OUT/${NAME}.time.txt"

  set +e
  /usr/bin/time -v -o "$TIME" \
    timeout --kill-after=30s "${BUDGET}s" \
    "$TAMARIN" --prove="$LEMMA" "$THEORY" > "$LOG" 2>&1
  RC=$?
  set -e

  LINE=$(grep -E "^[[:space:]]*${LEMMA} .*:" "$LOG" | tail -1 || true)

  OBS=unknown
  grep -q 'verified' <<<"$LINE" && OBS=verified
  grep -q 'falsified' <<<"$LINE" && OBS=falsified

  STEPS=$(grep -oE '\([0-9]+ steps\)' <<<"$LINE" | grep -oE '[0-9]+' | tail -1 || true)
  [[ -n "$STEPS" ]] || STEPS=NA

  WALL=$(awk -F': ' '/Elapsed \(wall clock\)/ {print $2}' "$TIME" | tail -1)
  WALL_SEC=$(awk -v t="$WALL" 'BEGIN{
    n=split(t,a,":");
    if(n==3) printf "%.2f",a[1]*3600+a[2]*60+a[3];
    else if(n==2) printf "%.2f",a[1]*60+a[2];
    else printf "%.2f",a[1];
  }')
  RSS=$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TIME" | tail -1)
  RSS_MIB=$(awk -v r="$RSS" 'BEGIN{printf "%.1f", r/1024}')

  SOURCES=$(grep -oE 'Saturating Sources] Step [0-9]+' "$LOG" \
      | grep -oE '[0-9]+' | tail -1 || true)
  if [[ -z "$SOURCES" ]]; then
    SOURCES=$(grep -oE 'source[s]? saturated after [0-9]+' "$LOG" \
      | grep -oE '[0-9]+' | tail -1 || true)
  fi
  [[ -n "$SOURCES" ]] || SOURCES=NA

  WARN=clean
  if grep -qE 'WARNING:|wellformedness checks failed|Fact arity|Fact multiplicity|Subterm Convergence Warning|Message Derivation Checks|Failed to derive' "$LOG"; then
    WARN=present
  fi

  STATUS=OK
  if [[ "$OBS" != "$EXPECTED" || "$RC" -ne 0 || "$WARN" != clean ]]; then
    STATUS=MISMATCH
    FAILS=$((FAILS+1))
  fi

  echo "$NAME,$THEORY,$LEMMA,$EXPECTED,$OBS,$STATUS,$STEPS,$WALL_SEC,$RSS,$RC,$SOURCES,$WARN,$THEORY_SHA" \
    >> "$OUT/stage_headline_results.csv"

  printf "%-10s %-30s %-10s %-10s %-10s %-8s %-9s %-10s %s\n" \
    "$NAME" "$LEMMA" "$EXPECTED" "$OBS" "$STATUS" "$STEPS" "$WALL_SEC" "$RSS_MIB" "$WARN"
done

echo
echo "Results: $OUT/stage_headline_results.csv"
echo "Mismatches/nonclean runs: $FAILS"
echo
echo "NOTE: A mismatch is evidence to inspect the staged derivation/expectation;"
echo "this script intentionally does not rewrite any model."

# Always return 0 so all collected data remains easy to inspect.
exit 0
