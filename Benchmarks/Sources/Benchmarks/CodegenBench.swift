import Differentiation
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum CodegenBench {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if !args.contains("--codegen")
            && !args.contains("--seed")
            && !args.contains("--count")
            && !args.contains("--size")
            && !args.contains("--depth")
            && !args.contains("--out")
            && !args.contains("--emit")
            && !args.contains("-v")
            && !args.contains("--verbose") {
            return false
        }

        var seedHex: String?
        var count: Int = 1000
        var size: Int = 4096
        var depth: Int = 3
        var outPath: String?
        var emitPath: String?
        let verbose = args.contains("-v") || args.contains("--verbose")

        func consumeValue(_ args: [String], _ index: Int) -> (value: String?, next: Int) {
            let next = index + 1
            guard next < args.count else { return (nil, index + 1) }
            let candidate = args[next]
            if candidate.hasPrefix("--") { return (nil, index + 1) }
            return (candidate, index + 2)
        }

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--seed":
                let consumed = consumeValue(args, i)
                seedHex = consumed.value
                i = consumed.next
            case "--count":
                let consumed = consumeValue(args, i)
                if let value = consumed.value, let v = Int(value) { count = v }
                i = consumed.next
            case "--size":
                let consumed = consumeValue(args, i)
                if let value = consumed.value, let v = Int(value) { size = v }
                i = consumed.next
            case "--depth":
                let consumed = consumeValue(args, i)
                if let value = consumed.value, let v = Int(value) { depth = v }
                i = consumed.next
            case "--out":
                let consumed = consumeValue(args, i)
                outPath = consumed.value
                i = consumed.next
            case "--emit":
                let consumed = consumeValue(args, i)
                emitPath = consumed.value
                i = consumed.next
            default:
                i += 1
            }
        }

        if depth < 1 {
            StdErr.write("invalid --depth (must be >= 1)")
            exit(1)
        }

        let seed: Seed
        if let seedHex {
            guard let parsed = Seed(hex: seedHex) else {
                StdErr.write("invalid --seed (expected 64 hex chars)")
                exit(1)
            }
            seed = parsed
        }
        else {
            seed = Seed.random()
        }
        let actualSeedHex = seed.hex
        let dateStamp = DateStamp.now()
        let outputPath = outPath ?? "\(dateStamp)_\(actualSeedHex).csv"
        let outputDir = URL(fileURLWithPath: outputPath).deletingLastPathComponent().path
        let outputDirPath = outputDir.isEmpty ? "." : outputDir
        let defaultEmit = "\(dateStamp)_\(actualSeedHex).swift"
        let emittedPath = emitPath ?? URL(fileURLWithPath: outputDirPath).appendingPathComponent(defaultEmit).path

        if verbose {
            let baselineCount = baselineTests(seed: seed, size: size).count
            print("codegen: seed=\(actualSeedHex) count=\(count) size=\(size) out=\(outputPath) emit=\(emittedPath) baseline=\(baselineCount)")
        }

        if args.contains("--emit") {
            let generator = SwiftSourceGenerator(seed: seed, size: size, depth: depth)
            let source = generator.emitSource(count: count)
            let emittedName = emittedPath
            do {
                try FileManager.default.createDirectory(atPath: outputDirPath, withIntermediateDirectories: true)
                try source.write(to: URL(fileURLWithPath: emittedName), atomically: true, encoding: .utf8)
                let projectPath = GeneratedTestsPath.project
                try source.write(to: URL(fileURLWithPath: projectPath), atomically: true, encoding: .utf8)
            }
            catch {
                StdErr.write("failed to write generated swift file: \(error)")
                exit(1)
            }
            if verbose {
                print("wrote generated tests to \(emittedName)")
                print("updated \(GeneratedTestsPath.project)")
            }
            return true
        }

        let tests: [GeneratedTestCase]
        let baseline = baselineTests(seed: seed, size: size)
        if generatedTestsIsAvailable {
            let seedMatches = (generatedTestsSeed == actualSeedHex)
            let depthMatches = (generatedTestsDepth == nil || generatedTestsDepth == depth)
            let sizeMatches = (generatedTestsSize == nil || generatedTestsSize == size)
            let countMatches = (generatedTestsCount == nil || generatedTestsCount == count)
            let metadataMatches = seedMatches && depthMatches && sizeMatches && countMatches
            if !metadataMatches {
                if verbose {
                    print("generated tests metadata mismatch; regenerating for seed \(actualSeedHex)")
                }
                let sourceGenerator = SwiftSourceGenerator(seed: seed, size: size, depth: depth)
                let source = sourceGenerator.emitSource(count: count)
                do {
                    try FileManager.default.createDirectory(atPath: outputDirPath, withIntermediateDirectories: true)
                    try source.write(to: URL(fileURLWithPath: emittedPath), atomically: true, encoding: .utf8)
                    try source.write(to: URL(fileURLWithPath: GeneratedTestsPath.project), atomically: true, encoding: .utf8)
                }
                catch {
                    StdErr.write("failed to write generated swift file: \(error)")
                    exit(1)
                }
                // Use in-memory generated tests for this run; compiled tests will match on next run.
                let testGenerator = TestGenerator(seed: seed, size: size, depth: depth)
                tests = baseline + (0 ..< count).map { index in testGenerator.makeTest(index: index) }
            }
            else {
                tests = baseline + generatedTests
            }
        }
        else {
            let generator = TestGenerator(seed: seed, size: size, depth: depth)
            tests = baseline + (0 ..< count).map { index in generator.makeTest(index: index) }
        }

        if verbose { print("benchmark: start") }
        let total = tests.count
        Progress.render(current: 0, total: total)
        var results: [ResultRow] = []
        results.reserveCapacity(tests.count)
        for (i, test) in tests.enumerated() {
            test.forward()
            test.reverse()
            let forwardTime = Timing.measure(iterations: test.iterations) {
                test.forward()
            }
            let reverseTime = Timing.measure(iterations: test.iterations) {
                test.reverse()
            }
            let ratio = reverseTime / max(forwardTime, 1e-12)
            results.append(ResultRow(index: test.index, ratio: ratio, forward: forwardTime, reverse: reverseTime, snippet: test.snippet))
            Progress.render(current: i + 1, total: total)
        }
        Progress.finish(total: total)
        if verbose { print("benchmark: done") }

        results.sort { a, b in a.ratio < b.ratio }

        let csv = CSVRenderer.render(rows: results)
        do {
            try csv.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        }
        catch {
            StdErr.write("failed to write CSV: \(error)")
            exit(1)
        }

        if verbose {
            print("wrote \(results.count) rows to \(outputPath)")
        }
        return true
    }
}

