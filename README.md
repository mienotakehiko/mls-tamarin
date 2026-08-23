# mls-tamarin

Companion artifact for the CSCI 2026 paper *Staged Symbolic Analysis of the MLS Ratchet Tree in Tamarin* by Takehiko Mieno. This repository accompanies the paper as a self-contained artifact: the final Tamarin theory, the nine staged intermediates that back Section 6 of the paper, the measurement scripts, the raw per-repetition logs, and the reproducibility metadata that binds the numbers of the paper to a specific Tamarin binary and a specific model file.

This repository holds only what a third party needs in order to rerun every experiment reported in the paper.

## Scope

This repository lets a reader:

* rerun the full nine-lemma regression on the final model and reproduce the verdicts of Table 1 of the paper;
* rerun the ten-repetition reproducibility experiment on the two headline lemmas `L2_forward_secrecy` and `L3_post_compromise_security`;
* replay each of the nine staged theories to observe how a single modelling decision (KDF visibility, KeyPackage authentication, UpdatePath abstraction) flips the verdict;
* replay the ten-repetition monotonic re-measurement of `stage3` that resolves the wall-clock anomaly of the original nine-stage session;
* verify the integrity of the theory files and of the Tamarin executable through the recorded SHA-256 digests.

## Repository layout

```
mls-tamarin/
├── README.md
├── LICENSE
├── CITATION.cff
├── theories/
│   ├── mls_ratchet_tree_semantic_final.spthy    # final model (headline result)
│   ├── stages/
│   │   ├── README.md                            # per-stage lineage table
│   │   ├── stage1_private_kdf.spthy             # L1 verified (feasibility)
│   │   ├── stage1c_public_kdf_control.spthy     # L1 falsified (public-KDF ablation)
│   │   ├── stage2_private_fs.spthy              # L2 verified (private KDF)
│   │   ├── stage3_private_pcs.spthy             # L3 verified (private KDF)
│   │   ├── stage4_p1_public_unauth_kp.spthy     # L1 falsified (missing AS)
│   │   ├── stage4_p2_public_valid_kp.spthy      # L1 verified (with AS)
│   │   ├── stage5_public_fs.spthy               # L2 verified (public KDF)
│   │   ├── stage6_v1_simplified_pcs.spthy       # L3 falsified (simplified UpdatePath)
│   │   └── stage7_v2_copath_pcs.spthy           # L3 verified (identical to final)
│   └── prototype/
│       └── mls_mini_v4.spthy                    # early ProVerif-comparable prototype
├── scripts/
│   ├── record_provenance.sh                     # pre/post SHA-256 and version capture
│   ├── run_full_regression.sh                   # single --prove of the final theory
│   ├── run_L2_repeat10.sh                       # ten repetitions of L2_forward_secrecy
│   ├── run_L3_repeat10.sh                       # ten repetitions of L3_post_compromise_security
│   ├── run_stage_replay.sh                      # invokes each of the nine staged theories once
│   ├── measure_stage_headlines_clean.sh         # nine-stage headline session (first pass)
│   ├── measure_stage_headlines_clean_v2.sh      # nine-stage headline session (corrected-v2 pass)
│   ├── diagnose_stage_l1_lineage.sh             # L1-only subset for the four L1 stages
│   ├── remeasure_stage3_monotonic.sh            # ten repetitions of stage3 with a monotonic clock
│   ├── verify_stage_derivations.sh              # checks observed vs expected verdicts
│   └── summarise_repeat.py                      # CSV → mean/stdev/min/max summary
├── results/
│   ├── clean_release/
│   │   ├── full/                                # full nine-lemma regression on the final model
│   │   └── L2_L3/                               # ten repetitions of L2 and L3 (final model)
│   ├── stage_headline_measurement_v2/           # nine-stage headline session (all nine stages)
│   ├── stage_l1_diagnostic/                     # L1-only subset (stage1, 1c, 4-P1, 4-P2)
│   └── stage3_monotonic_repeat10/               # ten repetitions of stage3 with a monotonic clock
└── metadata/
    ├── model_sha256.txt
    ├── stage_theory_sha256.txt
    ├── stage_artifact_revision.txt
    ├── tamarin_binary_sha256.txt
    ├── clean_build_audit.txt
    ├── source_status_before_build.txt
    └── source_status_after_build.txt
```

The paper source (TeX) and its PDF are excluded on purpose.

## Prerequisites

The final measurements reported in the paper used the following stack. Any environment that reproduces this stack should reproduce the invariants (verdict, proof-step count, source-saturation depth) exactly; wall-clock time and peak memory naturally vary with the host.

* Tamarin Prover 1.12.0, clean release build at Git revision `82780bbaf3328a45f624ddb41e51bf75425f851c`.
* Maude 3.5.1.
* GHC / cabal as required by Tamarin (only needed when building Tamarin from source).
* GNU coreutils (`sha256sum`, `/usr/bin/time -v`), Python 3.10 or newer for `summarise_repeat.py` and for the monotonic re-measurement script.
* An x86_64 host with at least 16 GiB of RAM. The L3 lemma peaks at roughly 4.7 GiB, and the full regression peaks at roughly 11.5 GiB.

