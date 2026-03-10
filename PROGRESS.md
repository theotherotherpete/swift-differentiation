# Progress

## 2026-02-25 05:39:19
- Current state: Benchmark harness and Swift codegen are in place; operator coverage expanded; seed/size/depth handling stabilized; progress/verbose output added; learnings and ADRs established. Next focus is size sweep graphing and driving high-ratio compositions below 8.

## 2026-02-25 17:41:38
- Phase 1 (size sweep, seed `4723550c332438a6c8aeb8c4408bcfca1fe3e9a832f952941973b70c1813e74d`) executed for sizes 256/512/1024 with `--count 100 --depth 4`. Size 2048 was started but aborted due to runtime.
- Sweep stats (median ratio / p90 / p99, median fwd/rev): 256 → 20.68 / 4085.30 / 7065.41, fwd 0.001687s rev 0.072088s; 512 → 19.04 / 8030.14 / 14057.99, fwd 0.000867s rev 0.039826s; 1024 → 15.12 / 16255.93 / 28042.12, fwd 0.001542s rev 0.076495s. Ratios are not fully stable yet; provisional working size is 1024 pending a full 2048 run or iteration scaling adjustments.
- Phase 2 (offender identification) done on size 1024 CSV. Offenders (ratio > 8) dominated by loop-based compositions: `baseline:for` (max 36054), `zip + for + var` (max 28042, n=7), `array + for + var` (max 16327, n=6), `zip + for + abs + var` (max 11549), plus several `dict + update ...` variants around ~50x.