// MARK: - Seed

struct Seed {
    let bytes: [UInt8]

    var hex: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    init?(hex: String) {
        guard hex.count == 64 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2)
            guard next <= hex.endIndex else { return nil }
            let pair = String(hex[i..<next])
            guard let b = UInt8(pair, radix: 16) else { return nil }
            bytes.append(b)
            i = next
        }
        self.bytes = bytes
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func random() -> Seed {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        for _ in 0 ..< 32 {
            bytes.append(UInt8.random(in: 0 ... 255))
        }
        return Seed(bytes: bytes)
    }
}

// MARK: - DateStamp

struct DateStamp {
    static func now() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy_MM_dd_HHmmss"
        return formatter.string(from: Date())
    }
}

// MARK: - Timing

enum Timing {
    static func measure(iterations: Int, _ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0 ..< iterations { body() }
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsedNs = Double(end - start)
        return elapsedNs / 1_000_000_000.0
    }
}

// MARK: - Baseline tests

@differentiable(reverse)
private func baselineAdd(_ x: Float) -> Float { x + 1.0 }

@differentiable(reverse)
private func baselineSub(_ x: Float) -> Float { x - 1.0 }

@differentiable(reverse)
private func baselineMul(_ x: Float) -> Float { x * 1.5 }

@differentiable(reverse)
private func baselineDiv(_ x: Float) -> Float { x / 1.5 }

@differentiable(reverse)
private func baselineAbs(_ x: Float) -> Float { abs(x) }

@differentiable(reverse)
private func baselineMin(_ x: Float) -> Float { min(x, 0.25) }

@differentiable(reverse)
private func baselineMax(_ x: Float) -> Float { max(x, -0.25) }

@differentiable(reverse)
private func baselineMapReduce(_ values: [Float]) -> Float {
    values.differentiableMap { $0 * 1.1 }.differentiableReduce(Float.zero, +)
}

@differentiable(reverse)
private func baselineZipMapReduce(_ a: [Float], _ b: [Float]) -> Float {
    differentiableZip(a, b).differentiableMap { $0 + $1 }.differentiableReduce(Float.zero, +)
}

