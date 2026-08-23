#!/usr/bin/env bash
# ============================================================
# Corrected-v2: measure headline lemma for all nine stages.
#
# Safety checks before measurement:
#   - corrected-v2 artifact marker
#   - all nine staged-theory SHA-256 values
#   - final-model SHA-256
#   - pinned clean Tamarin 1.12.0 binary SHA-256
#   - Tamarin release revision 82780bb...
#   - no dirty-working-tree marker
#   - semantic-shape guards for stage1c and stage4_p1
#
# Measurements:
#   stage1      L1_baseline_secrecy
#   stage1c     L1_baseline_secrecy
#   stage2      L2_forward_secrecy
#   stage3      L3_post_compromise_security
#   stage4_p1   L1_baseline_secrecy
#   stage4_p2   L1_baseline_secrecy
#   stage5      L2_forward_secrecy
#   stage6_v1   L3_post_compromise_security
#   stage7_v2   L3_post_compromise_security
# ============================================================

set -euo pipefail

REPO_ROOT="${1:-$PWD}"
TAMARIN="${TAMARIN:-$HOME/tamarin-clean-1.12.0/bin/tamarin-prover-1.12.0-clean}"
OUT="$REPO_ROOT/results/stage_headline_measurement_v2"
BUDGET="${BUDGET:-3600}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

cd "$REPO_ROOT"

echo "============================================================"
echo "Corrected-v2 nine-stage headline measurement"
echo "============================================================"
echo "REPO_ROOT=$(pwd)"
echo "TAMARIN=$TAMARIN"
echo "OUT=$OUT"
echo

# ------------------------------------------------------------
# Artifact identity
# ------------------------------------------------------------

[[ -f metadata/stage_artifact_revision.txt ]] || \
    die "corrected-v2 artifact marker missing"

grep -q '^artifact_revision=corrected-v2-historical-stages$' \
    metadata/stage_artifact_revision.txt || \
    die "wrong artifact revision / wrong repository"

echo "===== artifact marker ====="
cat metadata/stage_artifact_revision.txt
echo

# ------------------------------------------------------------
# Theory integrity
# ------------------------------------------------------------

[[ -f metadata/stage_theory_sha256.txt ]] || \
    die "stage hash manifest missing"

echo "===== staged theory SHA-256 check ====="
sha256sum -c metadata/stage_theory_sha256.txt
echo

# Semantic guards for the two previously mis-reconstructed stages.
S1C="theories/stages/stage1c_public_kdf_control.spthy"
P1="theories/stages/stage4_p1_public_unauth_kp.spthy"

grep -q 'functions: node_sk/1, node_pk/1' "$S1C" || \
    die "stage1c is not the historical public-control shape"
grep -q 'pk_w_old = node_pk(ps_w_old)' "$S1C" || \
    die "stage1c does not retain the historical old-node Update"
if grep -q 'ResolutionKey' "$S1C"; then
    die "stage1c unexpectedly contains copath-resolution keys"
fi

grep -q 'functions: node_sk/1' "$P1" || \
    die "stage4_p1 does not use public node_sk/1"
grep -q 'pk_w_old = pk(node_sk(ps_w_old))' "$P1" || \
    die "stage4_p1 does not retain the historical old-node Update"
if grep -q 'ResolutionKey' "$P1"; then
    die "stage4_p1 unexpectedly contains copath-resolution keys"
fi

echo "Semantic-shape guards: PASS"
echo

# ------------------------------------------------------------
# Clean Tamarin / final-model integrity
# ------------------------------------------------------------

[[ -x "$TAMARIN" ]] || die "Tamarin not executable: $TAMARIN"

EXPECTED_BIN="$(awk '{print $1}' metadata/tamarin_binary_sha256.txt)"
RESOLVED_BIN="$(readlink -f "$TAMARIN")"
ACTUAL_BIN="$(sha256sum "$RESOLVED_BIN" | awk '{print $1}')"

