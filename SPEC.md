# Code Generation Benchmarking Spec

## Goal
Generate randomized Swift test functions that combine differentiable operators and control-flow constructs, then benchmark the ratio between:
- regular evaluation time of the function, and
- reverse-mode `pullback` evaluation time.

Produce ~1000 randomized tests, compute the ratio for each, then render a sorted histogram of results.

## Scope
Include combinations of the following operator/construct categories:
- `zip` (including `differentiableZipWith` and `ZipSequence` variants)
- `map` / `differentiableMap` (including `Optional.differentiableMap`)
- arithmetic operators `+`, `-`, `*`, `/`
- conditionals (`if` / ternary)
- `for` loops

Also include these differentiable operators/APIs from the repo where type-compatible:
- `min`, `max`, `abs`
- `atan2`
- `repeatElement`
- `withUnsafeBufferPointer`-based array accessor (`unsafeBufferSum`) with custom VJP
- `Array.update(at:with:)`
- `Dictionary.update(at:with:)`
- `Dictionary` subscript getter derivative
- `ContiguousArray` `update`, `subscript`, and `init(repeating:count:)`
- `InlineArray` `read`, `update`, `+`, `-` (Swift 6.2+, macOS/iOS 26 only)
- `runWithoutDerivative` (as a control / nonvarying baseline)

Coverage requirements:
- Every fundamental operator must be tested at least once as a standalone baseline (as with `min`, `max`, `abs`).
- Every operator in the palette must appear at least once in combination with at least one other operator in the same run.

Generate ordered combinations containing up to **`--depth` operators/constructs** (default 3) working together (e.g. `map` + `*` + `zip`, or `for` + `if` + `+`). Order matters (`if + map` is distinct from `map + if`). `--depth N` creates test cases using between 1 and `N` nested operators and errors if `N < 1`.

Focus on **obviously composable** operators and types:
- Scalar/array pipelines: `+ - * / abs min max`, `if`, `for`, `map/reduce`, `zip`
- Scalar-pair pipelines: `atan2` (composable with scalar ops and `zip`/`map`)
- Optional pipelines: `Optional.differentiableMap` with scalar ops inside the map body
- Update pipelines: `Array.update(at:with:)` and `Dictionary.update(at:with:)`, combined with scalar ops and conditionals to form the updated value
- Sequence reductions: `Sequence min/max` after `map` or `for` transforms

Defer or gate less-composable operators (platform/type-specific or niche) unless explicitly enabled:
- `InlineArray` operators (Swift 6.2+/new OS only)
- `ContiguousArray` differentiable view specifics
- `repeatElement`/`Repeated` subscript derivative

## Non-goals
- Proving mathematical correctness of derivatives beyond basic sanity checks.
- Exhaustive coverage of all operators in the repository.
- Optimizing the Swift compiler or runtime.

## Test Generation Strategy
1. **Operator palette**
   - Define a palette of operator/construct templates. Each template describes:
     - required input shapes/types (e.g. scalar `Float`, `[Float]`, tuples)
     - required differentiability constraints
     - how to generate random values
     - how to compose with other templates

2. **Random composition**
   - Randomly select an ordered combination of 1–`--depth` operators and compose them into a single function body.
   - Ensure type compatibility across composed templates by tracking a simple type state (scalar/vector/tuple).
   - Prefer small sizes for arrays (e.g. 4–32) to keep per-test runtime reasonable.
   - Operator counting is token-based: `map + reduce` counts as 2, `zip + map + reduce` counts as 3, `for` counts as 1, `if` counts as 1, and scalar ops (`+ - * / abs min max`) count as 1 each.

3. **Function form**
   - Generated function signature should be `@differentiable` and accept a single input `x` (scalar or array) or a tuple if required by `zip`.
   - The function must return a scalar (e.g. `Float`) to enable `pullback` of a scalar output.

4. **Examples of compositions** (illustrative)
   - `map` + `*`: map over array, multiply each element, then reduce to scalar.
   - `zip` + `+` + `map`: zip two arrays, map to sum pairs, then reduce to scalar.
   - `for` + `if` + `/`: loop over array, apply conditional, accumulate with division.
   - `min` + `if`: compute min, then branch based on it.
   - `repeatElement` + `map`: build repeated collection, then map.

