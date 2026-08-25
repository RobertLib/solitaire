//
//  Statistics.swift
//  solitaire
//
//  Lifetime player statistics, persisted to UserDefaults.
//

import Foundation
import Observation

struct StatisticsData: Equatable {
    /// The best a player has managed under one set of rules.
    ///
    /// Kept per draw mode: draw 1 and draw 3 are different games, and a draw-1
    /// deal beats a draw-3 one on time, moves and score alike — pooled, the
    /// table would only ever show how the easier mode had gone.
    struct Records: Codable, Equatable {
        var bestTimeSeconds: Int?
        var fewestMoves: Int?
        var bestStandardScore: Int?
    }

    var gamesPlayed = 0
    var gamesWon = 0
    var currentStreak = 0
    var bestStreak = 0
    var vegasBalance = 0
    var drawOne = Records()
    var drawThree = Records()

    var winRate: Double {
        gamesPlayed > 0 ? Double(gamesWon) / Double(gamesPlayed) : 0
    }

    /// The records kept for a set of rules. Settings offer only the two draw
    /// counts, so anything that is not draw 3 is draw 1.
    subscript(drawCount drawCount: Int) -> Records {
        get { drawCount == 3 ? drawThree : drawOne }
        set { if drawCount == 3 { drawThree = newValue } else { drawOne = newValue } }
    }
}

extension StatisticsData: Codable {
    private enum CodingKeys: String, CodingKey {
        case gamesPlayed, gamesWon, currentStreak, bestStreak, vegasBalance, drawOne, drawThree
    }

    /// Keys written by builds that kept one set of records for both draw modes.
    private enum PooledRecordKeys: String, CodingKey {
        case bestTimeSeconds, fewestMoves, bestStandardScore
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gamesPlayed = try c.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0
        gamesWon = try c.decodeIfPresent(Int.self, forKey: .gamesWon) ?? 0
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        vegasBalance = try c.decodeIfPresent(Int.self, forKey: .vegasBalance) ?? 0
        drawThree = try c.decodeIfPresent(Records.self, forKey: .drawThree) ?? Records()

        if let split = try c.decodeIfPresent(Records.self, forKey: .drawOne) {
            drawOne = split
        } else {
            // A table written before the records were split. Those bests were
            // set under whichever mode the player was using at the time and the
            // table did not say which, so they go to draw 1 — the default, and
            // much the likelier of the two — rather than being thrown away.
            let pooled = try decoder.container(keyedBy: PooledRecordKeys.self)
            drawOne = Records(
                bestTimeSeconds: try pooled.decodeIfPresent(Int.self, forKey: .bestTimeSeconds),
                fewestMoves: try pooled.decodeIfPresent(Int.self, forKey: .fewestMoves),
                bestStandardScore: try pooled.decodeIfPresent(Int.self, forKey: .bestStandardScore)
            )
        }
    }
}

@Observable
final class Statistics {
    private static let key = "solitaire.statistics.v1"

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var data: StatisticsData {
        didSet { save() }
    }

    /// `defaults` is a parameter so the tests can keep their tallies out of the
    /// defaults of whoever is running them.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(StatisticsData.self, from: raw) {
            data = decoded
        } else {
            data = StatisticsData()
        }
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            defaults.set(raw, forKey: Self.key)
        }
    }

    /// Applies a batch of changes as one write. Assigning `data` field by field
    /// would encode and store the whole blob again for every field touched.
    private func update(_ change: (inout StatisticsData) -> Void) {
        var copy = data
        change(&copy)
        data = copy
    }

    /// Called once per deal, when the player makes their first move.
    func recordGameStarted() {
        update { $0.gamesPlayed += 1 }
    }

    /// Called when a started game is abandoned without winning.
    func recordLoss() {
        update { $0.currentStreak = 0 }
    }

    /// Marks the current game as won. Returns which records were newly set.
    @discardableResult
    func recordWin(drawCount: Int, timeSeconds: Int, moves: Int, standardScore: Int?) -> (time: Bool, moves: Bool, score: Bool) {
        var newTime = false, newMoves = false, newScore = false
        update { d in
            d.gamesWon += 1
            d.currentStreak += 1
            d.bestStreak = max(d.bestStreak, d.currentStreak)

            var records = d[drawCount: drawCount]
            if records.bestTimeSeconds == nil || timeSeconds < records.bestTimeSeconds! {
                records.bestTimeSeconds = timeSeconds
                newTime = true
            }
            if records.fewestMoves == nil || moves < records.fewestMoves! {
                records.fewestMoves = moves
                newMoves = true
            }
            if let score = standardScore, records.bestStandardScore == nil || score > records.bestStandardScore! {
                records.bestStandardScore = score
                newScore = true
            }
            d[drawCount: drawCount] = records
        }
        return (newTime, newMoves, newScore)
    }

    func addVegasResult(_ amount: Int) {
        update { $0.vegasBalance += amount }
    }

    func reset() {
        data = StatisticsData()
    }
}
