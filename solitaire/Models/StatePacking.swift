//
//  StatePacking.swift
//  solitaire
//
//  The compact binary forms the save file is built out of: a board in 65
//  bytes, and one step of the undo history in 92.
//
//  The history holds one record per move and is rewritten after every single
//  move, so the JSON a synthesised encoder produces — around 200 bytes per
//  step, re-encoded from scratch each time — is the wrong shape for it. These
//  bytes are written to disk, so every number below is part of the save
//  format: reorder them and old saves decode into the wrong cards.
//

import Foundation

extension Suit {
    /// Stable on-disk code. Do not renumber.
    var code: UInt8 {
        switch self {
        case .spades: return 0
        case .hearts: return 1
        case .diamonds: return 2
        case .clubs: return 3
        }
    }

    init?(code: UInt8) {
        switch code {
        case 0: self = .spades
        case 1: self = .hearts
        case 2: self = .diamonds
        case 3: self = .clubs
        default: return nil
        }
    }
}

extension Card {
    /// Suit and rank in the low seven bits, face-up in the high bit.
    var packedByte: UInt8 {
        let base = suit.code * 13 + UInt8(rank.rawValue - 1)
        return isFaceUp ? base | 0x80 : base
    }

    init?(packedByte byte: UInt8) {
        let index = byte & 0x7F
        guard index < 52,
              let suit = Suit(code: index / 13),
              let rank = Rank(rawValue: Int(index % 13) + 1)
        else { return nil }
        self.init(suit: suit, rank: rank, isFaceUp: byte & 0x80 != 0)
    }
}

// MARK: - Board

extension GameState {
    /// Thirteen pile lengths followed by the cards themselves, in the order
    /// `allPiles` lists them. That order is part of the format too.
    static let packedSize = 65

    var packedBytes: [UInt8] {
        let piles = Self.allPiles
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.packedSize)
        for pile in piles { bytes.append(UInt8(truncatingIfNeeded: self[pile].count)) }
        for pile in piles {
            for card in self[pile] { bytes.append(card.packedByte) }
        }
        return bytes
    }

    var packed: Data { Data(packedBytes) }

    /// Reads a packed board back, or nil if the bytes are not one. Only checks
    /// the shape — that 52 distinct cards are laid out in a board the rules
    /// could have produced is `isConsistent`'s job, as it is for any save.
    init?(packedBytes bytes: [UInt8]) {
        let piles = Self.allPiles
        guard bytes.count == Self.packedSize else { return nil }

        let counts = bytes.prefix(piles.count).map(Int.init)
        guard counts.reduce(0, +) == 52 else { return nil }

        var state = GameState()
        var offset = piles.count
        for (i, pile) in piles.enumerated() {
            var cards: [Card] = []
            cards.reserveCapacity(counts[i])
            for _ in 0..<counts[i] {
                guard let card = Card(packedByte: bytes[offset]) else { return nil }
                cards.append(card)
                offset += 1
            }
            state[pile] = cards
        }
        self = state
    }

    init?(packed data: Data) {
        self.init(packedBytes: [UInt8](data))
    }
}

// MARK: - One step of the undo history

/// The board as it stood *before* a move, with the counters that go back with
/// it. Undo restores the score the board had, and the clock does not rewind,
/// so `elapsedSeconds` is kept to work out which time penalties have to be
/// charged again.
struct UndoStep: Equatable {
    var state: GameState
    var points: Int
    var moves: Int
    var recyclesUsed: Int
    var elapsedSeconds: Int
    /// Cards the move carried, kept only so the undo animation can fly the
    /// same cards back over the piles they left.
    var movedIDs: [String]

    /// The longest run the rules can produce is King down to Ace, so a move
    /// never carries more cards than this and the record can hold them inline.
    static let maxMovedCards = 13

    /// The most recycles a record can carry — one byte's worth.
    ///
    /// `GameViewModel` stops counting here too, so the number on the board and
    /// the number in the record can never part company and undo cannot restore
    /// a count the player never had. Nothing reads the figure this far out
    /// anyway: the Vegas pass limit is three, and the standard penalty is the
    /// same for every pass past the first. Reaching it at all takes 255 turns
    /// of the deck in a single deal.
    static let maxRecycles = 255

    /// Whether this step describes a board the rules could have produced.
    var isPlayable: Bool {
        // Points go negative under Vegas, the rest never do.
        state.isConsistent && moves >= 0 && recyclesUsed >= 0 && elapsedSeconds >= 0
    }
}

extension UndoStep {
    /// Fixed width, so the history is a plain run of records: adding a step is
    /// a copy onto the end and taking one back is a truncation, with nothing
    /// before it re-encoded.
    ///
    ///     0..<65   the board
    ///     65..<69  points          Int32, little-endian
    ///     69..<73  moves           Int32, little-endian
    ///     73..<77  elapsedSeconds  Int32, little-endian
    ///     77       recyclesUsed
    ///     78       how many cards the move carried
    ///     79..<92  those cards, one packed byte each, unused bytes zero
    static let packedSize = GameState.packedSize + 14 + maxMovedCards