## Benchmarking Strategy
1. **Timing targets**
   - Regular evaluation: `f(x)`
   - Reverse-mode: `pullback(at: x)(1)`

2. **Measurement approach**
   - Use wall-clock time with repeated iterations per test to reduce noise.
   - Warm up each function before timing.
   - Record `ratio = reverse_time / forward_time` per test.

3. **Iterations**
   - Choose a fixed iteration count (e.g. 100–1000) for each test, or adaptively scale based on forward time to hit a minimum total duration.

4. **Validation**
   - Optionally compare `pullback` result against finite differences for a small subset to sanity-check correctness.

## Output and Reporting
- Save per-test results to a CSV file, with each row as:
  `test_number,ratio,forward_seconds,reverse_seconds,combination_code_snippet,command_line`
- Sort rows in ascending order by `ratio`.
- CSV filename format: `<year>_<month>_<day>_<time>_<hex-seed>.csv`.
- Emit the generated Swift source for that run as:
  `<yyyy_MM_dd_HHmmss>_<hex-seed>.swift`, stored alongside the CSV.
- Include baseline ratios for each fundamental differentiable operator by itself on every run.
- Baseline operator inputs must be randomized (seeded) to allow exact replay.
- Add batched scalar baselines for each fundamental scalar operator (apply to arrays of size `--size` via `map`/`reduce`) to avoid overhead-dominated timing and provide a per-op proxy.
- Provide summary statistics: min, max, median, p90, p99.
- Render a histogram (bucketed, e.g. 20–40 bins) from the sorted ratios.
- Always display a progress bar showing completed tests vs total.
- Provide verbose debug output with `-v` (seed, count, size, output paths, baseline count, timing phases).

## Command-line Interface
- Emit generated tests:
  `swift run Benchmarks --emit <swift-path> --seed <64-hex> --count 1000`
- Benchmark generated tests:
  `swift run Benchmarks --seed <64-hex> --count 1000 --out <csv-path>`
- Build configuration (default: release):
  - If `--config` is omitted, the tool **requires** a release build and errors otherwise.
  - Validate build configuration explicitly:
    `swift run -c release Benchmarks --config release ...` (errors if the binary is not built in the requested config)
- Control array sizes:
  `swift run Benchmarks --size 4096`
- Control number of generated tests:
  `swift run Benchmarks --count 1000`
- Control max ordered operator combinations per test (order matters):
  `swift run Benchmarks --depth 3`
- After emitting, rebuild or re-run so the generated tests are compiled into the Benchmarks target.
- If `--seed` is not provided, generate one (64-character hex string) and report it in stdout.
- If `--out` is not provided, default to `<date>_<seed>.csv` using the filename format above.
- If `--emit` is provided without a path, default to `<date>_<seed>.swift` alongside the CSV output path.
- Verbose output:
  `swift run Benchmarks -v ...`

## Implementation Notes
- Use a deterministic RNG seed for reproducibility, provided as a 64-character hex string to enable exact run replay.
- Generate Swift source for all tests into a single file for compilation.
- Prefer batching multiple tests into a single executable run to avoid startup overhead.
- Gate InlineArray tests behind Swift 6.2+ and platform availability checks.
- Default array sizes should be large enough to measure steady-state performance (e.g., 4096).
- Baseline operator tests should use randomized, seed-driven inputs for deterministic comparisons.
- Progress output should update in-place to avoid excessive log noise.

## Open Questions
- Should benchmarks be run with `-O` only, or multiple optimization levels?
- Should tests be grouped by operator combinations in the report?
- Should vector sizes be fixed per test or randomized per run?
- Should dictionary-based operators be limited to small key sets for predictability?

## Learnings and ADRs
- Project learnings are tracked in `LEARNINGS.md`.
- Architectural decisions are recorded under `./adr` (e.g., `adr/adr-001-benchmark-codegen.md`).

## Future Work
- Add a size sweep mode to determine when benchmarks move from overhead-dominated to work-dominated. Run the same seed/count/depth across increasing sizes (e.g., 256, 512, 1024, 2048) and compare median forward time, median reverse time, and ratio stability to pick a default size.