private func baselineTests(seed: Seed, size: Int) -> [GeneratedTestCase] {
    var rng = Xoroshiro.fromSeed(seed)
    let count = max(1, size)
    let x: Float = Float(rng.nextDouble(in: -2.0, 2.0))
    let values: [Float] = (0 ..< count).map { _ in Float(rng.nextDouble(in: -2.0, 2.0)) }
    let a: [Float] = (0 ..< count).map { _ in Float(rng.nextDouble(in: -2.0, 2.0)) }
    let b: [Float] = (0 ..< count).map { _ in Float(rng.nextDouble(in: -2.0, 2.0)) }
    return [
        GeneratedTestCase(
            index: -1,
            snippet: "baseline:+",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineAdd(x) },
            reverse: { _ = pullback(at: x, of: baselineAdd)(1) }
        ),
        GeneratedTestCase(
            index: -2,
            snippet: "baseline:-",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineSub(x) },
            reverse: { _ = pullback(at: x, of: baselineSub)(1) }
        ),
        GeneratedTestCase(
            index: -3,
            snippet: "baseline:*",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineMul(x) },
            reverse: { _ = pullback(at: x, of: baselineMul)(1) }
        ),
        GeneratedTestCase(
            index: -4,
            snippet: "baseline:/",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineDiv(x) },
            reverse: { _ = pullback(at: x, of: baselineDiv)(1) }
        ),
        GeneratedTestCase(
            index: -5,
            snippet: "baseline:abs",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineAbs(x) },
            reverse: { _ = pullback(at: x, of: baselineAbs)(1) }
        ),
        GeneratedTestCase(
            index: -6,
            snippet: "baseline:min",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineMin(x) },
            reverse: { _ = pullback(at: x, of: baselineMin)(1) }
        ),
        GeneratedTestCase(
            index: -7,
            snippet: "baseline:max",
            iterations: 400,
            input: .scalarFloat(x),
            forward: { _ = baselineMax(x) },
            reverse: { _ = pullback(at: x, of: baselineMax)(1) }
        ),
        GeneratedTestCase(
            index: -8,
            snippet: "baseline:map+reduce",
            iterations: 200,
            input: .singleFloat(values),
            forward: { _ = baselineMapReduce(values) },
            reverse: { _ = pullback(at: values, of: baselineMapReduce)(1) }
        ),
        GeneratedTestCase(
            index: -9,
            snippet: "baseline:zip+map+reduce",
            iterations: 200,
            input: .pairFloat(a, b),
            forward: { _ = baselineZipMapReduce(a, b) },
            reverse: { _ = pullback(at: a, b, of: baselineZipMapReduce)(1) }
        ),
    ]
}

// MARK: - Test generation

final class TestGenerator {
    private var rng: Xoroshiro
    private let size: Int
    private let maxDepth: Int

    init(seed: Seed, size: Int, depth: Int) {
        var words: [UInt64] = []
        words.reserveCapacity(4)
        var acc: UInt64 = 0
        var shift: UInt64 = 0
        for (i, b) in seed.bytes.enumerated() {
            acc |= UInt64(b) << shift
            shift += 8
            if (i + 1) % 8 == 0 {
                words.append(acc)
                acc = 0
                shift = 0
            }
        }
        if words.count < 2 { words.append(0x9e3779b97f4a7c15) }
        self.rng = Xoroshiro(state0: words[0], state1: words[1])
        self.size = max(1, size)
        self.maxDepth = max(1, depth)
    }

    func makeTest(index: Int) -> GeneratedTestCase {
        let choice = Int(rng.next() % 6)
        switch choice {
        case 0:
            return makeMapMultiply(index: index)
        case 1:
            return makeZipMapAdd(index: index)
        case 2:
            return makeForIfDivide(index: index)
        case 3:
            return makeMinIf(index: index)
        case 4:
            return makeMaxIf(index: index)
        default:
            return makeAbsScale(index: index)
        }
    }

    private func randomDepth() -> Int {
        if maxDepth <= 1 { return 1 }
        return 1 + Int(rng.next() % UInt64(maxDepth))
    }

