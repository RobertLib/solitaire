//
//  Card.swift
//  solitaire
//
//  Core playing-card model. Kept free of UI frameworks so the game engine
//  can be compiled and tested standalone.
//

import Foundation

enum Suit: String, CaseIterable, Codable, Sendable {
    case spades, hearts, diamonds, clubs

    var isRed: Bool { self == .hearts || self == .diamonds }

    var symbol: String {
        switch self {
        case .spades: return "♠"
        case .hearts: return "♥"
        case .diamonds: return "♦"
        case .clubs: return "♣"
        }
    }
}

enum Rank: Int, CaseIterable, Codable, Comparable, Sendable {
    case ace = 1, two, three, four, five, six, seven, eight, nine, ten, jack, queen, king

    static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Short label printed in the card corners.
    var label: String {
        switch self {
        case .ace: return "A"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        default: return String(rawValue)
        }
    }
}

struct Card: Identifiable, Equatable, Hashable, Codable, Sendable {
    let suit: Suit
    let rank: Rank
    var isFaceUp: Bool = false

    // Stable identity independent of face-up state, so SwiftUI animates the
    // same view as a card moves and flips.
    var id: String { "\(suit.rawValue)-\(rank.rawValue)" }

    var isRed: Bool { suit.isRed }

    /// A full 52-card deck in deterministic order (shuffle before use).
    static var orderedDeck: [Card] {
        Suit.allCases.flatMap { suit in
            Rank.allCases.map { rank in Card(suit: suit, rank: rank) }
        }
    }
}

/// Deterministic SplitMix64 generator so deals can be replayed by number.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
