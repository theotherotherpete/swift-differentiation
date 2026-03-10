import CollectionsBenchmark
import Differentiation
import Foundation

private let benchmarkTitle = "baselineArraySum"

@differentiable(reverse)
private func arraySum(_ values: [Float]) -> Float {
    values.differentiableReduce(Float.zero, +)
}

func addBaselineArraySumBenchmarks(_ benchmark: inout Benchmark) {
    benchmark.add(
        title: benchmarkTitle,
        type: [Float].self,
        regular: { input in
            { _ in
                blackHole(arraySum(input))
            }
        },
        forward: { input in
            { _ in
                blackHole(valueWithPullback(at: input, of: arraySum).value)
            }
        },
        reverse: { input in
            let pullback = valueWithPullback(at: input, of: arraySum).pullback
            return { _ in
                blackHole(pullback(1))
            }
        }
    )
}
