import Foundation

final class Expect: @unchecked Sendable {
    static let shared = Expect()
    var failures = 0

    static func equal<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if actual != expected {
            shared.failures += 1
            print("FAIL \(file):\(line) expected \(expected), got \(actual)")
        }
    }

    static func isTrue(
        _ value: Bool,
        _ message: String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if !value {
            shared.failures += 1
            print("FAIL \(file):\(line) \(message)")
        }
    }

    static func isNil<T>(
        _ value: T?,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        if value != nil {
            shared.failures += 1
            print("FAIL \(file):\(line) expected nil, got \(String(describing: value))")
        }
    }

    static func unwrap<T>(
        _ value: T?,
        file: StaticString = #fileID,
        line: UInt = #line
    ) throws -> T {
        guard let value else {
            shared.failures += 1
            print("FAIL \(file):\(line) unexpected nil")
            throw UnwrapError()
        }
        return value
    }
}

struct UnwrapError: Error {}
