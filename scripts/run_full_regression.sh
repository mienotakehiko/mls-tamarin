#!/usr/bin/env bash
# run_full_regression.sh
#
# Reproduce the full nine-lemma regression of Table 1 of the paper.
# The script pins the Tamarin binary and the theory file via SHA-256 before
# invocation, runs a single `--prove` under GNU `/usr/bin/time -v`, and pins
# the same digests again after invocation. Any mismatch aborts the run.
#
# Environment:
#   TAMARIN   absolute path to a Tamarin Prover 1.12.0 executable.
#             Strongly recommended to be a clean release build whose SHA-256
#             matches metadata/tamarin_binary_sha256.txt.
#
# Output layout (created below the current working directory):
#   results/clean_release/full/full_once.log
#   results/clean_release/full/full_once.time.txt
#   results/clean_release/full/full_once.exitcode
#   results/clean_release/full/reproducibility_metadata.txt
#   results/clean_release/full/postflight_integrity.txt

set -euo pipefail

: "${TAMARIN:?please export TAMARIN to the absolute path of your tamarin-prover binary}"

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

MODEL="theories/mls_ratchet_tree_semantic_final.spthy"
OUT_DIR="results/clean_release/full"
mkdir -p "$OUT_DIR"

# Preflight: record the SHA-256 of the executable and the model.
PRE_BIN=$(sha256sum "$(readlink -f "$TAMARIN")" | awk '{print $1}')
PRE_MOD=$(sha256sum "$MODEL"                    | awk '{print $1}')

"$REPO_ROOT/scripts/record_provenance.sh" \
  "$TAMARIN" "$MODEL" "$OUT_DIR/reproducibility_metadata.txt"

# Invocation.
set +e
/usr/bin/time -v -o "$OUT_DIR/full_once.time.txt" \
  timeout --kill-after=30s 3600s \
  "$TAMARIN" --prove "$MODEL" > "$OUT_DIR/full_once.log" 2>&1
EXIT=$?
set -e
echo "$EXIT" > "$OUT_DIR/full_once.exitcode"

# Postflight: SHA-256 must be unchanged.
POST_BIN=$(sha256sum "$(readlink -f "$TAMARIN")" | awk '{print $1}')
POST_MOD=$(sha256sum "$MODEL"                    | awk '{print $1}')

{
  echo "pre_binary_sha256=$PRE_BIN"
  echo "post_binary_sha256=$POST_BIN"
  echo "pre_model_sha256=$PRE_MOD"
  echo "post_model_sha256=$POST_MOD"
  echo "full_exit_code=$EXIT"
  echo "measurement_completed_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
} > "$OUT_DIR/postflight_integrity.txt"

if [[ "$PRE_BIN" != "$POST_BIN" || "$PRE_MOD" != "$POST_MOD" ]]; then
  echo "FATAL: binary or model digest changed during measurement." >&2
  exit 5
fi

echo "full regression finished with exit code $EXIT"
echo "log:  $OUT_DIR/full_once.log"
echo "time: $OUT_DIR/full_once.time.txt"
