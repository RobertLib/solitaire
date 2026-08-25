//
//  GameState.swift
//  solitaire
//
//  Pure Klondike game state and rules. No UI dependencies.
//

import Foundation

enum PileID: Hashable, Codable, Sendable {
    case stock
    case waste
    case foundation(Int) // 0..3
    case tableau(Int)    // 0..6

    var isFoundation: Bool { if case .foundation = self { return true }; return false }
    var isTableau: Bool { if case .tableau = self { return true }; return false }
}

struct CardLocation: Equatable {
    var pile: PileID
    var index: Int
}

struct GameState: Codable, Equatable {
    var stock: [Card] = []
    var waste: [Card] = []
    var foundations: [[Card]] = Array(repeating: [], count: 4)
    var tableaus: [[Card]] = Array(repeating: [], count: 7)

    // MARK: - Access

    subscript(pile: PileID) -> [Card] {
        get {
            switch pile {
            case .stock: return stock
            case .waste: return waste
            case .foundation(let i): return foundations[i]
            case .tableau(let i): return tableaus[i]
            }
        }
        set {
            switch pile {
            case .stock: stock = newValue
            case .waste: waste = newValue
            case .foundation(let i): foundations[i] = newValue
            case .tableau(let i): tableaus[i] = newValue
            }
        }
    }

    static var allPiles: [PileID] {
        [.stock, .waste]
            + (0..<4).map { PileID.foundation($0) }
            + (0..<7).map { PileID.tableau($0) }
    }

    var isWon: Bool { foundations.allSatisfy { $0.count == 13 } }

    func location(of cardID: String) -> CardLocation? {
        for pile in Self.allPiles {
            if let index = self[pile].firstIndex(where: { $0.id == cardID }) {
                return CardLocation(pile: pile, index: index)
            }
        }
        return nil
    }

    func card(withID cardID: String) -> Card? {
        guard let loc = location(of: cardID) else { return nil }
        return self[loc.pile][loc.index]
    }

    // MARK: - Dealing

    /// Standard Klondike deal: seven tableau piles of 1...7 cards, top card
    /// face up, remaining 24 cards form the stock.
    static func deal(seed: UInt64) -> GameState {
        var deck = Card.orderedDeck
        var rng = SeededGenerator(seed: seed)
        deck.shuffle(using: &rng)

        var state = GameState()
        for row in 0..<7 {
            for column in row..<7 {
                var card = deck.removeLast()
                card.isFaceUp = (row == column)
                state.tableaus[column].append(card)
            }
        }
        state.stock = deck // all face down
        return state
    }

    /// The list of (row, column) deal steps in the order a human would deal
    /// them, used for the dealing animation.
    static var dealSteps: [(row: Int, column: Int)] {
        var steps: [(Int, Int)] = []
        for row in 0..<7 {
            for column in row..<7 { steps.append((row, column)) }
        }
        return steps
    }

    // MARK: - Rules

    func canPlace(_ card: Card, onTableau index: Int) -> Bool {
        guard let top = tableaus[index].last else { return card.rank == .king }
        return top.isFaceUp
            && top.rank.rawValue == card.rank.rawValue + 1
            && top.isRed != card.isRed
    }

    func canPlace(_ card: Card, onFoundation index: Int) -> Bool {
        guard let top = foundations[index].last else { return card.rank == .ace }
        return top.suit == card.suit && card.rank.rawValue == top.rank.rawValue + 1
    }

    /// Foundation index that would accept the card right now, if any.
    /// Prefers a foundation already holding the card's suit.
    func foundationTarget(for card: Card) -> Int? {
        for i in 0..<4 where !foundations[i].isEmpty && canPlace(card, onFoundation: i) {
            return i
        }
        for i in 0..<4 where foundations[i].isEmpty && card.rank == .ace {
            return i
        }
        return nil
    }