The reference host is an Intel Core i7-13700H with eight logical CPUs exposed to WSL2 running Ubuntu 24.04, 50 GiB of RAM allocated to the WSL2 VM, and swap disabled.

## Binary and model integrity

The final measurements in this artifact are bound to the following digests. `record_provenance.sh` writes these digests before and after every measurement session and the postflight files under `results/` refuse to declare success on mismatch.

* Final theory `theories/mls_ratchet_tree_semantic_final.spthy`
  SHA-256 `054de69086fdbf5cd1f4158b18edde5a0434e61436080d3ccf3b84cf7e80be03`.
* Clean release Tamarin executable
  SHA-256 `39cfd71ce7cd9028badbcf22729c807a78040ebc9665207d52f140994bf596a0`.

The executable reports version `tamarin-prover 1.12.0` at Git revision `82780bbaf3328a45f624ddb41e51bf75425f851c` on branch `HEAD`, with no `with uncommited changes` marker. The three build-audit files under `metadata/` record the state of the source tree before and after the build, so the provenance chain from source to binary to result can be inspected end-to-end. Each staged theory's individual SHA-256 is pinned in `metadata/stage_theory_sha256.txt`.

## Quick start

The scripts below assume that a Tamarin executable exists on disk and that its path has been exported. Using an absolute path to a known clean build is strongly recommended over relying on `$PATH`, since a system-wide `tamarin-prover` may resolve to an unrelated build.

```bash
git clone https://github.com/mienotakehiko/mls-tamarin.git
cd mls-tamarin
export TAMARIN=/absolute/path/to/tamarin-prover-1.12.0
sha256sum "$TAMARIN"   # should match metadata/tamarin_binary_sha256.txt
```

### Reproduce the headline verdict

A single `--prove` invocation reproduces every lemma of Table 1 of the paper:

```bash
./scripts/run_full_regression.sh
```

The script records the pre-measurement digests, invokes Tamarin on the final theory under `/usr/bin/time -v`, and records the post-measurement digests. On the reference host this takes about eight minutes of wall time and peaks at roughly 11.5 GiB of resident memory. The expected outcome is:

| Property                          | Expected  | Result     | Steps |
|-----------------------------------|-----------|------------|------:|
| `exec_normal_flow_alice_recv`     | reachable | verified   |    22 |
| `exec_normal_flow_bob_recv`       | reachable | verified   |    18 |
| `L1_baseline_secrecy`             | secure    | verified   |    52 |
| `exec_fs_current_compromise`      | reachable | verified   |    14 |
| `L2_forward_secrecy`              | secure    | verified   | 1,347 |
| `L2_same_epoch_reveal_control`    | insecure  | falsified  |    12 |
| `exec_pcs_healing`                | reachable | verified   |    30 |
| `L3_post_compromise_security`     | secure    | verified   | 4,336 |
| `L3_healed_epoch_reveal_control`  | insecure  | falsified  |    30 |

All well-formedness checks pass and source saturation terminates at depth 2 without any auxiliary `sources` lemma.

### Reproduce the ten-run stability experiment

Two scripts drive the ten repetitions per headline lemma described in Section 7 of the paper:

```bash
./scripts/run_L2_repeat10.sh
./scripts/run_L3_repeat10.sh
python3 scripts/summarise_repeat.py results/clean_release/L2_L3/L2_repeat10.csv
python3 scripts/summarise_repeat.py results/clean_release/L2_L3/L3_repeat10.csv
```

Each repetition writes an isolated log, a `/usr/bin/time -v` record, and one row of the corresponding CSV. The summary script prints the mean, median, standard deviation, min and max of wall time and peak resident set size. On the reference host the clean-release session produced:

| Lemma                             | Verdict           | Wall (s)        | Peak RSS (MiB) | Proof steps | Sources saturation |
|-----------------------------------|-------------------|-----------------|---------------:|------------:|-------------------:|
| `L2_forward_secrecy`              | 10 / 10 verified  | 54.74 ± 2.94    | 938.9          | 1,347 × 10  | 2 × 10             |
| `L3_post_compromise_security`     | 10 / 10 verified  | 212.16 ± 7.91   | 4,734.9        | 4,336 × 10  | 2 × 10             |

Only wall-clock time and resident memory vary between repetitions. The verdict, the proof-step count, the source-saturation depth, the well-formedness status, and the exit code are identical across all ten runs of each lemma.

### Replay the nine staged theories

Section 6 of the paper argues that the final verdict depends on three explicit modelling decisions: whether the tree KDF is a private function, whether KeyPackages are validated by an authentication service, and whether UpdatePath is abstracted to encryption under the copath resolution or under a single old node key. The following script replays the nine staged theories in order and reports each verdict:

