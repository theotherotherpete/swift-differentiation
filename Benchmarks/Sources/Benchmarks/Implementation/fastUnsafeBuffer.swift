import CollectionsBenchmark
import Differentiation
import Foundation

private let benchmarkTitle = "fastUnsafeBufferSum"

@differentiable(reverse)
private func unsafeBufferSum(_ values: [Float]) -> Float {
    values.withUnsafeBufferPointer { buffer in
        var sum: Float = 0
        for i in 0 ..< buffer.count {
            sum += buffer[i]
        }
        return sum
    }
}

@derivative(of: unsafeBufferSum)
private func vjpUnsafeBufferSum(_ values: [Float]) -> (value: Float, pullback: (Float) -> [Float].TangentVector) {
    let value = unsafeBufferSum(values)
    return (value, { v in
        Array<Float>.DifferentiableView(repeating: v, count: values.count)
    })
}

func addUnsafeBufferBenchmarks(_ benchmark: inout Benchmark) {
    benchmark.add(
        title: benchmarkTitle,
        type: [Float].self,
        regular: { input in
            { _ in
                blackHole(unsafeBufferSum(input))
            }
        },
        forward: { input in
            { _ in
                blackHole(valueWithPullback(at: input, of: unsafeBufferSum).value)
            }
        },
        reverse: { input in
            let pullback = valueWithPullback(at: input, of: unsafeBufferSum).pullback
            return { _ in
                blackHole(pullback(1))
            }
        }
    )
}