    private func randomArray(count: Int) -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            let v = Float(rng.nextDouble(in: -10.0, 10.0))
            result.append(v)
        }
        return result
    }

    private func makeInputArray() -> [Float] {
        return randomArray(count: size)
    }

    private func randomDoubleArray(count: Int) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            let v = rng.nextDouble(in: -10.0, 10.0)
            result.append(v)
        }
        return result
    }

    private func makeInputDoubleArray() -> [Double] {
        return randomDoubleArray(count: size)
    }

    private func makeMapMultiply(index: Int) -> GeneratedTestCase {
        let snippet = "map * reduce"
        let input = makeInputArray()
        return GeneratedTestCase(
            index: index,
            snippet: snippet,
            iterations: 200,
            input: .singleFloat(input),
            forward: {
                _ = mapMultiply(values: input)
            },
            reverse: {
                _ = pullback(at: input, of: mapMultiply)(1)
            }
        )
    }

    private func makeZipMapAdd(index: Int) -> GeneratedTestCase {
        let snippet = "zip + map + reduce"
        let a = makeInputArray()
        let b = makeInputArray()
        return GeneratedTestCase(
            index: index,
            snippet: snippet,
            iterations: 200,
            input: .pairFloat(a, b),
            forward: {
                _ = zipMapAdd(a: a, b: b)
            },
            reverse: {
                _ = pullback(at: a, b, of: zipMapAdd)(1)
            }
        )
    }

    private func makeForIfDivide(index: Int) -> GeneratedTestCase {
        let snippet = "for + if + /"
        let input = makeInputArray()
        return GeneratedTestCase(
            index: index,
            snippet: snippet,
            iterations: 200,
            input: .singleFloat(input),
            forward: {
                _ = forIfDivide(values: input)
            },
            reverse: {
                _ = pullback(at: input, of: forIfDivide)(1)
            }
        )
    }

    private func makeMinIf(index: Int) -> GeneratedTestCase {
        let snippet = "min + if"
        let input = makeInputArray()
        return GeneratedTestCase(
            index: index,
            snippet: snippet,
            iterations: 200,
            input: .singleFloat(input),
            forward: {
                _ = minIf(values: input)
            },
            reverse: {
                _ = pullback(at: input, of: minIf)(1)
            }
        )
    }

    private func makeMaxIf(index: Int) -> GeneratedTestCase {
        let snippet = "max + if"
        let input = makeInputArray()
        return GeneratedTestCase(
            index: index,
            snippet: snippet,
            iterations: 200,
            input: .singleFloat(input),
            forward: {
                _ = maxIf(values: input)
            },
            reverse: {
                _ = pullback(at: input, of: maxIf)(1)
            }
        )
    }

    private func makeAbsScale(index: Int) -> GeneratedTestCase {
        let snippet = "abs + map + *"
        let input = makeInputArray()
        return GeneratedTestCase(
            index: index,
            snippet: snippet,
            iterations: 200,
            input: .singleFloat(input),
            forward: {
                _ = absScale(values: input)
            },
            reverse: {
                _ = pullback(at: input, of: absScale)(1)
            }
        )
    }

    // Note: no optional or atan2 variants in fallback; those are covered by emitted code.
}

// MARK: - Generated test functions

@differentiable(reverse)
private func mapMultiply(values: [Float]) -> Float {
    values.differentiableMap { $0 * 1.1 }.differentiableReduce(0, +)
}

@differentiable(reverse)
private func zipMapAdd(a: [Float], b: [Float]) -> Float {
    differentiableZip(a, b).differentiableMap { $0 + $1 }.differentiableReduce(0, +)
}

@differentiable(reverse)
private func forIfDivide(values: [Float]) -> Float {
    values.differentiableMap { v in
        v > 0 ? (v / 2.0) : (v / -3.0)
    }.differentiableReduce(0, +)
}

@differentiable(reverse)
private func minIf(values: [Float]) -> Float {
    let m = values.differentiableReduce(Float.greatestFiniteMagnitude) { min($0, $1) }
    return m < 0 ? (m * 1.5) : (m + 0.5)
}

@differentiable(reverse)
private func maxIf(values: [Float]) -> Float {
    let m = values.differentiableReduce(-Float.greatestFiniteMagnitude) { max($0, $1) }
    return m > 0 ? (m * 0.8) : (m - 0.4)
}

@differentiable(reverse)
private func absScale(values: [Float]) -> Float {
    values.differentiableMap { abs($0) * 0.7 }.differentiableReduce(0, +)
}

// MARK: - RNG

struct Xoroshiro {
    private var s0: UInt64
    private var s1: UInt64

    init(state0: UInt64, state1: UInt64) {
        self.s0 = state0
        self.s1 = state1
    }

    mutating func next() -> UInt64 {
        let result = s0 &+ s1
        let t = s1 ^ s0
        s0 = (s0 << 55) | (s0 >> (64 - 55))
        s0 ^= t ^ (t << 14)
        s1 = (t << 36) | (t >> (64 - 36))
        return result
    }

