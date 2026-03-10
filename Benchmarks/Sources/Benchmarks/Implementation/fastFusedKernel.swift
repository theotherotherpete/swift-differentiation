import CollectionsBenchmark
import Differentiation
import Foundation

private let benchmarkTitle = "fastFusedKernel"

@differentiable(reverse)
private func fusedKernelSum(_ values: [Float]) -> Float {
    var sum: Float = 0
    for i in 0 ..< withoutDerivative(at: values.count) {
        let v = values[i]
        let y = v * 1.1 + 0.3
        sum += y
    }
    return sum
}

@derivative(of: fusedKernelSum)
private func vjpFusedKernelSum(_ values: [Float]) -> (value: Float, pullback: (Float) -> [Float].TangentVector) {
    let value = fusedKernelSum(values)
    return (value, { v in
        let scale = v * 1.1
        return Array<Float>.DifferentiableView(repeating: scale, count: values.count)
    })
}

func addFusedKernelBenchmarks(_ benchmark: inout Benchmark) {
    benchmark.add(
        title: benchmarkTitle,
        type: [Float].self,
        regular: { input in
            { _ in
                blackHole(fusedKernelSum(input))
            }
        },
        forward: { input in
            { _ in
                blackHole(valueWithPullback(at: input, of: fusedKernelSum).value)
            }
        },
        reverse: { input in
            let pullback = valueWithPullback(at: input, of: fusedKernelSum).pullback
            return { _ in
                blackHole(pullback(1))
            }
        }
    )
}
