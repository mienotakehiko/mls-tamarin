#!/usr/bin/env bash
# run_L2_repeat10.sh
#
# Repeat the `L2_forward_secrecy` lemma ten times on the final model and
# emit one CSV row per repetition. The columns of the CSV are:
#   rep,wall_seconds,max_rss_kb,exit_code,verdict,steps,sources_steps,warnings
#
# Environment:
#   TAMARIN   absolute path to a Tamarin Prover 1.12.0 executable.
#
# Output layout:
#   results/clean_release/L2_L3/L2_repeat10.csv
#   results/clean_release/L2_L3/L2_run_{1..10}.log
#   results/clean_release/L2_L3/L2_run_{1..10}.time
#   results/clean_release/L2_L3/reproducibility_metadata.txt
#   results/clean_release/L2_L3/postflight_integrity.txt

set -euo pipefail

: "${TAMARIN:?please export TAMARIN to the absolute path of your tamarin-prover binary}"

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

MODEL="theories/mls_ratchet_tree_semantic_final.spthy"
OUT_DIR="results/clean_release/L2_L3"
LEMMA="L2_forward_secrecy"
CSV="$OUT_DIR/L2_repeat10.csv"
mkdir -p "$OUT_DIR"

PRE_BIN=$(sha256sum "$(readlink -f "$TAMARIN")" | awk '{print $1}')
PRE_MOD=$(sha256sum "$MODEL"                    | awk '{print $1}')

"$REPO_ROOT/scripts/record_provenance.sh" \
  "$TAMARIN" "$MODEL" "$OUT_DIR/reproducibility_metadata.txt"

echo "rep,wall_seconds,max_rss_kb,exit_code,verdict,steps,sources_steps,warnings" > "$CSV"

for rep in $(seq 1 10); do
  LOG="$OUT_DIR/L2_run_${rep}.log"
  TIME_FILE="$OUT_DIR/L2_run_${rep}.time"

  set +e
  /usr/bin/time -v -o "$TIME_FILE" \
    timeout --kill-after=30s 3600s \
    "$TAMARIN" --prove="$LEMMA" "$MODEL" > "$LOG" 2>&1
  EXIT=$?
  set -e

  WALL=$(awk -F': ' '/Elapsed \(wall clock\)/ {print $2}' "$TIME_FILE" \
         | awk -F: '{ if (NF==3) print $1*3600+$2*60+$3; else if (NF==2) print $1*60+$2; else print $1 }')
  RSS=$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TIME_FILE")

  if   grep -q "^  ${LEMMA} .*: verified"           "$LOG"; then VERDICT=verified
  elif grep -q "^  ${LEMMA} .*: falsified"          "$LOG"; then VERDICT=falsified
  else                                                          VERDICT=unknown
  fi

  STEPS=$(grep -E "^  ${LEMMA} .*\(([0-9]+) steps\)" "$LOG" \
          | sed -E 's/.*\(([0-9]+) steps\).*/\1/' | head -1)
  SOURCES=$(grep -oE 'source[s]? saturated after [0-9]+' "$LOG" \
            | awk '{print $NF}' | head -1)
  [[ -z "$STEPS"   ]] && STEPS="NA"
  [[ -z "$SOURCES" ]] && SOURCES="NA"

  if grep -q "wellformedness checks were successful" "$LOG"; then WARN=clean; else WARN=nonclean; fi

  echo "${rep},${WALL},${RSS},${EXIT},${VERDICT},${STEPS},${SOURCES},${WARN}" >> "$CSV"
  echo "L2 rep ${rep}: verdict=${VERDICT} steps=${STEPS} wall=${WALL}s rss=${RSS}KB"
done

POST_BIN=$(sha256sum "$(readlink -f "$TAMARIN")" | awk '{print $1}')
POST_MOD=$(sha256sum "$MODEL"                    | awk '{print $1}')

{
  echo "pre_binary_sha256=$PRE_BIN"
  echo "post_binary_sha256=$POST_BIN"
  echo "pre_model_sha256=$PRE_MOD"
  echo "post_model_sha256=$POST_MOD"
  echo "measurement_completed_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} > "$OUT_DIR/postflight_integrity_L2.txt"

if [[ "$PRE_BIN" != "$POST_BIN" || "$PRE_MOD" != "$POST_MOD" ]]; then
  echo "FATAL: binary or model digest changed during measurement." >&2
  exit 5
fi

echo "L2 repeat10 finished; CSV at $CSV"
