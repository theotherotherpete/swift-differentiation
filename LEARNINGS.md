# Learnings

## 2026-02-25
- Large generated Swift files can make SwiftPM appear stuck at "Write sources"; keeping the checked-in `GeneratedTestsData.swift` small prevents long source-scans and compiles.
- Generated tests must embed metadata (seed/size/count/depth) to avoid accidentally reusing stale compiled tests.
- Benchmarking must avoid dead-code elimination; use a result sink and ensure generated expressions reference inputs.
- Random generation should be type-aware; otherwise depth/feature coverage can silently regress (e.g., fallback generator capped at depth 3).
