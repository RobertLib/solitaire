//
//  Scoring.swift
//  solitaire
//
//  Standard (Windows-style) and Vegas scoring rules.
//

import Foundation

enum ScoringMode: String, Codable, CaseIterable, Sendable {
    case none
    case standard
    case vegas

    var displayName: String {
        switch self {
        case .none: return L10n.scoringNone
        case .standard: return L10n.scoringStandard
        case .vegas: return L10n.scoringVegas
        }
    }
}

enum ScoreEvent {
    case wasteToTableau
    case wasteToFoundation
    case tableauToFoundation
    case foundationToTableau
    case turnOverTableauCard
    /// Turning the waste back into the stock, beginning pass number `pass`
    /// through the deck. The deal itself is pass 1, so the first recycle
    /// begins pass 2.
    case recycleWaste(drawCount: Int, pass: Int)

    /// Point delta under standard scoring.
    var standardDelta: Int {
        switch self {
        case .wasteToTableau: return 5
        case .wasteToFoundation: return 10
        case .tableauToFoundation: return 10
        case .foundationToTableau: return -15
        case .turnOverTableauCard: return 5
        case .recycleWaste(let drawCount, let pass):
            // Windows scoring charges for turning the deck over, but not
            // for the passes the rules expect a player to need. Drawing one
            // card at a time shows the whole deck in a single pass, so every
            // pass after the first costs; drawing three shows a third of it
            // per pass, so the first three are free and the fourth is where
            // the deck has been seen in full and the player is going round
            // again.
            if drawCount == 1 { return pass > 1 ? -100 : 0 }
            return pass > 3 ? -20 : 0
        }
    }

    /// Dollar delta under Vegas scoring ($5 per card reaching a foundation).
    var vegasDelta: Int {
        switch self {
        case .wasteToFoundation, .tableauToFoundation: return 5
        case .foundationToTableau: return -5
        default: return 0
        }
    }
}

struct ScoreKeeper: Codable, Equatable {
    var mode: ScoringMode
    var points: Int

    init(mode: ScoringMode) {
        self.mode = mode
        // Vegas: the deck is "bought" for $52 up front.
        self.points = mode == .vegas ? -52 : 0
    }

    mutating func apply(_ event: ScoreEvent) {
        switch mode {
        case .none:
            break
        case .standard:
            points = max(0, points + event.standardDelta)
        case .vegas:
            points += event.vegasDelta
        }
    }

    /// Windows-style trickle penalty: −2 points every 10 seconds.
    ///
    /// `times` charges several ticks at once, which undo needs: it restores the
    /// score the board had before a move, and the penalties the clock has run up
    /// since then have to go back on top of it.
    mutating func applyTimePenalty(times: Int = 1) {
        guard mode == .standard, times > 0 else { return }
        points = max(0, points - 2 * times)
    }

    /// Windows-style time bonus awarded on winning a timed standard game.
    static func timeBonus(elapsedSeconds: Int) -> Int {
        guard elapsedSeconds > 30 else { return 0 }
        return 700_000 / elapsedSeconds
    }

    /// Number of passes through the stock allowed for the given rules.
    /// nil means unlimited.
    static func allowedPasses(mode: ScoringMode, drawCount: Int) -> Int? {
        guard mode == .vegas else { return nil }
        return drawCount == 1 ? 1 : 3
    }

    static func formatVegas(_ amount: Int) -> String {
        amount < 0 ? "-$\(-amount)" : "$\(amount)"
    }
}
