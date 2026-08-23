#!/usr/bin/env bash
# verify_stage_derivations.sh
#
# Sanity-check the nine staged theories against the verdict pattern
# reported in Section VI of the paper. This script is intended to be
# run once on the reference host after the artifact is unpacked or
# freshly cloned. Any deviation of an observed verdict from the
# expected verdict is a defect in the derivation and should be filed
# against the shipping author's repository.
#
# Environment:
#   TAMARIN   absolute path to a Tamarin Prover 1.12.0 executable
#             (a clean release build is strongly recommended; use the
#             executable pinned in metadata/tamarin_binary_sha256.txt).
#
# Output:
#   * one Tamarin log per stage under results/stage_replay/;
#   * a summary table on stdout listing observed vs expected verdicts;
#   * exit code 0 when all observations match the expectation, exit
#     code 1 when at least one stage disagrees.

set -euo pipefail

: "${TAMARIN:?please export TAMARIN to the absolute path of your tamarin-prover binary}"

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

OUT_DIR="results/stage_replay"
mkdir -p "$OUT_DIR"

# Format: stage_id | theory | headline_lemma | expected_verdict
stages=(
  "stage1     | theories/stages/stage1_private_kdf.spthy           | L1_baseline_secrecy             | verified"
  "stage1c    | theories/stages/stage1c_public_kdf_control.spthy   | L1_baseline_secrecy             | falsified"
  "stage2     | theories/stages/stage2_private_fs.spthy            | L2_forward_secrecy              | verified"
  "stage3     | theories/stages/stage3_private_pcs.spthy           | L3_post_compromise_security     | verified"
  "stage4_p1  | theories/stages/stage4_p1_public_unauth_kp.spthy   | L1_baseline_secrecy             | falsified"
  "stage4_p2  | theories/stages/stage4_p2_public_valid_kp.spthy    | L1_baseline_secrecy             | verified"
  "stage5     | theories/stages/stage5_public_fs.spthy             | L2_forward_secrecy              | verified"
  "stage6_v1  | theories/stages/stage6_v1_simplified_pcs.spthy     | L3_post_compromise_security     | falsified"
  "stage7_v2  | theories/stages/stage7_v2_copath_pcs.spthy         | L3_post_compromise_security     | verified"
)

printf "%-11s %-32s %-10s %-10s %s\n" "stage" "headline_lemma" "expected" "observed" "status"
FAILS=0
for entry in "${stages[@]}"; do
  IFS='|' read -r NAME THEORY LEMMA EXPECTED <<<"$entry"
  NAME=$(echo "$NAME" | xargs)
  THEORY=$(echo "$THEORY" | xargs)
  LEMMA=$(echo "$LEMMA" | xargs)
  EXPECTED=$(echo "$EXPECTED" | xargs)

  if [[ ! -f "$THEORY" ]]; then
    printf "%-11s %-32s %-10s %-10s %s\n" "$NAME" "$LEMMA" "$EXPECTED" "-" "MISSING"
    FAILS=$((FAILS + 1))
    continue
  fi

  LOG="$OUT_DIR/${NAME}.log"
  set +e
  timeout --kill-after=30s 3600s \
    "$TAMARIN" --prove="$LEMMA" "$THEORY" > "$LOG" 2>&1
  set -e

  if   grep -q "^  ${LEMMA} .*: verified"  "$LOG"; then OBS=verified
  elif grep -q "^  ${LEMMA} .*: falsified" "$LOG"; then OBS=falsified
  else                                                  OBS=unknown
  fi

  if [[ "$OBS" == "$EXPECTED" ]]; then STATUS=OK; else STATUS=MISMATCH; FAILS=$((FAILS + 1)); fi
  printf "%-11s %-32s %-10s %-10s %s\n" "$NAME" "$LEMMA" "$EXPECTED" "$OBS" "$STATUS"
done

echo ""
if [[ $FAILS -eq 0 ]]; then
  echo "All nine stages observed the expected verdict."
  exit 0
else
  echo "$FAILS stage(s) disagreed with the expected verdict; please file an issue."
  exit 1
fi