    var packedBytes: [UInt8] {
        var bytes = state.packedBytes
        bytes.reserveCapacity(Self.packedSize)
        appendInt32(points, to: &bytes)
        appendInt32(moves, to: &bytes)
        appendInt32(elapsedSeconds, to: &bytes)
        // Saturates rather than wrapping, and `maxRecycles` keeps the live
        // count inside the range so this never actually has to.
        bytes.append(UInt8(clamping: recyclesUsed))
        let carried = movedIDs.prefix(Self.maxMovedCards).compactMap { Card.packedIndex(forID: $0) }
        bytes.append(UInt8(carried.count))
        bytes.append(contentsOf: carried)
        bytes.append(contentsOf: repeatElement(0, count: Self.maxMovedCards - carried.count))
        return bytes
    }

    init?(packedBytes bytes: [UInt8]) {
        guard bytes.count == Self.packedSize,
              let state = GameState(packedBytes: Array(bytes[0..<GameState.packedSize]))
        else { return nil }
        self.state = state
        points = readInt32(bytes, at: 65)
        moves = readInt32(bytes, at: 69)
        elapsedSeconds = readInt32(bytes, at: 73)
        recyclesUsed = Int(bytes[77])
        let carried = Int(bytes[78])
        guard carried <= Self.maxMovedCards else { return nil }
        movedIDs = (0..<carried).compactMap { Card(packedByte: bytes[79 + $0])?.id }
    }
}

private extension Card {
    /// The deck index a card id stands for, for writing a move's cards into a
    /// record as one byte each.
    static func packedIndex(forID id: String) -> UInt8? {
        let parts = id.split(separator: "-")
        guard parts.count == 2,
              let suit = Suit(rawValue: String(parts[0])),
              let rank = Int(parts[1]), (1...13).contains(rank)
        else { return nil }
        return suit.code * 13 + UInt8(rank - 1)
    }
}

private func appendInt32(_ value: Int, to bytes: inout [UInt8]) {
    let raw = UInt32(bitPattern: Int32(clamping: value))
    bytes.append(UInt8(truncatingIfNeeded: raw))
    bytes.append(UInt8(truncatingIfNeeded: raw >> 8))
    bytes.append(UInt8(truncatingIfNeeded: raw >> 16))
    bytes.append(UInt8(truncatingIfNeeded: raw >> 24))
}

private func readInt32(_ bytes: [UInt8], at index: Int) -> Int {
    let raw = UInt32(bytes[index])
        | UInt32(bytes[index + 1]) << 8
        | UInt32(bytes[index + 2]) << 16
        | UInt32(bytes[index + 3]) << 24
    return Int(Int32(bitPattern: raw))
}

// MARK: - The history

/// Every move of a deal, oldest first, as one run of fixed-width records.
///
/// Kept packed rather than as an array of values because it is written to disk
/// after every single move: adding a step is a copy onto the end of a buffer
/// that is already laid out, rather than re-encoding a growing array of
/// records each time. The save itself still hands the whole buffer to
/// `JSONEncoder`, which base64s it — a few tens of kilobytes at the history
/// cap, and the reason the records are this small.
struct UndoHistory: Equatable {
    private var bytes: [UInt8] = []

    init() {}

    /// Reads a stored history back, or nil if these are not records of boards
    /// the rules could have produced.
    init?(packed data: Data) {
        let raw = [UInt8](data)
        guard raw.count % UndoStep.packedSize == 0 else { return nil }
        for start in stride(from: 0, to: raw.count, by: UndoStep.packedSize) {
            let record = Array(raw[start ..< start + UndoStep.packedSize])
            guard let step = UndoStep(packedBytes: record), step.isPlayable else { return nil }
        }
        bytes = raw
    }

    var packed: Data { Data(bytes) }
    var count: Int { bytes.count / UndoStep.packedSize }
    var isEmpty: Bool { bytes.isEmpty }

    /// Adds a step, dropping the oldest ones once the history is `limit` deep.
    mutating func push(_ step: UndoStep, limit: Int) {
        bytes.append(contentsOf: step.packedBytes)
        let excess = count - max(0, limit)
        if excess > 0 { bytes.removeFirst(excess * UndoStep.packedSize) }
    }

    mutating func popLast() -> UndoStep? {
        guard bytes.count >= UndoStep.packedSize else { return nil }
        let start = bytes.count - UndoStep.packedSize
        let step = UndoStep(packedBytes: Array(bytes[start...]))
        bytes.removeLast(UndoStep.packedSize)
        return step
    }

    mutating func removeAll() { bytes.removeAll(keepingCapacity: true) }
}
