//
//  GameSettings.swift
//  solitaire
//
//  User preferences, persisted to UserDefaults.
//

import Foundation
import Observation

enum TableTheme: String, Codable, CaseIterable, Identifiable {
    case forest, midnight, ocean, wine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .forest: return L10n.themeForest
        case .midnight: return L10n.themeMidnight
        case .ocean: return L10n.themeOcean
        case .wine: return L10n.themeWine
        }
    }
}

enum CardBackStyle: String, Codable, CaseIterable, Identifiable {
    case crimson, royal, emerald, night

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .crimson: return L10n.backCrimson
        case .royal: return L10n.backRoyal
        case .emerald: return L10n.backEmerald
        case .night: return L10n.backNight
        }
    }
}

@Observable
final class GameSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var drawCount: Int {
        didSet { defaults.set(drawCount, forKey: "settings.drawCount") }
    }
    var scoringMode: ScoringMode {
        didSet { defaults.set(scoringMode.rawValue, forKey: "settings.scoringMode") }
    }
    var vegasCumulative: Bool {
        didSet { defaults.set(vegasCumulative, forKey: "settings.vegasCumulative") }
    }
    var leftHandMode: Bool {
        didSet { defaults.set(leftHandMode, forKey: "settings.leftHandMode") }
    }
    var tableTheme: TableTheme {
        didSet { defaults.set(tableTheme.rawValue, forKey: "settings.tableTheme") }
    }
    var cardBack: CardBackStyle {
        didSet { defaults.set(cardBack.rawValue, forKey: "settings.cardBack") }
    }
    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: "settings.sounds") }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "settings.haptics") }
    }

    /// `defaults` is a parameter so the tests can read and write a scratch
    /// suite rather than the preferences of whoever is running them.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        let storedDraw = d.integer(forKey: "settings.drawCount")
        drawCount = storedDraw == 3 ? 3 : 1
        scoringMode = ScoringMode(rawValue: d.string(forKey: "settings.scoringMode") ?? "") ?? .standard
        vegasCumulative = d.bool(forKey: "settings.vegasCumulative")
        leftHandMode = d.bool(forKey: "settings.leftHandMode")
        tableTheme = TableTheme(rawValue: d.string(forKey: "settings.tableTheme") ?? "") ?? .forest
        cardBack = CardBackStyle(rawValue: d.string(forKey: "settings.cardBack") ?? "") ?? .crimson
        soundsEnabled = d.object(forKey: "settings.sounds") as? Bool ?? true
        hapticsEnabled = d.object(forKey: "settings.haptics") as? Bool ?? true
    }
}
