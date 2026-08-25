#!/bin/bash
#
# Runs the engine suites straight from the command line — no Xcode, no
# simulator, no test target. Xcode runs the same suites under ⌘U through the
# solitaireTests target; this is the check that needs nothing but a toolchain.
#
# The sources below are the ones that stand up outside a running app. Anything
# that needs a live view hierarchy — GameViewModel above all — is covered by
# solitaireTests instead.
#
# -default-isolation MainActor matches SWIFT_DEFAULT_ACTOR_ISOLATION in the app
# target: without it these files would compile under different rules here than
# they do when shipped, and this harness would stop vouching for the app.
set -euo pipefail
cd "$(dirname "$0")"

SRC=../solitaire
OUT=.build
mkdir -p "$OUT"

swiftc -O -swift-version 6 -default-isolation MainActor \
    "$SRC/Models/Card.swift" \
    "$SRC/Models/GameState.swift" \
    "$SRC/Models/StatePacking.swift" \
    "$SRC/Models/Scoring.swift" \
    "$SRC/Models/MoveAdvisor.swift" \
    "$SRC/Models/SavedGame.swift" \
    "$SRC/Models/Statistics.swift" \
    "$SRC/Models/GameSettings.swift" \
    "$SRC/Models/TimeFormat.swift" \
    "$SRC/Views/BoardLayout.swift" \
    "$SRC/Support/Strings.swift" \
    EngineTests.swift \
    main.swift \
    -o "$OUT/enginetests"

"$OUT/enginetests"
