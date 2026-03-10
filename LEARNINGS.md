# Learnings

## 2026-02-25 05:39:19
- Large generated Swift files can make SwiftPM appear stuck at "Write sources"; keeping the checked-in `GeneratedTestsData.swift` small prevents long source-scans and compiles.
- Generated tests must embed metadata (seed/size/count/depth) to avoid accidentally reusing stale compiled tests.
- Benchmarking must avoid dead-code elimination; use a result sink and ensure generated expressions reference inputs.
- Random generation should be type-aware; otherwise depth/feature coverage can silently regress (e.g., fallback generator capped at depth 3).

## 2026-02-25 05:39:19
- Added `TEST_CREATION_CONTEXT.md` as a durable summary of the benchmark/codegen work and decisions to date.
- Introduced `PROGRESS.md` for per-fix status tracking; Plan now calls for timestamped updates in both learnings and progress logs.

## 2026-02-25 16:12:20
- Enforcing operator coverage requires both baseline tests and explicit coverage tests in generated compositions; otherwise some operators (e.g., `atan2`, `optional.map`, updates) may never appear in a run.
- Plain `atan2` is not differentiable by default; a custom `@derivative` is needed for generated tests and baseline usage.
- `for` loops are differentiable only when indexing uses `withoutDerivative(at:)`; simple `for v in values` can fail in AD contexts.
- Regenerating emitted Swift before benchmarks avoids stale `GeneratedTestsData.swift` mismatches when generator logic changes.

## 2026-02-25 20:25:33
- Single-scalar baselines are overhead-dominated; adding batched scalar baselines (map/reduce over arrays) provides a more reliable per-op proxy.
- Multicore execution is better treated as an optional throughput mode; single-threaded runs are the reference for stable ratio comparisons.

## 2026-03-03 00:32:00
- `array + unsafeBufferSum` is a read-only full-array reduction, while `array + update` is a single-element mutation plus reduction; they exercise different operator families and reverse-mode costs.
- Implementing an unsafe-pointer variant of `array + update` would require a bespoke API and custom VJP to model mutation semantics; `withUnsafeBufferPointer` alone is insufficient.
