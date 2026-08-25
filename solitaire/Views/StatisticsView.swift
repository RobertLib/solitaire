//
//  StatisticsView.swift
//  solitaire
//

import SwiftUI

struct StatisticsView: View {
    var statistics: Statistics

    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private var data: StatisticsData { statistics.data }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatRow(label: L10n.gamesPlayed, value: "\(data.gamesPlayed)")
                    StatRow(label: L10n.gamesWon, value: "\(data.gamesWon)")
                    StatRow(label: L10n.winRate, value: data.gamesPlayed > 0
                            ? "\(Int((data.winRate * 100).rounded())) %" : "—")
                    StatRow(label: L10n.currentStreak, value: "\(data.currentStreak)")
                    StatRow(label: L10n.bestStreak, value: "\(data.bestStreak)")
                    StatRow(label: L10n.vegasBalance, value: ScoreKeeper.formatVegas(data.vegasBalance))
                }
                // A draw-1 deal beats a draw-3 one on time, moves and score
                // alike, so each mode keeps its own bests rather than the two
                // sharing a table the easier one would always top.
                Section(L10n.drawOne) { records(data.drawOne) }
                Section(L10n.drawThree) { records(data.drawThree) }
                Section {
                    Button(role: .destructive) {
                        confirmReset = true
                    } label: {
                        Text(L10n.resetStats)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(L10n.statistics)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
            .confirmationDialog(L10n.resetStatsConfirm, isPresented: $confirmReset, titleVisibility: .visible) {
                Button(L10n.reset, role: .destructive) { statistics.reset() }
                Button(L10n.cancel, role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func records(_ r: StatisticsData.Records) -> some View {
        StatRow(label: L10n.bestTime, value: r.bestTimeSeconds.map(TimeFormat.clock) ?? "—")
        StatRow(label: L10n.fewestMoves, value: r.fewestMoves.map(String.init) ?? "—")
        StatRow(label: L10n.bestScore, value: r.bestStandardScore.map(String.init) ?? "—")
    }
}

private struct StatRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
