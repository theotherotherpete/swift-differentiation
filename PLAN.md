# Plan: Drive Reverse/Forward Ratios Below 8

## Objective
Continuously drive composed-operator reverse-with-pullback ratios to < 8 while maintaining correctness. The workflow is a closed loop: pick a stable size, measure, find offenders, fix, re-measure.

## Phase 0: Baseline Setup
- Ensure a reproducible seed is used for every sweep.
- Use a fixed `--count` for comparison runs (e.g., 200) and fixed `--depth` for the composition space being studied.
- Keep `GeneratedTestsData.swift` stub small to avoid slow compiles.

## Phase 1: Find a Stable Size (Avoid Overhead Dominance)
Goal: Identify a size where ratios stabilize (work-dominated) without runaway runtime.

Steps:
1. Pick a seed (record it).
2. Run size sweep:
   - 256, 512, 1024, 2048 (extend if needed).
3. For each size, collect CSV output.
4. Extract metrics:
   - Median forward time
   - Median reverse time
   - Median ratio, p90, p99
5. Choose the smallest size where median ratio and p90 ratio stabilize across sizes.

Exit criteria:
- Size chosen and recorded as default for ongoing runs.

## Phase 2: Identify Offenders
Goal: Find composed operator combinations with ratio > 8.

Steps:
1. Run benchmarks at chosen size:
   - `swift run Benchmarks --seed <seed> --count <count> --depth <depth> --size <size> -v`
2. Parse CSV and filter rows where `ratio > 8`.
3. Group by snippet pattern (normalize constants and variable names).
4. Rank clusters by:
   - Max ratio
   - Median ratio
   - Frequency

Exit criteria:
- Top offender clusters identified and ranked.

## Phase 3: Diagnose Root Causes
Goal: Determine why reverse dominates for top offenders.

Checklist per offender cluster:
- Excess allocations in pullback (arrays, dictionaries, intermediate buffers)
- Non-inlined closures or higher-order function overhead
- Tape size growth (captures, large intermediates)
- Non-fused map/reduce/zip pipelines
- Update operations expanding tangent storage

Exit criteria:
- Root cause hypotheses documented for each top cluster.

## Phase 4: Apply Fixes
Goal: Implement targeted improvements to reduce reverse overhead.

Common fix strategies:
- Fuse `map` + `reduce` into a single loop
- Specialize common compositions (e.g., zip+map+reduce)
- Preallocate tangent vectors for update ops
- Avoid unnecessary captures in pullbacks
- Inline small helper functions

Exit criteria:
- Patch implemented for each prioritized cluster.
- Checkpoint commit created once each offending combination (or cluster) is brought below a ratio of 8.

## Phase 5: Validate and Iterate
Goal: Confirm ratios improve without regressions.

Steps:
1. Re-run with same seed/size/depth.
2. Compare offender ratios before/after.
3. Confirm no new high-ratio regressions.
4. Record learnings and ADRs as needed (timestamped entries in `LEARNINGS.md`).
5. Update `PROGRESS.md` with a timestamped entry for each fix.

Exit criteria:
- Offender ratios reduced or eliminated (< 8).

## Continuous Operation
- Repeat Phases 2–5 weekly or after major changes.
- Maintain a rolling record of:
  - Baseline size
  - Worst ratios
  - Fixes applied
  - Improvements achieved
  - Decisions/learnings (append to `LEARNINGS.md` with timestamps)
  - Progress snapshots (append to `PROGRESS.md` with timestamps)

## Outputs
- CSV results from each run
- `LEARNINGS.md` updates for persistent insights
- `PROGRESS.md` updates for fix-by-fix status tracking
- ADRs in `./adr` for decisions that affect architecture or methodology
