//
//  SettingsView.swift
//  solitaire
//

import SwiftUI

struct SettingsView: View {
    @Bindable var settings: GameSettings

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The label above the control rather than beside it. A
                    // segmented picker hides its own, and the footer below
                    // names this setting by name — "Draw and scoring apply to
                    // the next deal." — so without one the footer named a
                    // control that was never labelled; in Czech the segments
                    // ("Po 1 kartě") do not carry the word either. Beside it
                    // the two segments would be squeezed instead.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.draw)
                        Picker(L10n.draw, selection: $settings.drawCount) {
                            Text(L10n.drawOne).tag(1)
                            Text(L10n.drawThree).tag(3)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    Picker(L10n.scoring, selection: $settings.scoringMode) {
                        ForEach(ScoringMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if settings.scoringMode == .vegas {
                        Toggle(L10n.vegasCumulative, isOn: $settings.vegasCumulative)
                    }
                } header: {
                    Text(L10n.gameplay)
                } footer: {
                    Text(settings.scoringMode == .vegas
                         ? "\(L10n.appliesNextDeal) \(L10n.vegasCumulativeFooter)"
                         : L10n.appliesNextDeal)
                }

                Section(L10n.appearance) {
                    Picker(L10n.tableTheme, selection: $settings.tableTheme) {
                        ForEach(TableTheme.allCases) { theme in
                            HStack {
                                Circle()
                                    .fill(theme.feltCenter)
                                    .frame(width: 18, height: 18)
                                    .overlay(Circle().strokeBorder(.black.opacity(0.2)))
                                Text(theme.displayName)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker(L10n.cardBack, selection: $settings.cardBack) {
                        ForEach(CardBackStyle.allCases) { style in
                            HStack(spacing: 10) {
                                CardBackView(style: style, size: CGSize(width: 26, height: 37))
                                Text(style.displayName)
                            }
                            .tag(style)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Toggle(L10n.leftHandMode, isOn: $settings.leftHandMode)
                }

                Section(L10n.feedback) {
                    Toggle(L10n.sounds, isOn: $settings.soundsEnabled)
                        // Switching them on here is the one moment the
                        // synthesiser is not already warm, and the next move is
                        // moments away — build it now so that move is heard.
                        .onChange(of: settings.soundsEnabled) { _, on in
                            SoundManager.prepare(enabled: on)
                        }
                    Toggle(L10n.haptics, isOn: $settings.hapticsEnabled)
                }
            }
            .navigationTitle(L10n.settings)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.done) { dismiss() }
                }
            }
        }
    }
}
