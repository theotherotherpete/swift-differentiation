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
- `Array.update(at:with:)`
- `Dictionary.update(at:with:)`
- `Dictionary` subscript getter derivative
- `ContiguousArray` `update`, `subscript`, and `init(repeating:count:)`
- `InlineArray` `read`, `update`, `+`, `-` (Swift 6.2+, macOS/iOS 26 only)
- `runWithoutDerivative` (as a control / nonvarying baseline)

Generate ordered combinations containing up to **`--depth` operators/constructs** (default 3) working together (e.g. `map` + `*` + `zip`, or `for` + `if` + `+`). Order matters (`if + map` is distinct from `map + if`). `--depth N` creates test cases using between 1 and `N` nested operators and errors if `N < 1`.

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
  `test_number,ratio,forward_seconds,reverse_seconds,combination_code_snippet`
- Sort rows in ascending order by `ratio`.
- CSV filename format: `<year>_<month>_<day>_<time>_<hex-seed>.csv`.
- Emit the generated Swift source for that run as:
  `<yyyy_MM_dd_HHmmss>_<hex-seed>.swift`, stored alongside the CSV.
- Include baseline ratios for each fundamental differentiable operator by itself on every run.
- Baseline operator inputs must be randomized (seeded) to allow exact replay.
- Provide summary statistics: min, max, median, p90, p99.
- Render a histogram (bucketed, e.g. 20–40 bins) from the sorted ratios.
- Always display a progress bar showing completed tests vs total.
- Provide verbose debug output with `-v` (seed, count, size, output paths, baseline count, timing phases).

## Command-line Interface
- Emit generated tests:
  `swift run Benchmarks --emit <swift-path> --seed <64-hex> --count 1000`
- Benchmark generated tests:
  `swift run Benchmarks --seed <64-hex> --count 1000 --out <csv-path>`
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
