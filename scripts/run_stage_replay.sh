#!/usr/bin/env bash
# run_stage_replay.sh
#
# Replay the seven staged models of Section VI of the paper in order. Each
# staged theory carries a small, well-defined change with respect to the
# previous one, so the sequence of verdicts documents which single modelling
# decision flips which lemma.
#
# The script invokes each theory once with `--prove`, writes the log under
# results/stage_replay/, and prints a compact one-line summary per stage.
#
# Environment:
#   TAMARIN   absolute path to a Tamarin Prover 1.12.0 executable.

set -euo pipefail

: "${TAMARIN:?please export TAMARIN to the absolute path of your tamarin-prover binary}"

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

OUT_DIR="results/stage_replay"
mkdir -p "$OUT_DIR"

stages=(
  "stage1      theories/stages/stage1_private_kdf.spthy"
  "stage1c     theories/stages/stage1c_public_kdf_control.spthy"
  "stage2      theories/stages/stage2_private_fs.spthy"
  "stage3      theories/stages/stage3_private_pcs.spthy"
  "stage4_p1   theories/stages/stage4_p1_public_unauth_kp.spthy"
  "stage4_p2   theories/stages/stage4_p2_public_valid_kp.spthy"
  "stage5      theories/stages/stage5_public_fs.spthy"
  "stage6_v1   theories/stages/stage6_v1_simplified_pcs.spthy"
  "stage7_v2   theories/stages/stage7_v2_copath_pcs.spthy"
)

printf "%-12s %-12s %-8s %s\n" "stage" "verdict" "steps" "log"
for entry in "${stages[@]}"; do
  read -r NAME PATH_TO_SPTHY <<<"$entry"

  if [[ ! -f "$PATH_TO_SPTHY" ]]; then
    printf "%-12s %-12s %-8s %s\n" "$NAME" "SKIP" "-" "(missing: $PATH_TO_SPTHY)"
    continue
  fi

  LOG="$OUT_DIR/${NAME}.log"

  set +e
  timeout --kill-after=30s 3600s \
    "$TAMARIN" --prove "$PATH_TO_SPTHY" > "$LOG" 2>&1
  set -e

  VERDICT=$(grep -oE ': (verified|falsified)' "$LOG" | head -1 | tr -d ': ')
  STEPS=$(grep -oE '\(([0-9]+) steps\)' "$LOG" | head -1 | tr -dc '0-9')
  [[ -z "$VERDICT" ]] && VERDICT="unknown"
  [[ -z "$STEPS"   ]] && STEPS="-"

  printf "%-12s %-12s %-8s %s\n" "$NAME" "$VERDICT" "$STEPS" "$LOG"
done
