import Foundation

/// Minimal test harness for the TDD loop.
///
/// This machine only has Command Line Tools: no XCTest, and swift-testing's
/// runner integration is not wired up, so tests run through this tiny
/// in-repo harness instead: `swift run alttab-tests` exits non-zero on any
/// failure and prints one line per test.

public struct TestFailure: Error {
    let message: String
    let file: StaticString
    let line: UInt
}

public func expect(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    if !condition() {
        throw TestFailure(message: message(), file: file, line: line)
    }
}

public func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: String = "",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    if actual != expected {
        let prefix = label.isEmpty ? "" : "\(label): "
        throw TestFailure(
            message: "\(prefix)expected \(expected), got \(actual)",
            file: file,
            line: line
        )
    }
}

public final class TestSuite {
    public struct Case {
        let name: String
        let body: () throws -> Void
    }

    public let name: String
    public private(set) var cases: [Case] = []

    public init(_ name: String, _ register: (TestSuite) -> Void = { _ in }) {
        self.name = name
        register(self)
    }

    public func test(_ name: String, _ body: @escaping () throws -> Void) {
        cases.append(Case(name: name, body: body))
    }
}

public enum TestRunner {
    public static func run(_ suites: [TestSuite]) -> Int32 {
        var failed = 0
        var passed = 0
        var failedNames: [String] = []

        for suite in suites {
            print("Suite \(suite.name)")
            for testCase in suite.cases {
                do {
                    try testCase.body()
                    passed += 1
                    print("  ✅ \(testCase.name)")
                } catch let failure as TestFailure {
                    failed += 1
                    let caseID = "\(suite.name).\(testCase.name)"
                    failedNames.append(caseID)
                    print("  ❌ \(testCase.name)")
                    print("     \(failure.file):\(failure.line) — \(failure.message)")
                } catch {
                    failed += 1
                    let caseID = "\(suite.name).\(testCase.name)"
                    failedNames.append(caseID)
                    print("  ❌ \(testCase.name)")
                    print("     threw unexpected error: \(error)")
                }
            }
        }

        print("----------------------------------------")
        print("Passed: \(passed)  Failed: \(failed)")
        if !failedNames.isEmpty {
            print("Failures:")
            for name in failedNames { print("  - \(name)") }
        }
        return failed == 0 ? 0 : 1
    }
}

/// Exit the process with a status code usable by CI / TDD scripts.
public func exitWithTestResult(_ suites: [TestSuite]) -> Never {
    exit(TestRunner.run(suites))
}