    /// The run of cards that moves together when the given card is dragged.
    /// Returns nil when the card cannot legally be picked up.
    func movableRun(startingAt cardID: String) -> (cards: [Card], location: CardLocation)? {
        guard let loc = location(of: cardID) else { return nil }
        let pile = self[loc.pile]
        let card = pile[loc.index]
        guard card.isFaceUp else { return nil }

        switch loc.pile {
        case .stock:
            return nil
        case .waste, .foundation:
            // Only the top card can leave these piles.
            guard loc.index == pile.count - 1 else { return nil }
            return ([card], loc)
        case .tableau:
            // Any face-up card moves along with everything stacked on it.
            // Runs are valid sequences by construction; verify rather than
            // assume, so a corrupt state can never be dragged around.
            let run = Array(pile[loc.index...])
            guard Self.isValidRun(run) else { return nil }
            return (run, loc)
        }
    }

    /// A run of face-up cards descending in alternating colours — the only
    /// shape that may be moved between tableau piles.
    static func isValidRun(_ run: [Card]) -> Bool {
        guard let first = run.first, first.isFaceUp else { return false }
        for (a, b) in zip(run, run.dropFirst()) {
            guard b.isFaceUp,
                  a.rank.rawValue == b.rank.rawValue + 1,
                  a.isRed != b.isRed
            else { return false }
        }
        return true
    }

    /// Whether a run taken from `source` may be dropped on the target pile.
    func canDrop(run: [Card], from source: PileID, on target: PileID) -> Bool {
        guard let first = run.first, source != target else { return false }
        switch target {
        case .tableau(let i):
            return canPlace(first, onTableau: i)
        case .foundation(let i):
            // Cards never travel between foundations.
            guard !source.isFoundation else { return false }
            return run.count == 1 && canPlace(first, onFoundation: i)
        case .stock, .waste:
            return false
        }
    }

    // MARK: - Mutations (rule-checked by callers)

    /// Removes the run from its pile and appends it to the target.
    /// Returns true when the removal exposed a face-down card that was flipped.
    @discardableResult
    mutating func applyMove(run: [Card], from source: PileID, to target: PileID) -> Bool {
        var sourcePile = self[source]
        sourcePile.removeLast(run.count)
        var flipped = false
        if source.isTableau, let last = sourcePile.indices.last, !sourcePile[last].isFaceUp {
            sourcePile[last].isFaceUp = true
            flipped = true
        }
        self[source] = sourcePile
        self[target] = self[target] + run
        return flipped
    }

    /// Deals up to `count` cards from the stock onto the waste.
    /// Returns the number of cards actually dealt.
    @discardableResult
    mutating func drawFromStock(count: Int) -> Int {
        let n = Swift.min(count, stock.count)
        guard n > 0 else { return 0 }
        for _ in 0..<n {
            var card = stock.removeLast()
            card.isFaceUp = true
            waste.append(card)
        }
        return n
    }

    /// Turns the waste back into the stock (one "pass" through the deck).
    /// Cards are drawn off the end, so the recycled waste goes underneath
    /// anything still left in the stock.
    mutating func recycleWaste() {
        let recycled = waste.reversed().map { card in
            var c = card
            c.isFaceUp = false
            return c
        }
        stock.insert(contentsOf: recycled, at: 0)
        waste = []
    }

    // MARK: - Derived info

    /// All tableau cards are face up and the stock/waste are empty — from this
    /// position the game is always winnable, so auto-finish can take over.
    var canAutoFinish: Bool { canAutoFinish(freeStockCycling: false) }

    /// Whether auto-finish can take over.
    ///
    /// With every tableau card face up and every column a descending run, the
    /// lowest-ranked card still in play is always on top of some pile — which
    /// means it can always go straight to its foundation. That makes the deal
    /// won for certain once the stock and waste are empty.
    ///
    /// The runs are checked rather than assumed. Face-up-everywhere implies
    /// them on any board the rules produced, and `isConsistent` turns away a
    /// save that says otherwise — but the guarantee this method makes is the
    /// one the wand bets 800 steps on, so it rests on what the board says
    /// rather than on where the board came from.
    ///
    /// `freeStockCycling` extends the same guarantee to a stock that still has
    /// cards in it: drawing one card at a time through an unlimited number of
    /// passes brings every stock card to the top of the waste eventually, so
    /// each card can be claimed the moment its foundation is ready. It must not
    /// be set for draw-3 (two out of every three cards stay unreachable while
    /// the grouping holds) or when the rules cap the number of passes.
    func canAutoFinish(freeStockCycling: Bool) -> Bool {
        guard !isWon else { return false }
        guard tableaus.allSatisfy({ pile in
            pile.allSatisfy(\.isFaceUp) && (pile.isEmpty || Self.isValidRun(pile))
        }) else { return false }
        return freeStockCycling || (stock.isEmpty && waste.isEmpty)
    }

