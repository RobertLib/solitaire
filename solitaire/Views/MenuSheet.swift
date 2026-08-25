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
                    MenuRow(icon: "play.fill", tint: .green, title: L10n.resume) {
                        dismiss()
                    }
                    MenuRow(icon: "plus.rectangle.on.rectangle", tint: .blue, title: L10n.newGame) {
                        dismiss()
                        vm.newGame()
                    }
                    MenuRow(icon: "arrow.counterclockwise", tint: .orange, title: L10n.restartDeal) {
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
        .presentationDetents([.medium, .large])
    }
}

private struct MenuRow: View {
    var icon: String
    var tint: Color
    var title: String
    var action: () -> Void

    var body: some View {
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
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
