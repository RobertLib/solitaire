//
//  MenuSheet.swift
//  solitaire
//
//  In-game pause menu.
//

import SwiftUI

struct MenuSheet: View {
    var vm: GameViewModel
    var onSettings: () -> Void
    var onStatistics: () -> Void
    var onHelp: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MenuRow(icon: "play.fill", tint: .green, title: L10n.resume, navigates: false) {
                        dismiss()
                    }
                    MenuRow(icon: "plus.rectangle.on.rectangle", tint: .blue, title: L10n.newGame, navigates: false) {
                        dismiss()
                        vm.newGame()
                    }
                    MenuRow(icon: "arrow.counterclockwise", tint: .orange, title: L10n.restartDeal, navigates: false) {
                        dismiss()
                        vm.restartDeal()
                    }
                }
                Section {
                    MenuRow(icon: "gearshape.fill", tint: .gray, title: L10n.settings, action: onSettings)
                    MenuRow(icon: "chart.bar.fill", tint: .purple, title: L10n.statistics, action: onStatistics)
                    MenuRow(icon: "questionmark.circle.fill", tint: .teal, title: L10n.howToPlay, action: onHelp)
                } footer: {
                    HStack {
                        Text(L10n.dealNumber("\(vm.seed)"))
                        Spacer()
                        Text("\(vm.drawCount == 3 ? L10n.drawThree : L10n.drawOne) · \(vm.scoring.mode.displayName)")
                    }
                    .font(.footnote)
                }
            }
            .navigationTitle(L10n.appTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.close) { dismiss() }
                }
            }
        }
        // Full height only. At a partial detent iOS gives the sheet a glass
        // background, and the felt and cards behind it show straight through a
        // list of buttons — the one sheet in the app that did not look like the
        // others. Full height also brings the footer, which carries the deal
        // number and the rules in force, back above the fold.
        .presentationDetents([.large])
    }
}

private struct MenuRow: View {
    var icon: String
    var tint: Color
    var title: String
    /// Whether the row opens another screen. The chevron promises one, so the
    /// three rows that act on the game and dismiss — resume, deal, restart —
    /// say no and go without it.
    var navigates: Bool = true
    var action: () -> Void

    var body: some View {
        // `.plain` so the label keeps the colours set below. Under the
        // automatic style a button's label resolves `.primary` to the button's
        // tint, which is the app's gold accent — every row came out gold, and
        // the `.foregroundStyle` on the title did nothing.
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                if navigates {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
