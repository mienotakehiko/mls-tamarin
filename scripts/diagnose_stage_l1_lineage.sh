#!/usr/bin/env bash
# Corrected-v2 four-stage L1 lineage diagnostic.
set -euo pipefail

REPO_ROOT="${1:-$PWD}"
TAMARIN="${TAMARIN:-$HOME/tamarin-clean-1.12.0/bin/tamarin-prover-1.12.0-clean}"
OUT="$REPO_ROOT/results/stage_l1_diagnostic"
BUDGET="${BUDGET:-3600}"

die() { echo "ERROR: $*" >&2; exit 1; }

cd "$REPO_ROOT"

echo "============================================================"
echo "Corrected-v2 L1 stage diagnostic"
echo "============================================================"
echo "REPO_ROOT=$(pwd)"
echo "TAMARIN=$TAMARIN"
echo

[[ -f metadata/stage_artifact_revision.txt ]] || \
  die "corrected-v2 marker missing; wrong repository?"
grep -q '^artifact_revision=corrected-v2-historical-stages$' \
  metadata/stage_artifact_revision.txt || \
  die "unexpected artifact revision; wrong repository?"

[[ -f metadata/stage_theory_sha256.txt ]] || die "stage hash manifest missing"
[[ -x "$TAMARIN" ]] || die "Tamarin not executable: $TAMARIN"

echo "===== artifact marker ====="
cat metadata/stage_artifact_revision.txt
echo

echo "===== checking all staged theory hashes ====="
sha256sum -c metadata/stage_theory_sha256.txt
echo

# Semantic-shape guards specifically for the two stages that were wrong
# in the first reconstructed artifact.
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
  die "stage4_p1 does not use a public KDF"
grep -q 'pk_w_old = pk(node_sk(ps_w_old))' "$P1" || \
  die "stage4_p1 does not retain the historical old-node Update"
if grep -q 'ResolutionKey' "$P1"; then
  die "stage4_p1 unexpectedly contains copath-resolution keys"
fi

echo "Semantic-shape guards: PASS"
echo

rm -rf "$OUT"
mkdir -p "$OUT"

"$TAMARIN" -V > "$OUT/tamarin_version.txt" 2>&1
grep -Eq '1\.12\.0' "$OUT/tamarin_version.txt" || die "Tamarin 1.12.0 not reported"
grep -Eq '82780bb' "$OUT/tamarin_version.txt" || die "release revision 82780bb not reported"
if grep -Eiq 'with[[:space:]]+uncommitt?ed[[:space:]]+changes' \
  "$OUT/tamarin_version.txt"; then
  die "dirty Tamarin build marker detected"
fi

EXPECTED_BIN=$(awk '{print $1}' metadata/tamarin_binary_sha256.txt)
ACTUAL_BIN=$(sha256sum "$(readlink -f "$TAMARIN")" | awk '{print $1}')
[[ "$ACTUAL_BIN" == "$EXPECTED_BIN" ]] || \
  die "Tamarin SHA mismatch: actual=$ACTUAL_BIN expected=$EXPECTED_BIN"

EXPECTED_MODEL=$(awk '{print $1}' metadata/model_sha256.txt)
ACTUAL_MODEL=$(sha256sum theories/mls_ratchet_tree_semantic_final.spthy | awk '{print $1}')
[[ "$ACTUAL_MODEL" == "$EXPECTED_MODEL" ]] || \
  die "final model SHA mismatch: actual=$ACTUAL_MODEL expected=$EXPECTED_MODEL"

echo "stage,theory,theory_sha256,verdict,steps,wall_seconds,max_rss_kb,exit_code,sources_step,warnings" \
  > "$OUT/l1_diagnostic.csv"

stages=(
  "stage1|theories/stages/stage1_private_kdf.spthy"
  "stage1c|theories/stages/stage1c_public_kdf_control.spthy"
  "stage4_p1|theories/stages/stage4_p1_public_unauth_kp.spthy"
  "stage4_p2|theories/stages/stage4_p2_public_valid_kp.spthy"
)

LEMMA="L1_baseline_secrecy"

printf "%-10s %-11s %-8s %-10s %-10s %s\n" \
  "stage" "verdict" "steps" "wall(s)" "RSS(MiB)" "warnings"

for entry in "${stages[@]}"; do
  IFS='|' read -r NAME THEORY <<<"$entry"
  [[ -f "$THEORY" ]] || die "missing theory: $THEORY"

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

  VERDICT=unknown
  grep -q 'verified' <<<"$LINE" && VERDICT=verified
  grep -q 'falsified' <<<"$LINE" && VERDICT=falsified

  STEPS=$(grep -oE '\([0-9]+ steps\)' <<<"$LINE" |
          grep -oE '[0-9]+' | tail -1 || true)
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

  SOURCES=$(grep -oE 'Saturating Sources] Step [0-9]+' "$LOG" |
            grep -oE '[0-9]+' | tail -1 || true)
  [[ -n "$SOURCES" ]] || SOURCES=NA

  WARN=clean
  if grep -qE \
    'WARNING:|wellformedness checks failed|Fact arity|Fact multiplicity|Subterm Convergence Warning|Message Derivation Checks|Failed to derive' \
    "$LOG"; then
    WARN=present
  fi

  echo "$NAME,$THEORY,$THEORY_SHA,$VERDICT,$STEPS,$WALL_SEC,$RSS,$RC,$SOURCES,$WARN" \
    >> "$OUT/l1_diagnostic.csv"

  printf "%-10s %-11s %-8s %-10s %-10s %s\n" \
    "$NAME" "$VERDICT" "$STEPS" "$WALL_SEC" "$RSS_MIB" "$WARN"
done

echo
echo "Expected corrected-v2 pattern:"
echo "  stage1     = verified"
echo "  stage1c    = falsified"
echo "  stage4_p1  = falsified"
echo "  stage4_p2  = verified"
echo
echo "RESULT_DIR=$OUT"
echo "CSV=$OUT/l1_diagnostic.csv"
