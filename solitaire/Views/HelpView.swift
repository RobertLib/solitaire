//
//  HelpView.swift
//  solitaire
//
//  The rules of the game, for a player meeting Klondike for the first time.
//

import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HelpSection(icon: "flag.checkered", title: L10n.helpObjectiveTitle, text: L10n.helpObjective)
                    HelpSection(icon: "rectangle.split.3x1", title: L10n.helpTableauTitle, text: L10n.helpTableau)
                    HelpSection(icon: "rectangle.stack", title: L10n.helpStockTitle, text: L10n.helpStock)
                    HelpSection(icon: "hand.tap", title: L10n.helpControlsTitle, text: L10n.helpControls)
                    HelpSection(icon: "star.circle", title: L10n.helpScoringTitle, text: L10n.helpScoring)
                }
                .padding(20)
            }
            .navigationTitle(L10n.howToPlay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
    }
}

private struct HelpSection: View {
    var icon: String
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
