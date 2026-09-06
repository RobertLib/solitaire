//
//  StatisticsView.swift
//  solitaire
//

import SwiftUI

struct StatisticsView: View {
    var statistics: Statistics
    /// The Vegas balance to show, asked for rather than read off `statistics`.
    ///
    /// The balance in the status bar counts the deal on the table — the buy-in
    /// appearing the moment the cards are dealt is exactly that — so a table
    /// showing only the banked figure put two different numbers under the same
    /// word on two screens at once. `GameViewModel.vegasBalance` is the answer
    /// both now give. A closure rather than a figure because clearing the table
    /// changes it, and `statistics.data` — which this view already reads — is
    /// what re-runs `body` when it does.
    var vegasBalance: () -> Int
    /// Called after the table is cleared, so the deal on the table can count
    /// itself into the fresh one. See `GameViewModel.statisticsWereReset`.
    var onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    private var data: StatisticsData { statistics.data }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatRow(label: L10n.gamesPlayed, value: "\(data.gamesPlayed)")
                    StatRow(label: L10n.gamesWon, value: "\(data.gamesWon)")
                    // Formatted rather than spelled out: English writes
                    // "100%" and Czech "100 %", and where the space goes is
                    // the locale's business rather than something to fix in
                    // a format string here. This is the one figure on the
                    // screen that is not a bare count.
                    StatRow(label: L10n.winRate, value: data.gamesPlayed > 0
                            ? data.winRate.formatted(.percent.precision(.fractionLength(0)))
                            : "—")
                    StatRow(label: L10n.currentStreak, value: "\(data.currentStreak)")
                    StatRow(label: L10n.bestStreak, value: "\(data.bestStreak)")
                    StatRow(label: L10n.vegasBalance, value: ScoreKeeper.formatVegas(vegasBalance()))
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
                Button(L10n.reset, role: .destructive) {
                    statistics.reset()
                    onReset()
                }
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
