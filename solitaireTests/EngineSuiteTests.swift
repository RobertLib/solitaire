//
//  EngineSuiteTests.swift
//  solitaireTests
//
//  Brings the command-line engine suites under ⌘U. The assertions live in
//  Tests/EngineTests.swift, which this target compiles too, so the two ways of
//  running them can never check different things.
//

import XCTest
@testable import solitaire

@MainActor
final class EngineSuiteTests: XCTestCase {
    func testEngineSuites() {
        // A slice of the fuzz rather than the whole sweep: the game logic is
        // compiled into the app module, which Xcode builds unoptimised, and the
        // full 400 deals take three minutes there against two seconds under
        // ./Tests/run.sh. That script is the thorough gate; this keeps ⌘U worth
        // pressing while still holding every invariant on every move it plays.
        for failure in EngineTests.runAll(fuzzDeals: 50) {
            XCTFail(failure)
        }
    }
}