    mutating func nextDouble(in min: Double, _ max: Double) -> Double {
        let v = Double(next() >> 11) / Double(1 << 53)
        return min + (max - min) * v
    }
}

extension Xoroshiro {
    static func fromSeed(_ seed: Seed) -> Xoroshiro {
        var words: [UInt64] = []
        words.reserveCapacity(4)
        var acc: UInt64 = 0
        var shift: UInt64 = 0
        for (i, b) in seed.bytes.enumerated() {
            acc |= UInt64(b) << shift
            shift += 8
            if (i + 1) % 8 == 0 {
                words.append(acc)
                acc = 0
                shift = 0
            }
        }
        if words.count < 2 { words.append(0x9e3779b97f4a7c15) }
        return Xoroshiro(state0: words[0], state1: words[1])
    }
}

// MARK: - CSV

struct ResultRow {
    let index: Int
    let ratio: Double
    let forward: Double
    let reverse: Double
    let snippet: String
}

enum CSVRenderer {
    static func render(rows: [ResultRow]) -> String {
        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append("test,ratio,forward_seconds,reverse_seconds,code")
        for row in rows {
            let code = escape(row.snippet)
            lines.append("\(row.index),\(row.ratio),\(row.forward),\(row.reverse),\(code)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

enum StdErr {
    static func write(_ message: String) {
        let data = (message + "\n").data(using: .utf8) ?? Data()
        FileHandle.standardError.write(data)
    }
}

enum Progress {
    static func render(current: Int, total: Int) {
        let width = 30
        let safeTotal = max(1, total)
        let ratio = Double(current) / Double(safeTotal)
        let filled = min(width, Int(Double(width) * ratio))
        let bar = String(repeating: "#", count: filled) + String(repeating: "-", count: width - filled)
        let line = "\r[\(bar)] \(current)/\(total)"
        write(line)
    }

    static func finish(total: Int) {
        render(current: total, total: total)
        write("\n")
    }

    private static func write(_ message: String) {
        let data = message.data(using: .utf8) ?? Data()
        FileHandle.standardOutput.write(data)
    }
}

// MARK: - Generated source

enum GeneratedTestsPath {
    static let project = "/root/swift-differentiation/Benchmarks/Sources/Benchmarks/GeneratedTestsData.swift"
}

final class SwiftSourceGenerator {
    private var rng: Xoroshiro
    private let seedHex: String
    private let size: Int
    private let maxDepth: Int

    init(seed: Seed, size: Int, depth: Int) {
        self.seedHex = seed.hex
        var words: [UInt64] = []
        words.reserveCapacity(4)
        var acc: UInt64 = 0
        var shift: UInt64 = 0
        for (i, b) in seed.bytes.enumerated() {
            acc |= UInt64(b) << shift
            shift += 8
            if (i + 1) % 8 == 0 {
                words.append(acc)
                acc = 0
                shift = 0
            }
        }
        if words.count < 2 { words.append(0x9e3779b97f4a7c15) }
        self.rng = Xoroshiro(state0: words[0], state1: words[1])
        self.size = max(1, size)
        self.maxDepth = max(1, depth)
    }

    func emitSource(count: Int) -> String {
        var lines: [String] = []
        lines.append("import Differentiation")
        lines.append("import Foundation")
        lines.append("")
        lines.append("let generatedTestsIsAvailable: Bool = true")
        lines.append("let generatedTestsSeed: String? = \"\(seedHex)\"")
        lines.append("let generatedTestsDepth: Int? = \(maxDepth)")
        lines.append("let generatedTestsSize: Int? = \(size)")
        lines.append("let generatedTestsCount: Int? = \(count)")
        lines.append("")

        var testEntries: [String] = []
        testEntries.reserveCapacity(count)

        for index in 0 ..< count {
            emitRandomTest(index: index, lines: &lines, entries: &testEntries)
        }

        lines.append("let generatedTests: [GeneratedTestCase] = [")
        lines.append(contentsOf: testEntries.map { "    \($0)," })
        lines.append("]")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func emitRandomTest(index: Int, lines: inout [String], entries: inout [String]) {
        let kinds: [Int]
        if maxDepth < 2 {
            kinds = [0, 1]
        }
        else {
            kinds = [0, 1, 2]
        }
        let kind = kinds[Int(rng.next() % UInt64(kinds.count))]
        switch kind {
        case 0:
            emitScalarTest(index: index, lines: &lines, entries: &entries)
        case 1:
            emitArrayTest(index: index, lines: &lines, entries: &entries)
        default:
            emitPairArrayTest(index: index, lines: &lines, entries: &entries)
        }
    }

    private func emitScalarTest(index: Int, lines: inout [String], entries: inout [String]) {
        let input = emitFloatScalar(name: "x\(index)", lines: &lines)
        let fn = "testFunc\(index)"
        let node = randomScalarNode(vars: [input], ops: randomOpsTarget())
        let emitted = emitScalarNode(node)
        lines.append("@differentiable(reverse)")
        lines.append("private func \(fn)(x: Float) -> Float {")
        for line in emitted.lines {
            lines.append("    \(line)")
        }
        lines.append("    return \(emitted.result)")
        lines.append("}")
        entries.append("GeneratedTestCase(index: \(index), snippet: \"\(describe(node))\", iterations: 200, input: .scalarFloat(\(input)), forward: { _ = \(fn)(x: \(input)) }, reverse: { _ = pullback(at: \(input), of: \(fn))(1) })")
        lines.append("")
    }

    private func emitArrayTest(index: Int, lines: inout [String], entries: inout [String]) {
        let input = emitFloatArray(name: "input\(index)", lines: &lines)
        let fn = "testFunc\(index)"
        let element = "v\(index)"
        let expr = randomArrayExprSingle(valuesName: "values", elementName: element, maxOps: randomOpsTarget())
        lines.append("@differentiable(reverse)")
        lines.append("private func \(fn)(values: [Float]) -> Float {")
        for line in expr.bodyLines {
            lines.append("    \(line)")
        }
        lines.append("}")
        entries.append("GeneratedTestCase(index: \(index), snippet: \"array + \(expr.snippet)\", iterations: 200, input: .singleFloat(\(input)), forward: { _ = \(fn)(values: \(input)) }, reverse: { _ = pullback(at: \(input), of: \(fn))(1) })")
        lines.append("")
    }

    private func emitPairArrayTest(index: Int, lines: inout [String], entries: inout [String]) {
        let a = emitFloatArray(name: "input\(index)A", lines: &lines)
        let b = emitFloatArray(name: "input\(index)B", lines: &lines)
        let fn = "testFunc\(index)"
        let va = "a\(index)"
        let vb = "b\(index)"
        let expr = randomArrayExprPair(aName: "a", bName: "b", va: va, vb: vb, maxOps: randomOpsTarget(minimum: 2))
        lines.append("@differentiable(reverse)")
        lines.append("private func \(fn)(a: [Float], b: [Float]) -> Float {")
        for line in expr.bodyLines {
            lines.append("    \(line)")
        }
        lines.append("}")
        entries.append("GeneratedTestCase(index: \(index), snippet: \"zip + map + \(expr.snippet)\", iterations: 200, input: .pairFloat(\(a), \(b)), forward: { _ = \(fn)(a: \(a), b: \(b)) }, reverse: { _ = pullback(at: \(a), \(b), of: \(fn))(1) })")
        lines.append("")
    }

    private indirect enum ScalarNode {
        case variable(String)
        case constant(String)
        case abs(ScalarNode)
        case min(ScalarNode, ScalarNode)
        case max(ScalarNode, ScalarNode)
        case op(String, ScalarNode, ScalarNode)
        case cond(ScalarNode, ScalarNode, ScalarNode)
    }

    private struct EmittedScalar {
        let lines: [String]
        let result: String
    }

    private func randomScalarNode(vars: [String], ops: Int) -> ScalarNode {
        if ops <= 0 {
            let pickVar = Int(rng.next() % 2) == 0 && !vars.isEmpty
            if pickVar {
                let expr = vars[Int(rng.next() % UInt64(vars.count))]
                return .variable(expr)
            }
            let value = String(format: "%.4f", rng.nextDouble(in: -2.0, 2.0))
            return .constant("Float(\(value))")
        }
        let choice = Int(rng.next() % 5)
        let remaining = ops - 1
        switch choice {
        case 0:
            let split = splitOps(remaining, parts: 2)
            let a = randomScalarNode(vars: vars, ops: split[0])
            let b = randomScalarNode(vars: vars, ops: split[1])
            let op = ["+", "-", "*", "/"][Int(rng.next() % 4)]
            return .op(op, a, b)
        case 1:
            let a = randomScalarNode(vars: vars, ops: remaining)
            return .abs(a)
        case 2:
            let split = splitOps(remaining, parts: 2)
            let a = randomScalarNode(vars: vars, ops: split[0])
            let b = randomScalarNode(vars: vars, ops: split[1])
            return .min(a, b)
        case 3:
            let split = splitOps(remaining, parts: 2)
            let a = randomScalarNode(vars: vars, ops: split[0])
            let b = randomScalarNode(vars: vars, ops: split[1])
            return .max(a, b)
        default:
            let split = splitOps(remaining, parts: 3)
            let cond = randomScalarNode(vars: vars, ops: split[0])
            let t = randomScalarNode(vars: vars, ops: split[1])
            let f = randomScalarNode(vars: vars, ops: split[2])
            return .cond(cond, t, f)
        }
    }

    private func describe(_ node: ScalarNode) -> String {
        switch node {
        case .variable:
            return "var"
        case .constant:
            return "const"
        case .abs(let n):
            return "abs + \(describe(n))"
        case .min(let a, let b):
            return "min + \(describe(a)) + \(describe(b))"
        case .max(let a, let b):
            return "max + \(describe(a)) + \(describe(b))"
        case .op(let op, let a, let b):
            return "\(describe(a)) \(op) \(describe(b))"
        case .cond(let c, let t, let f):
            return "if + \(describe(c)) + \(describe(t)) + \(describe(f))"
        }
    }

    private func emitScalarNode(_ node: ScalarNode, tempIndex: inout Int) -> EmittedScalar {
        switch node {
        case .variable(let v):
            return EmittedScalar(lines: [], result: v)
        case .constant(let c):
            return EmittedScalar(lines: [], result: c)
        case .abs(let n):
            let emitted = emitScalarNode(n, tempIndex: &tempIndex)
            let name = "t\(tempIndex)"
            tempIndex += 1
            return EmittedScalar(lines: emitted.lines + ["let \(name) = abs(\(emitted.result))"], result: name)
        case .min(let a, let b):
            let ea = emitScalarNode(a, tempIndex: &tempIndex)
            let eb = emitScalarNode(b, tempIndex: &tempIndex)
            let name = "t\(tempIndex)"
            tempIndex += 1
            return EmittedScalar(lines: ea.lines + eb.lines + ["let \(name) = min(\(ea.result), \(eb.result))"], result: name)
        case .max(let a, let b):
            let ea = emitScalarNode(a, tempIndex: &tempIndex)
            let eb = emitScalarNode(b, tempIndex: &tempIndex)
            let name = "t\(tempIndex)"
            tempIndex += 1
            return EmittedScalar(lines: ea.lines + eb.lines + ["let \(name) = max(\(ea.result), \(eb.result))"], result: name)
        case .op(let op, let a, let b):
            let ea = emitScalarNode(a, tempIndex: &tempIndex)
            let eb = emitScalarNode(b, tempIndex: &tempIndex)
            let name = "t\(tempIndex)"
            tempIndex += 1
            return EmittedScalar(lines: ea.lines + eb.lines + ["let \(name) = (\(ea.result) \(op) \(eb.result))"], result: name)
        case .cond(let c, let t, let f):
            let ec = emitScalarNode(c, tempIndex: &tempIndex)
            let et = emitScalarNode(t, tempIndex: &tempIndex)
            let ef = emitScalarNode(f, tempIndex: &tempIndex)
            let name = "t\(tempIndex)"
            tempIndex += 1
            let line = "let \(name) = (\(ec.result) > 0 ? \(et.result) : \(ef.result))"
            return EmittedScalar(lines: ec.lines + et.lines + ef.lines + [line], result: name)
        }
    }

    private func emitScalarNode(_ node: ScalarNode) -> EmittedScalar {
        var index = 0
        return emitScalarNode(node, tempIndex: &index)
    }

    private struct ArrayExpr {
        let snippet: String
        let bodyLines: [String]
    }

    private func indent(_ lines: [String], spaces: Int) -> [String] {
        let prefix = String(repeating: " ", count: spaces)
        return lines.map { "\(prefix)\($0)" }
    }

    private func randomArrayExprSingle(valuesName: String, elementName: String, maxOps: Int) -> ArrayExpr {
        let totalOps = max(1, maxOps)
        let useMapReduce: Bool
        if totalOps <= 1 {
            useMapReduce = false
        }
        else {
            useMapReduce = Int(rng.next() % 2) == 0
        }
        let arrayOps = useMapReduce ? 2 : 1
        let remaining = max(0, totalOps - arrayOps)
        let scalarOps = remaining == 0 ? 0 : Int(rng.next() % UInt64(remaining + 1))
        let scalarNode = randomScalarNode(vars: [elementName], ops: scalarOps)
        let emitted = emitScalarNode(scalarNode)
        if useMapReduce {
            return ArrayExpr(
                snippet: "map + reduce + \(describe(scalarNode))",
                bodyLines: ["return \(valuesName).differentiableMap { \(elementName) in"]
                    + indent(emitted.lines, spaces: 4)
                    + ["    return \(emitted.result)", "}.differentiableReduce(Float.zero, +)"]
            )
        }
        return ArrayExpr(
            snippet: "for + \(describe(scalarNode))",
            bodyLines: ["var sum: Float = 0",
                        "for i in 0 ..< withoutDerivative(at: \(valuesName).count) {",
                        "    let \(elementName) = \(valuesName)[i]"]
                + indent(emitted.lines, spaces: 4)
                + ["    sum += \(emitted.result)", "}", "return sum"]
        )
    }

    private func randomArrayExprPair(aName: String, bName: String, va: String, vb: String, maxOps: Int) -> ArrayExpr {
        let totalOps = maxOps
        let useMapReduce: Bool
        if totalOps <= 2 {
            useMapReduce = false
        }
        else {
            useMapReduce = Int(rng.next() % 2) == 0
        }
        let arrayOps = useMapReduce ? 3 : 2
        let remaining = max(0, totalOps - arrayOps)
        let scalarOps = remaining == 0 ? 0 : Int(rng.next() % UInt64(remaining + 1))
        let scalarNode = randomScalarNode(vars: [va, vb], ops: scalarOps)
        let emitted = emitScalarNode(scalarNode)
        if useMapReduce {
            return ArrayExpr(
                snippet: "zip + map + \(describe(scalarNode))",
                bodyLines: ["return differentiableZip(\(aName), \(bName)).differentiableMap { \(va), \(vb) in"]
                    + indent(emitted.lines, spaces: 4)
                    + ["    return \(emitted.result)", "}.differentiableReduce(Float.zero, +)"]
            )
        }
        return ArrayExpr(
            snippet: "zip + for + \(describe(scalarNode))",
            bodyLines: ["let n = withoutDerivative(at: min(\(aName).count, \(bName).count))",
                        "var sum: Float = 0",
                        "for i in 0 ..< n {",
                        "    let \(va) = \(aName)[i]",
                        "    let \(vb) = \(bName)[i]"]
                + indent(emitted.lines, spaces: 4)
                + ["    sum += \(emitted.result)", "}", "return sum"]
        )
    }

    private func emitFloatArray(name: String, lines: inout [String]) -> String {
        let count = size
        var values: [String] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            let v = Float(rng.nextDouble(in: -10.0, 10.0))
            values.append(String(format: "%.6f", v))
        }
        lines.append("private let \(name): [Float] = [\(values.joined(separator: ", "))]")
        return name
    }

    private func emitDoubleArray(name: String, lines: inout [String]) -> String {
        let count = size
        var values: [String] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            let v = rng.nextDouble(in: -10.0, 10.0)
            values.append(String(format: "%.6f", v))
        }
        lines.append("private let \(name): [Double] = [\(values.joined(separator: ", "))]")
        return name
    }

    private func emitFloatScalar(name: String, lines: inout [String]) -> String {
        let value = Float(rng.nextDouble(in: -10.0, 10.0))
        lines.append("private let \(name): Float = \(String(format: "%.6f", value))")
        return name
    }

    private func randomOpsTarget() -> Int {
        return randomOpsTarget(minimum: 1)
    }

    private func randomOpsTarget(minimum: Int) -> Int {
        let minOps = max(1, minimum)
        if maxDepth <= minOps { return maxDepth }
        return minOps + Int(rng.next() % UInt64(maxDepth - minOps + 1))
    }

    private func splitOps(_ total: Int, parts: Int) -> [Int] {
        guard parts > 1 else { return [max(0, total)] }
        if total == 0 { return Array(repeating: 0, count: parts) }
        var cuts: [Int] = []
        cuts.reserveCapacity(parts - 1)
        for _ in 0 ..< (parts - 1) {
            cuts.append(Int(rng.next() % UInt64(total + 1)))
        }
        cuts.sort()
        var result: [Int] = []
        result.reserveCapacity(parts)
        var last = 0
        for cut in cuts {
            result.append(cut - last)
            last = cut
        }
        result.append(total - last)
        return result
    }
}
