# ADR-001: Benchmark Codegen and Runtime Fallback

## Status
Accepted (2026-02-25)

## Context
We need reproducible, large-scale benchmarking of differentiable operator combinations. SwiftPM compilation can be slow or appear stalled when large generated source files are checked in. We also require deterministic regeneration when seed/size/count/depth changes, and we must avoid dead-code elimination during timing.

## Decision
- Generate Swift source for tests and write it to `GeneratedTestsData.swift` at runtime.
- Keep the checked-in `GeneratedTestsData.swift` as a small stub to avoid slow source discovery/compilation.
- Embed metadata (seed/size/count/depth) into generated source and regenerate when metadata mismatches.
- Use a sink (blackhole) to consume results and enforce variable usage in generated expressions to prevent DCE.
- Maintain a runtime fallback generator for use in the first run after regeneration.

## Consequences
- First run after regeneration uses in-memory tests; subsequent run uses compiled tests.
- Benchmark builds remain responsive because the checked-in generated file is minimal.
- Measurements are more stable and less likely to be optimized away.
