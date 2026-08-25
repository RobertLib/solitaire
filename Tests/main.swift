//
//  main.swift
//  solitaire
//
//  Command-line entry point for the engine suites. Kept apart from
//  EngineTests.swift because that file is also compiled into the Xcode test
//  target, where a second `main` would be one too many.
//

import Foundation

let failures = EngineTests.runAll()
print(failures.isEmpty ? "ALL ENGINE TESTS PASSED" : "\(failures.count) FAILURE(S)")
exit(failures.isEmpty ? 0 : 1)
