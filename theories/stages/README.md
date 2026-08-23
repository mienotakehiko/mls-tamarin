# Staged theories

This directory carries the nine staged theories that back Section 6 of the paper. Each stage differs from the previous one by a single, deliberately isolated modelling decision, so the sequence of Tamarin verdicts documents which decision flips which lemma. Section 6 reports the observed verdict per stage against the expectation, and the refinement narrative rests on the sequence being reproducible.

## Provenance

The nine theories shipped here are the historical intermediate files that were used to produce the verdicts recorded in Section 6. `metadata/stage_artifact_revision.txt` pins the revision string as `corrected-v2-historical-stages`; `metadata/stage_theory_sha256.txt` pins each stage file's SHA-256 individually. The final model `theories/mls_ratchet_tree_semantic_final.spthy` and `stage7_v2_copath_pcs.spthy` share the digest `054de690...80be03` and are bit-identical.

## Stage lineage

| File                                    | Purpose                                                                                                 | SHA-256 (first 12 hex)   |
|-----------------------------------------|---------------------------------------------------------------------------------------------------------|--------------------------|
| `stage1_private_kdf.spthy`              | Private-KDF feasibility baseline. L1 verified.                                                          | `fe5141bcfc32`           |
| `stage1c_public_kdf_control.spthy`      | Public-KDF ablation control. L1 falsified.                                                              | `582b9643ab01`           |
| `stage2_private_fs.spthy`               | Forward secrecy under private KDF. L2 verified.                                                         | `aeee4d6833bd`           |
| `stage3_private_pcs.spthy`              | Post-compromise security under private KDF. L3 verified.                                                | `dca9d4e6e484`           |
| `stage4_p1_public_unauth_kp.spthy`      | Public KDF plus trusted Alice PK only, no KeyPackage validation. L1 falsified.                          | `6d85c7c6fa63`           |
| `stage4_p2_public_valid_kp.spthy`       | Public KDF plus AS-validated KeyPackages. L1 verified.                                                  | `0942508c53af`           |
| `stage5_public_fs.spthy`                | Forward secrecy on top of `stage4_p2`. L2 verified.                                                     | `5c1e93fbccfa`           |
| `stage6_v1_simplified_pcs.spthy`        | Simplified UpdatePath abstraction. L3 falsified (modelling artefact, not an attack on MLS).             | `d28244a44ce9`           |
| `stage7_v2_copath_pcs.spthy`            | Copath-resolution UpdatePath (final model). L3 verified in 4,336 steps.                                 | `054de69086fd`           |

The `stage1c`, `stage4_p1` and `stage6_v1` runs are ablation controls: the falsifications they produce are not attacks on MLS itself, but artefacts of the deliberately weakened models used to isolate the modelling assumption under study.

## Section-by-section correspondence

Section 6 of the paper describes the same nine stages in prose. The one-to-one correspondence is:

* Section 6.A (Feasibility baseline) → `stage1_private_kdf.spthy`.
* Section 6.B (Public-KDF ablation) → `stage1c_public_kdf_control.spthy`.
* Section 6.C (Forward secrecy under private KDF) → `stage2_private_fs.spthy`.
* Section 6.D (Post-compromise security under private KDF) → `stage3_private_pcs.spthy`.
* Section 6.E (Missing-AS diagnostic) → `stage4_p1_public_unauth_kp.spthy`.
* Section 6.F (Authenticated KeyPackages) → `stage4_p2_public_valid_kp.spthy`.
* Section 6.G (Forward secrecy under the public KDF) → `stage5_public_fs.spthy`.
* Section 6.H (Simplified UpdatePath ablation) → `stage6_v1_simplified_pcs.spthy`.
* Section 6.I (Copath-resolution UpdatePath, final model) → `stage7_v2_copath_pcs.spthy`.

## Replaying the stages

The stage-replay session used to produce the verdicts under `results/stage_headline_measurement_v2/` invoked each `.spthy` in turn with a single `--prove` and recorded the verdict per stage together with `/usr/bin/time -v`. The CSV `results/stage_headline_measurement_v2/stage_headline_results.csv` reports one row per stage with the observed verdict, proof-step count, wall time, peak resident set size, source-saturation depth, well-formedness status, exit code, and the SHA-256 of the theory file that was actually consumed. `postflight_integrity.txt` in the same directory records that the Tamarin executable and the final-model file were unchanged before and after the whole session, with no dirty-working-tree marker and zero mismatches.

Observed verdicts against expectation, as recorded in the CSV:

| Stage       | Headline lemma                    | Expected  | Observed  | Proof steps |
|-------------|-----------------------------------|-----------|-----------|------------:|
| stage1      | `L1_baseline_secrecy`             | verified  | verified  |           3 |
| stage1c     | `L1_baseline_secrecy`             | falsified | falsified |          10 |
| stage2      | `L2_forward_secrecy`              | verified  | verified  |          18 |
| stage3      | `L3_post_compromise_security`     | verified  | verified  |          18 |
| stage4_p1   | `L1_baseline_secrecy`             | falsified | falsified |          16 |
| stage4_p2   | `L1_baseline_secrecy`             | verified  | verified  |         244 |
| stage5      | `L2_forward_secrecy`              | verified  | verified  |       1,686 |
| stage6_v1   | `L3_post_compromise_security`     | falsified | falsified |          17 |
| stage7_v2   | `L3_post_compromise_security`     | verified  | verified  |       4,336 |

Every stage matched its expectation, with source saturation succeeding, well-formedness reported as successful, no warnings, and exit code zero.

## Note on `stage3` wall time

The `stage_headline_results.csv` row for `stage3` records a negative wall time (`-2.41` s), inherited from a WSL host clock synchronisation event during the run rather than from Tamarin itself. The proof completed successfully: verdict `verified`, `18` proof steps, source saturation depth `1`, well-formedness `successful`, warnings `clean`, exit code `0`, peak RSS `101,620` KiB, User time `2.64` s, System time `0.41` s.

To supply a usable performance figure, this artifact also ships a ten-repetition monotonic re-measurement under `results/stage3_monotonic_repeat10/`. That session uses `time.monotonic_ns()` in Python for elapsed time and keeps `/usr/bin/time -v` for peak resident set size. All ten repetitions verified `L3_post_compromise_security` in 18 proof steps with source saturation at depth 1, `successful` well-formedness, `clean` warnings and exit code zero; the mean monotonic wall time was 1.342 ± 0.074 s and the mean peak RSS was 105.9 MiB. `stage_headline_results_authoritative.csv` mirrors the original CSV and adds two extra columns that point at the monotonic mean for `stage3` while marking every other row as authoritative in place.