    /// One step of the auto-finish loop.
    enum AutoFinishStep: Equatable {
        case play(cardID: String, foundation: Int)
        case draw
        case recycle
    }

    /// Next step for the auto-finish loop: the lowest card sitting on top of a
    /// tableau pile or the waste that fits a foundation, otherwise whatever
    /// turns the stock over to bring more cards within reach.
    func nextAutoFinishStep() -> AutoFinishStep? {
        var best: (cardID: String, foundation: Int, rank: Int)?
        for pile in tableaus + [waste] {
            guard let top = pile.last, let f = foundationTarget(for: top) else { continue }
            if best == nil || top.rank.rawValue < best!.rank {
                best = (top.id, f, top.rank.rawValue)
            }
        }
        if let b = best { return .play(cardID: b.cardID, foundation: b.foundation) }
        if !stock.isEmpty { return .draw }
        if !waste.isEmpty { return .recycle }
        return nil
    }

    /// Whether this is a board the rules could actually have produced.
    ///
    /// Nothing but a decoded save can be malformed, but a save is an opaque
    /// blob that may have been written by a different build or truncated on
    /// disk, and every routine here — dragging, hinting, auto-finish — assumes
    /// these invariants hold. Cheaper to check once than to reason about a
    /// board that cannot happen.
    var isConsistent: Bool {
        let all = allCards
        guard all.count == 52, Set(all.map(\.id)).count == 52 else { return false }
        guard stock.allSatisfy({ !$0.isFaceUp }), waste.allSatisfy(\.isFaceUp) else { return false }
        guard foundations.count == 4, tableaus.count == 7 else { return false }

        for pile in foundations {
            for (i, card) in pile.enumerated() {
                guard card.isFaceUp, card.rank.rawValue == i + 1, card.suit == pile[0].suit else { return false }
            }
        }
        for pile in tableaus {
            guard let firstFaceUp = pile.firstIndex(where: { $0.isFaceUp }) else {
                // A column with cards in it always shows its top one: the deal
                // turns that card over, and so does every move that exposes a
                // new one. A column of nothing but face-down cards is a shape
                // the rules cannot reach — and one the hint list would offer
                // moves from that no move can then make.
                guard pile.isEmpty else { return false }
                continue
            }
            // Face-down cards only ever sit underneath, and the face-up part is
            // a single descending run of alternating colours.
            guard Self.isValidRun(Array(pile[firstFaceUp...])) else { return false }
        }
        return true
    }

    /// Every card in play, used by the view layer to render with stable identity.
    var allCards: [Card] {
        var cards = stock + waste
        for pile in foundations { cards += pile }
        for pile in tableaus { cards += pile }
        return cards
    }

    /// Is there anything left to do? Taking a card back off a foundation is
    /// deliberately not counted — it undoes progress rather than making any.
    func hasLegalMove(allowRecycle: Bool) -> Bool {
        if !stock.isEmpty || allowRecycle { return true }

        if let top = waste.last {
            if foundationTarget(for: top) != nil { return true }
            if (0..<7).contains(where: { canPlace(top, onTableau: $0) }) { return true }
        }

        for (i, pile) in tableaus.enumerated() {
            if let top = pile.last, top.isFaceUp, foundationTarget(for: top) != nil { return true }
            guard let firstFaceUp = pile.firstIndex(where: { $0.isFaceUp }) else { continue }
            for start in firstFaceUp..<pile.count {
                let head = pile[start]
                for j in 0..<7 where j != i && canPlace(head, onTableau: j) {
                    // Relocating a whole column into another empty one achieves
                    // nothing, so it does not count as a move.
                    if !tableaus[j].isEmpty || start > 0 { return true }
                }
            }
        }
        return false
    }
}