[[ "$ACTUAL_BIN" == "$EXPECTED_BIN" ]] || \
    die "Tamarin binary SHA mismatch: actual=$ACTUAL_BIN expected=$EXPECTED_BIN"

EXPECTED_MODEL="$(awk '{print $1}' metadata/model_sha256.txt)"
FINAL_MODEL="theories/mls_ratchet_tree_semantic_final.spthy"
ACTUAL_MODEL="$(sha256sum "$FINAL_MODEL" | awk '{print $1}')"

[[ "$ACTUAL_MODEL" == "$EXPECTED_MODEL" ]] || \
    die "final model SHA mismatch: actual=$ACTUAL_MODEL expected=$EXPECTED_MODEL"

# Fresh output directory so stale results cannot be mistaken for this run.
rm -rf "$OUT"
mkdir -p "$OUT"

"$RESOLVED_BIN" -V > "$OUT/tamarin_version_preflight.txt" 2>&1

grep -Eq '1\.12\.0' "$OUT/tamarin_version_preflight.txt" || \
    die "Tamarin 1.12.0 not reported"
grep -Eq '82780bb' "$OUT/tamarin_version_preflight.txt" || \
    die "release revision 82780bb not reported"

if grep -Eiq 'with[[:space:]]+uncommitt?ed[[:space:]]+changes' \
    "$OUT/tamarin_version_preflight.txt"; then
    die "dirty Tamarin build marker detected"
fi

echo "===== clean Tamarin ====="
cat "$OUT/tamarin_version_preflight.txt"
echo
echo "Tamarin SHA-256: $ACTUAL_BIN"
echo "Final model SHA-256: $ACTUAL_MODEL"
echo

{
    echo "artifact_revision=corrected-v2-historical-stages"
    echo "run_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "repo_root=$(pwd)"
    echo "tamarin=$RESOLVED_BIN"
    echo "tamarin_sha256=$ACTUAL_BIN"
    echo "final_model_sha256=$ACTUAL_MODEL"
    echo "budget_seconds=$BUDGET"
    echo
    echo "--- Tamarin version ---"
    cat "$OUT/tamarin_version_preflight.txt"
    echo
    echo "--- stage hashes ---"
    cat metadata/stage_theory_sha256.txt
} > "$OUT/reproducibility_metadata.txt"

# ------------------------------------------------------------
# stage|theory|headline lemma|expected
# ------------------------------------------------------------

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

CSV="$OUT/stage_headline_results.csv"

echo "stage,theory,lemma,expected,observed,status,steps,wall_seconds,max_rss_kb,exit_code,sources_step,wellformedness,warnings,theory_sha256" \
    > "$CSV"

printf "%-10s %-30s %-10s %-10s %-10s %-8s %-9s %-10s %-8s %s\n" \
    "stage" "lemma" "expected" "observed" "status" "steps" "wall(s)" "RSS(MiB)" "WF" "warnings"

FAILS=0

