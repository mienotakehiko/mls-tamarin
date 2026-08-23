#!/usr/bin/env bash
# record_provenance.sh
#
# Emit a reproducibility-metadata block for the current measurement session.
# The block pins the Tamarin binary in use, its SHA-256, the model file in
# use, its SHA-256, the CPU and memory of the host, and the local UTC time.
# The three arguments are the Tamarin binary path, the model file path, and
# the output file to write.
#
# Usage:
#   ./scripts/record_provenance.sh "$TAMARIN" theories/mls_ratchet_tree_semantic_final.spthy \
#                                  results/clean_release/full/reproducibility_metadata.txt

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <tamarin-binary> <model.spthy> <output.txt>" >&2
  exit 2
fi

TAMARIN=$1
MODEL=$2
OUT=$3

if [[ ! -x "$TAMARIN" ]]; then
  echo "error: Tamarin binary not executable: $TAMARIN" >&2
  exit 3
fi
if [[ ! -f "$MODEL" ]]; then
  echo "error: model file not found: $MODEL" >&2
  exit 4
fi

RESOLVED_TAMARIN=$(readlink -f "$TAMARIN")
TAMARIN_SHA=$(sha256sum "$RESOLVED_TAMARIN" | awk '{print $1}')
MODEL_SHA=$(sha256sum "$MODEL" | awk '{print $1}')

{
  echo "audit_utc=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo "hostname=$(hostname)"
  echo "kernel=$(uname -srm) $(uname -o)"
  echo "model=$MODEL"
  echo "model_sha256=$MODEL_SHA"
  echo "clean_binary=$TAMARIN"
  echo "resolved_clean_binary=$RESOLVED_TAMARIN"
  echo "clean_binary_sha256=$TAMARIN_SHA"
  echo "nproc=$(nproc)"
  echo ""
  echo "--- selected Tamarin -V ---"
  "$RESOLVED_TAMARIN" -V 2>&1 || true
  echo ""
  echo "--- memory ---"
  free -h 2>&1 || true
  echo ""
  echo "--- CPU ---"
  lscpu 2>&1 | head -12 || true
} > "$OUT"

echo "wrote $OUT" >&2
