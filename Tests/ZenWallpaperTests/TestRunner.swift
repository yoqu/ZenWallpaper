import Foundation

/// Minimal assertion + reporter for a SwiftPM-only self-test target. We intentionally
/// avoid XCTest / swift-testing because neither links cleanly under a
/// CommandLineTools-only toolchain (see Package.swift for context).
enum TestReporter {
    nonisolated(unsafe) private static var failures: [(name: String, message: String)] = []

    static func recordFailure(_ name: String, _ message: String) {
        failures.append((name, message))
    }

    static func reset() {
        failures.removeAll()
    }

    /// Returns true when every assertion in the closure passed.
    static func run(_ name: String, _ body: () throws -> Void) -> Bool {
        let before = failures.count
        do {
            try body()
        } catch {
            recordFailure(name, "threw \(error)")
        }
        let passed = failures.count == before
        print((passed ? "  ✓ " : "  ✗ ") + name)
        return passed
    }

    /// Async sibling of `run` for tests that need to await something.
    static func runAsync(_ name: String, _ body: () async throws -> Void) async -> Bool {
        let before = failures.count
        do {
            try await body()
        } catch {
            recordFailure(name, "threw \(error)")
        }
        let passed = failures.count == before
        print((passed ? "  ✓ " : "  ✗ ") + name)
        return passed
    }

    static func summarize() -> Int {
        if failures.isEmpty {
            print("All tests passed.")
            return 0
        }
        print("\nFailures:")
        for failure in failures {
            print("  - \(failure.name): \(failure.message)")
        }
        return 1
    }
}

func expectTrue(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String,
                file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        TestReporter.recordFailure("\(file):\(line)", message())
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: @autoclosure () -> String = "",
                               file: StaticString = #file, line: UInt = #line) {
    if actual != expected {
        let label = message().isEmpty
            ? "expected \(expected), got \(actual)"
            : "\(message()) — expected \(expected), got \(actual)"
        TestReporter.recordFailure("\(file):\(line)", label)
    }
}

func expectNotNil<T>(_ value: T?, _ message: @autoclosure () -> String,
                     file: StaticString = #file, line: UInt = #line) {
    if value == nil {
        TestReporter.recordFailure("\(file):\(line)", message())
    }
}