for entry in "${stages[@]}"; do
    IFS='|' read -r NAME THEORY LEMMA EXPECTED <<<"$entry"

    [[ -f "$THEORY" ]] || {
        echo "ERROR: missing theory $THEORY" >&2
        FAILS=$((FAILS+1))
        continue
    }

    THEORY_SHA="$(sha256sum "$THEORY" | awk '{print $1}')"
    LOG="$OUT/${NAME}.log"
    TIME="$OUT/${NAME}.time.txt"

    set +e
    /usr/bin/time -v -o "$TIME" \
        timeout --kill-after=30s "${BUDGET}s" \
        "$RESOLVED_BIN" --prove="$LEMMA" "$THEORY" \
        > "$LOG" 2>&1
    RC=$?
    set -e

    LINE="$(grep -E "^[[:space:]]*${LEMMA} .*:" "$LOG" | tail -1 || true)"

    OBS="unknown"
    if grep -q 'verified' <<<"$LINE"; then
        OBS="verified"
    elif grep -q 'falsified' <<<"$LINE"; then
        OBS="falsified"
    fi

    STEPS="$(
        grep -oE '\([0-9]+ steps\)' <<<"$LINE" \
        | grep -oE '[0-9]+' \
        | tail -1 || true
    )"
    [[ -n "$STEPS" ]] || STEPS="NA"

    WALL_RAW="$(awk -F': ' '/Elapsed \(wall clock\)/ {print $2}' "$TIME" | tail -1)"
    WALL_SEC="$(
        awk -v t="$WALL_RAW" 'BEGIN {
          n=split(t,a,":");
          if(n==3) printf "%.2f",a[1]*3600+a[2]*60+a[3];
          else if(n==2) printf "%.2f",a[1]*60+a[2];
          else printf "%.2f",a[1];
        }'
    )"

    RSS="$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TIME" | tail -1)"
    [[ -n "$RSS" ]] || RSS="0"
    RSS_MIB="$(awk -v r="$RSS" 'BEGIN{printf "%.1f",r/1024}')"

    SOURCES="$(
        grep -oE 'Saturating Sources] Step [0-9]+' "$LOG" \
        | grep -oE '[0-9]+' \
        | tail -1 || true
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

    STATUS="OK"
    if [[ "$OBS" != "$EXPECTED" || "$RC" -ne 0 || "$WF" != "successful" || "$WARN" != "clean" ]]; then
        STATUS="MISMATCH"
        FAILS=$((FAILS+1))
    fi

    echo "$NAME,$THEORY,$LEMMA,$EXPECTED,$OBS,$STATUS,$STEPS,$WALL_SEC,$RSS,$RC,$SOURCES,$WF,$WARN,$THEORY_SHA" \
        >> "$CSV"

    printf "%-10s %-30s %-10s %-10s %-10s %-8s %-9s %-10s %-8s %s\n" \
        "$NAME" "$LEMMA" "$EXPECTED" "$OBS" "$STATUS" "$STEPS" "$WALL_SEC" "$RSS_MIB" "$WF" "$WARN"
done

# ------------------------------------------------------------
# Postflight integrity
# ------------------------------------------------------------

"$RESOLVED_BIN" -V > "$OUT/tamarin_version_postflight.txt" 2>&1

if grep -Eiq 'with[[:space:]]+uncommitt?ed[[:space:]]+changes' \
    "$OUT/tamarin_version_postflight.txt"; then
    die "dirty marker appeared in postflight"
fi

POST_BIN="$(sha256sum "$RESOLVED_BIN" | awk '{print $1}')"
POST_MODEL="$(sha256sum "$FINAL_MODEL" | awk '{print $1}')"

[[ "$POST_BIN" == "$ACTUAL_BIN" ]] || die "Tamarin binary changed during run"
[[ "$POST_MODEL" == "$ACTUAL_MODEL" ]] || die "final model changed during run"

# All staged theories must still match the pinned manifest.
sha256sum -c metadata/stage_theory_sha256.txt \
    > "$OUT/stage_hash_postflight.txt"

{
    echo "pre_binary_sha256=$ACTUAL_BIN"
    echo "post_binary_sha256=$POST_BIN"
    echo "pre_final_model_sha256=$ACTUAL_MODEL"
    echo "post_final_model_sha256=$POST_MODEL"
    echo "dirty_marker_preflight=no"
    echo "dirty_marker_postflight=no"
    echo "mismatches_or_nonclean_runs=$FAILS"
    echo "completed_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$OUT/postflight_integrity.txt"

find "$OUT" -maxdepth 1 -type f \
    ! -name 'artifacts_sha256.txt' \
    -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    > "$OUT/artifacts_sha256.txt"

echo
echo "============================================================"
echo "Nine-stage measurement completed"
echo "============================================================"
echo "Results: $CSV"
echo "Mismatches/nonclean runs: $FAILS"
echo

if [[ "$FAILS" -eq 0 ]]; then
    echo "ALL NINE STAGES MATCH THE EXPECTED HEADLINE VERDICTS."
    exit 0
else
    echo "One or more stages require inspection."
    exit 10
fi