```bash
./scripts/run_stage_replay.sh
```

On the reference host every stage matched its expectation and produced source saturation, `successful` well-formedness, `clean` warnings, and exit code zero:

| Stage       | Change from previous stage                          | Headline verdict            | Proof steps |
|-------------|-----------------------------------------------------|-----------------------------|------------:|
| stage1      | Private KDF, no compromise                          | L1 verified                 |           3 |
| stage1c     | Public KDF, otherwise identical (ablation)          | L1 falsified                |          10 |
| stage2      | Private KDF plus forward-secrecy interface          | L2 verified                 |          18 |
| stage3      | Private KDF plus PCS interface                      | L3 verified                 |          18 |
| stage4_p1   | Public KDF plus trusted Alice PK only               | L1 falsified                |          16 |
| stage4_p2   | Public KDF plus AS-validated KeyPackages            | L1 verified                 |         244 |
| stage5      | stage4_p2 plus forward secrecy                      | L2 verified                 |       1,686 |
| stage6_v1   | Simplified UpdatePath abstraction                   | L3 falsified                |          17 |
| stage7_v2   | Copath-resolution UpdatePath abstraction (final)    | L3 verified                 |       4,336 |

The `stage1c`, `stage4_p1` and `stage6_v1` runs are ablation controls: the falsifications they produce are not attacks on MLS itself, but artefacts of the deliberately weakened models used to isolate the modelling assumption under study.

### Monotonic re-measurement of `stage3`

The original nine-stage session recorded a negative wall-clock time for `stage3` (`-2.41` s), inherited from a WSL host clock synchronisation event that struck the shell during that run. The Tamarin proof itself completed successfully, but the wall time was unusable. To close this gap, this artifact ships a separate ten-repetition monotonic re-measurement:

```bash
./scripts/remeasure_stage3_monotonic.sh "$PWD"
cat results/stage3_monotonic_repeat10/stage3_repeat10_summary.txt
cat results/stage3_monotonic_repeat10/stage3_repeat10.csv
```

The script keeps `/usr/bin/time -v` for peak resident set size but measures elapsed time independently with `time.monotonic_ns()` in Python, so a backward jump of the system wall clock cannot produce a negative reading. On the reference host all ten repetitions verified `L3_post_compromise_security` in 18 proof steps with source saturation at depth 1, `successful` well-formedness, `clean` warnings and exit code zero:

| Metric                           | Value                    |
|----------------------------------|--------------------------|
| Runs                             | 10                       |
| Result                           | 10 / 10 verified         |
| Proof steps                      | 18 × 10                  |
| Sources saturation               | Step 1 × 10              |
| Mean monotonic wall time         | 1.342 s                  |
| Median                           | 1.372 s                  |
| Standard deviation               | 0.074 s                  |
| Range                            | 1.196 – 1.425 s          |
| Mean peak resident set size      | 105.9 MiB                |
| Warnings                         | clean                    |

The corresponding row of `results/stage_headline_measurement_v2/stage_headline_results.csv` remains as originally recorded (with its `-2.41` wall time) for audit; a sibling file `stage_headline_results_authoritative.csv` carries the same schema plus two extra columns that point at the monotonic mean for `stage3` and mark every other row as authoritative in place.

## What this artifact does not claim

The artifact reproduces exactly the experiments reported in the paper, no more. In particular:

* The verified security properties hold within the symbolic model of Section 5 of the paper and under the trust and compromise assumptions stated there. Full-device compromise, side channels, cryptographic implementation flaws, and the group-membership service beyond the abstracted authentication service are out of scope.
* The final PCS result concerns exposure of the previous shared path state while the copath-resolution private keys of honest members remain uncompromised. It is not a statement about arbitrary post-compromise recovery from full endpoint takeover.
* No claim of semantic equivalence with any other tool (ProVerif, CryptoVerif, an F* mechanisation, or the manual proofs in the literature) is asserted. The prototype under `theories/prototype/` is included only as an artifact of an earlier consistency check and is not on the certification path of the final model.
* `stage3`'s verdict and proof-step count are treated as the authoritative evidence of Section 6; the monotonic re-measurement supplies the associated performance figure. The original nine-stage session's `-2.41` wall time is retained purely for audit.

## Reusing the artifact

Reuse is welcome under the license below. When reusing the theories or the staged narrative, please retain the SHA-256 pinning of `mls_ratchet_tree_semantic_final.spthy` in downstream reports: the digest `054de690...80be03` is the identifier of the exact model whose verdicts appear in the paper. Any modification, however minor, should be shipped under a fresh digest.

## License

The Tamarin theories, scripts, and metadata files in this repository are released under the MIT License. See `LICENSE` for the full text.

## Contact

Issues and questions are best raised through the GitHub issue tracker of this repository. 
Correspondence about the paper itself should be directed to the author via the contact address printed on the paper.


(C) 2026 Takehiko Mieno