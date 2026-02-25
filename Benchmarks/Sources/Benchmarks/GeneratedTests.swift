import Foundation

enum GeneratedInput {
    case scalarFloat(Float)
    case singleFloat([Float])
    case pairFloat([Float], [Float])
    case singleDouble([Double])
}

struct GeneratedTestCase {
    let index: Int
    let snippet: String
    let iterations: Int
    let input: GeneratedInput
    let forward: () -> Void
    let reverse: () -> Void
}

extension GeneratedTestCase: @unchecked Sendable {}
