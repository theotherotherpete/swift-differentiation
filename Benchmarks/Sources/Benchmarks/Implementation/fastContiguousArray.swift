import CollectionsBenchmark
import Differentiation
import Foundation

private let benchmarkTitle = "fastContiguousArray"

@differentiable(reverse)
private func contiguousArraySum(_ values: ContiguousArray<Float>) -> Float {
    var sum: Float = 0
    for i in 0 ..< withoutDerivative(at: values.count) {
        sum += values[i]
    }
    return sum
}

func addContiguousArrayBenchmarks(_ benchmark: inout Benchmark) {
    benchmark.add(
        title: benchmarkTitle,
        type: ContiguousArray<Float>.self,
        regular: { input in
            { _ in
                blackHole(contiguousArraySum(input))
            }
        },
        forward: { input in
            { _ in
                blackHole(valueWithPullback(at: input, of: contiguousArraySum).value)
            }
        },
        reverse: { input in
            let pullback = valueWithPullback(at: input, of: contiguousArraySum).pullback
            return { _ in
                blackHole(pullback(1))
            }
        }
    )
}
