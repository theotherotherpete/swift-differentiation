# Test Creation Context

This document captures a reasonably detailed summary of the work and decisions across our conversation, focused on the Swift-differentiation benchmark/codegen effort. It is intended as a durable reference for why the benchmark harness exists, how it behaves, and what we changed along the way.

## High-level goal
- Build a Swift benchmark harness that generates randomized combinations of differentiable operators, measures forward (regular execution) vs reverse-with-pullback times, and outputs sorted CSV results.
- Use this to find combinations where reverse-mode is slow relative to forward-mode, and then iteratively reduce those ratios (target: ratios below 8 for composed operator combinations).

## Core design
- **True codegen:** Generate Swift test sources, compile them, and then benchmark those compiled tests. The generator emits Swift files for each run.
- **Operator combinations:** Generate random operator combinations of length 1..N (depth), in order (so `map` then `if` differs from `if` then `map`). The generator uses random combinations up to and including `--depth`.
- **Include key operators:** `zip`, `map`, `+`, `-`, `*`, `/`, conditionals, and `for` loops.
- **Add fundamental operators baseline:** Include standalone runs for each fundamental differentiable operator (with randomized inputs) in every run, so we always see “single-op” ratios.
- **Avoid DCE:** Add sinks and usage checks so generated results aren’t optimized away.

## CLI and outputs
- Command pattern:  
  `swift run Benchmarks --seed <64-hex> --count 1000 --out <csv>`  
  Output is **CSV** (not JSON).
- CSV format:  
  `<test number>,<regular:reverse-with-pullback ratio>,<combination code snippet>,<regular time>,<reverse time>`
- CSV sorting: Ascending by ratio.
- Seed handling:
  - If `--seed` provided, generator must use it.
  - If no seed provided, generate a random 64-hex seed.
  - If compiled tests seed mismatches requested seed, regenerate/recompile with the requested seed.
  - If no seed provided, generate and recompile with a new seed.
- Output file naming:
  - CSV: `<yyyy_MM_dd_HHmmss>_<seed>.csv`
  - Swift source: `<yyyy_MM_dd_HHmmss>_<seed>.swift`
  - Generated files stored next to CSV outputs.
- Parameters:
  - `--count` number of tests (default set)
  - `--size` number of elements per input (default set; later set to 4096 default)
  - `--depth` number of nested operator combos (1..N; error if N < 1)
  - `--verbose` (`-v`) emits debug info
  - Always show progress bar

## Behavioral decisions and options
- Codegen approach favored over pure runtime generation: generate Swift, compile, then benchmark to reflect real compiler/codegen costs and optimizations.
- Considered generating many files vs fewer:
  - Chose option 1: fewer Swift files with many tests in each (runtime dominates, compile time less critical).
  - Still save all generated Swift files alongside CSV outputs.
- Added `--size` to avoid overhead-dominated tests; default was 4096 and later adjusted by experimentation.
- Added progress indicator with verbose debug option to reduce “hang” ambiguity.
- Ensure reverse pass is measured properly and forward benchmark excludes pullback.

## Additional documentation added
- **SPEC.md** expanded throughout to cover:
  - CLI behavior and defaults
  - Seed rules
  - CSV format and naming
  - Generated Swift file naming
  - Progress bar and verbose output
  - Operator lists and composability scope
  - Learnings/ADR locations
  - Future work: size sweep and overhead vs real execution
- **AGENTS.md** created with formal role/goal: compiler + autodiff performance engineer, Swift/Tegra expert, focus on reverse-pass cost.
- **LEARNINGS.md** created for recorded learnings from runs.
- **ADR directory** created (`./adr`) with `adr-001-...` format.

## Implementation highlights (code)
- Central generator code lives in `Benchmarks/Sources/Benchmarks/CodegenBench.swift`.
- Generated test data file `GeneratedTestsData.swift` kept as a stub to reduce SwiftPM rebuild time.
- Added “sink” functions and `Blackhole` to prevent dead-code elimination:
  - `sink(_ value: Float)`, `sink(_ value: [Float])`, tuple tangent sinks, array tangent sinks, and dictionary sinks where needed.
- Ensured variable usage within generated expressions (`ensureVariable` helpers).
- Adjusted Optional and Dictionary update tests to stay differentiable:
  - Avoided `?? 0`; used `differentiableMap` and `!` where needed.
- Added `atan2f` helper to avoid enum case name collision.

## Operator coverage updates
- Base set: `map`, `zip`, `+`, `-`, `*`, `/`, conditionals, loops.
- Added composable operators (high-value and type-compatible with Float):
  - Optional mapping (`differentiableMap` path)
  - Array update
  - Dictionary update
  - `atan2`
  - `min` / `max` via `map + max/min` (force unwrap)
- Added handling in both generator and fallback/test generator.

## Issues encountered and fixes
- Depth handling bug: `--depth` stuck at 3. Fixed generator to respect `--depth`.
- CLI error: `--depth` not recognized due to subcommand routing; updated CLI structure.
- Seed mismatch warning: introduced explicit regen/recompile behavior.
- Swift compile errors:
  - Duplicate helper blocks (string vs scalar); fixed scoping separation.
  - `Swift.atan2` ambiguity; switched to `atan2f`.
  - Invalid `&+` usage for Float; fixed to standard `+=`.
  - Optional/dictionary tangent sink type mismatches fixed.
- Long build times: added progress bar and `-v` debugging.

## Current plan direction
- Use the benchmark suite to find compositions with ratios above 8, then fix reverse-pass overhead.
- Determine a “sweet spot” for `--size` so measurements reflect computation rather than overhead.
- Add plotting tools: graph ratio vs size of element array.
- Track findings in `LEARNINGS.md` and architecture decisions in `./adr`.

## Requested next steps (pending)
- Add a “size sweep” tool that runs multiple sizes, generates summary CSV, and plots ratio vs size (graph output).
- Start with `--depth 4` and `--count 100` for early runs (vibe-based defaults).

