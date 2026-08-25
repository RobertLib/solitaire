//
//  EngineTests.swift
//  solitaire
//
//  Assertions for the game logic that needs no running app.
//
//  Two harnesses drive this one file, so neither can drift from the other:
//  `./Tests/run.sh` compiles it against the sources directly for a check that
//  needs nothing but a toolchain, and the `solitaireTests` target runs it under
//  ⌘U alongside the tests that do need an app to run in.
//

import Foundation
import CoreGraphics // the layout suite measures in CGSize/CGPoint

// run.sh compiles this file alongside the sources it tests, so there is nothing
// to import there. The Xcode target compiles it against the built app instead,
// and has to reach inside it.
#if canImport(solitaire)
@testable import solitaire
#endif

// The whole harness runs on one actor so the failure count is shared state the
// compiler can vouch for — the sources under test build in Swift 6 mode too.
@MainActor
struct EngineTests {
    private(set) static var failures: [String] = []

    static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append(message)
            print("FAIL: \(message)")
        }
    }

    /// Runs every suite and returns what failed — empty means all passed.
    ///
    /// `fuzzDeals` is how many deals the fuzz plays out. run.sh compiles this
    /// optimised and takes the full sweep in about forty seconds; inside the
    /// app module Xcode builds it at -Onone, where the same sweep costs three
    /// minutes and nobody would press ⌘U twice. That run takes a slice.
    @discardableResult
    static func runAll(fuzzDeals: Int = 400) -> [String] {
        failures = []
        dealing()
        rules()
        runs()
        stockAndWaste()
        deadEnds()
        scoring()
        autoFinish()
        autoFinishThroughStock()
        consistency()
        suggestions()
        savedGames()
        packing()
        undoHistory()
        timeFormatting()
        layout()
        preferences()
        fuzz(deals: fuzzDeals)
        return failures
    }

    // MARK: - Invariants every reachable state must satisfy

    static func assertInvariants(_ s: GameState, _ context: String) {
        // The engine's own validator must agree with the checks below on every
        // state the tests reach, so a save can be trusted on the strength of it.
        check(s.isConsistent, "\(context): isConsistent disagrees with the invariants")
        let all = s.allCards
        check(all.count == 52, "\(context): card count \(all.count)")
        check(Set(all.map(\.id)).count == 52, "\(context): duplicate or missing cards")
        check(s.stock.allSatisfy { !$0.isFaceUp }, "\(context): face-up card in the stock")
        check(s.waste.allSatisfy(\.isFaceUp), "\(context): face-down card on the waste")

        for (f, pile) in s.foundations.enumerated() {
            for (i, card) in pile.enumerated() {
                check(card.rank.rawValue == i + 1, "\(context): foundation \(f) out of order")
                check(card.suit == pile[0].suit, "\(context): foundation \(f) mixes suits")
                check(card.isFaceUp, "\(context): foundation \(f) holds a face-down card")
            }
        }
        for (t, pile) in s.tableaus.enumerated() {
            var sawFaceUp = false
            for (i, card) in pile.enumerated() {
                if card.isFaceUp { sawFaceUp = true }
                else { check(!sawFaceUp, "\(context): tableau \(t) buries a face-up card") }
                if i > 0, card.isFaceUp, pile[i - 1].isFaceUp {
                    let above = pile[i - 1]
                    check(above.rank.rawValue == card.rank.rawValue + 1 && above.isRed != card.isRed,
                          "\(context): tableau \(t) invalid run \(above.id) -> \(card.id)")
                }
            }
        }
    }

    // MARK: - Dealing

    static func dealing() {
        let a = GameState.deal(seed: 12345)
        check(a == GameState.deal(seed: 12345), "the same seed must deal the same game")
        check(a != GameState.deal(seed: 12346), "different seeds dealt an identical game")
        check(a.stock.count == 24, "stock should hold 24 cards, got \(a.stock.count)")
        check(a.tableaus.map(\.count) == [1, 2, 3, 4, 5, 6, 7], "tableau sizes \(a.tableaus.map(\.count))")
        check(a.tableaus.allSatisfy { $0.last?.isFaceUp == true }, "every tableau top starts face up")
        check(a.tableaus.reduce(0) { $0 + $1.filter(\.isFaceUp).count } == 7, "exactly 7 cards start face up")
        check(GameState.dealSteps.count == 28, "28 deal steps, got \(GameState.dealSteps.count)")
        check(!a.isWon, "a fresh deal is not won")
        assertInvariants(a, "fresh deal")
    }

    // MARK: - Placement rules

    static func rules() {
        var s = GameState()
        check(s.canPlace(Card(suit: .spades, rank: .king), onTableau: 0), "a king goes on an empty column")
        check(!s.canPlace(Card(suit: .spades, rank: .queen), onTableau: 0), "only kings go on an empty column")

        s.tableaus[0] = [Card(suit: .spades, rank: .king, isFaceUp: true)]
        check(s.canPlace(Card(suit: .hearts, rank: .queen), onTableau: 0), "red queen on a black king")
        check(!s.canPlace(Card(suit: .clubs, rank: .queen), onTableau: 0), "colours must alternate")
        check(!s.canPlace(Card(suit: .hearts, rank: .jack), onTableau: 0), "ranks must descend by one")

        s.tableaus[1] = [Card(suit: .spades, rank: .king, isFaceUp: false)]
        check(!s.canPlace(Card(suit: .hearts, rank: .queen), onTableau: 1), "nothing stacks on a face-down card")

        check(s.canPlace(Card(suit: .clubs, rank: .ace), onFoundation: 0), "an ace opens a foundation")
        check(!s.canPlace(Card(suit: .clubs, rank: .two), onFoundation: 0), "a foundation starts with an ace")
        s.foundations[0] = [Card(suit: .clubs, rank: .ace, isFaceUp: true)]
        check(s.canPlace(Card(suit: .clubs, rank: .two), onFoundation: 0), "2♣ follows A♣")
        check(!s.canPlace(Card(suit: .spades, rank: .two), onFoundation: 0), "foundations keep one suit")
        check(s.foundationTarget(for: Card(suit: .clubs, rank: .two)) == 0, "foundationTarget prefers the matching suit")
        check(s.foundationTarget(for: Card(suit: .spades, rank: .three)) == nil, "no foundation accepts 3♠ yet")

        // Drops are judged against the pile the run came from.
        let two = Card(suit: .clubs, rank: .two, isFaceUp: true)
        check(!s.canDrop(run: [two, Card(suit: .hearts, rank: .ace, isFaceUp: true)], from: .waste, on: .foundation(0)),
              "a foundation takes a single card at a time")
        check(!s.canDrop(run: [two], from: .waste, on: .waste), "cards cannot be dropped on the waste")
        check(!s.canDrop(run: [two], from: .waste, on: .stock), "cards cannot be dropped on the stock")
        check(s.canDrop(run: [two], from: .waste, on: .foundation(0)), "2♣ drops onto A♣")

        var hop = GameState()
        hop.foundations[0] = [Card(suit: .spades, rank: .ace, isFaceUp: true)]
        let ace = Card(suit: .spades, rank: .ace, isFaceUp: true)
        check(!hop.canDrop(run: [ace], from: .foundation(0), on: .foundation(1)),
              "cards must not hop between foundations")
        check(!hop.canDrop(run: [ace], from: .foundation(0), on: .foundation(0)),
              "a pile is not a target for itself")
    }

    // MARK: - Movable runs

    static func runs() {
        var m = GameState()
        m.tableaus[0] = [
            Card(suit: .spades, rank: .king, isFaceUp: false),
            Card(suit: .hearts, rank: .queen, isFaceUp: true),
            Card(suit: .clubs, rank: .jack, isFaceUp: true),
        ]
        check(m.movableRun(startingAt: "spades-13") == nil, "a face-down card cannot be picked up")
        check(m.movableRun(startingAt: "hearts-12")?.cards.count == 2, "a run carries the cards stacked on it")
        check(m.movableRun(startingAt: "clubs-11")?.cards.count == 1, "the top card moves alone")
        check(m.movableRun(startingAt: "hearts-1") == nil, "a card that is not in play has no run")

        m.waste = [Card(suit: .clubs, rank: .three, isFaceUp: true), Card(suit: .clubs, rank: .four, isFaceUp: true)]
        check(m.movableRun(startingAt: "clubs-3") == nil, "only the top waste card is movable")
        check(m.movableRun(startingAt: "clubs-4")?.cards.count == 1, "the top waste card is movable")

        m.stock = [Card(suit: .diamonds, rank: .five)]
        check(m.movableRun(startingAt: "diamonds-5") == nil, "stock cards are not movable")

        // A pile that is not a descending, alternating run cannot be dragged.
        var corrupt = GameState()
        corrupt.tableaus[0] = [
            Card(suit: .spades, rank: .king, isFaceUp: true),
            Card(suit: .clubs, rank: .four, isFaceUp: true),
        ]
        check(corrupt.movableRun(startingAt: "spades-13") == nil, "an invalid run must not be movable")
        check(corrupt.movableRun(startingAt: "clubs-4")?.cards.count == 1, "its top card still moves alone")

        check(GameState.isValidRun([Card(suit: .spades, rank: .king, isFaceUp: true),
                                    Card(suit: .hearts, rank: .queen, isFaceUp: true)]), "K♠ Q♥ is a valid run")
        check(!GameState.isValidRun([Card(suit: .spades, rank: .king, isFaceUp: true),
                                     Card(suit: .clubs, rank: .queen, isFaceUp: true)]), "same colour is not a run")
        check(!GameState.isValidRun([Card(suit: .spades, rank: .king, isFaceUp: false)]), "a face-down card is no run")
        check(!GameState.isValidRun([]), "an empty run is not valid")
    }

    // MARK: - Stock, waste and recycling

    static func stockAndWaste() {
        var d = GameState.deal(seed: 7)
        check(d.drawFromStock(count: 3) == 3, "draw three")
        check(d.waste.count == 3 && d.waste.allSatisfy(\.isFaceUp), "drawn cards land face up on the waste")

        while !d.stock.isEmpty { _ = d.drawFromStock(count: 5) }
        check(d.waste.count == 24, "the whole stock ends up on the waste")
        check(d.drawFromStock(count: 3) == 0, "drawing from an empty stock does nothing")
        assertInvariants(d, "stock exhausted")

        let order = d.waste.map(\.id)
        d.recycleWaste()
        check(d.waste.isEmpty && d.stock.count == 24, "recycling moves the waste back")
        check(d.stock.map(\.id) == order.reversed(), "recycling preserves the deck order")
        check(d.stock.allSatisfy { !$0.isFaceUp }, "recycled cards go back face down")
        check(d.drawFromStock(count: 5) == 5 && d.stock.count == 19, "the recycled stock can be drawn again")

        // Recycling must never swallow cards still sitting in the stock.
        var leftovers = GameState()
        leftovers.stock = [Card(suit: .spades, rank: .two), Card(suit: .spades, rank: .three)]
        leftovers.waste = [Card(suit: .hearts, rank: .four, isFaceUp: true)]
        leftovers.recycleWaste()
        check(leftovers.stock.count == 3, "recycling kept every card, got \(leftovers.stock.count)")
        check(leftovers.stock.last?.id == "spades-3", "cards left in the stock stay on top")
        check(leftovers.stock.first?.id == "hearts-4", "the recycled waste goes underneath")
    }

    // MARK: - Dead ends

    /// Seven columns holding the whole deck: the given face-up tops, everything
    /// else buried face down underneath. `excluding` cards are left out entirely
    /// (they belong on a foundation instead).
    static func board(tops: [Card], excluding: [Card] = []) -> GameState {
        let spoken = Set(tops.map(\.id)).union(excluding.map(\.id))
        var buried = Card.orderedDeck.filter { !spoken.contains($0.id) }
        var state = GameState()
        for column in 0..<7 {
            // Spread the buried cards evenly; the last column takes the rest.
            let take = column == 6 ? buried.count : buried.count / (7 - column)
            state.tableaus[column] = (0..<take).map { _ in buried.removeLast() } + [tops[column]]
        }
        return state
    }

    static func deadEnds() {
        check(GameState.deal(seed: 3).hasLegalMove(allowRecycle: false), "a fresh deal always has a move")

        // Nothing to draw, nothing playable: the classic dead deal.
        let dead = board(tops: [
            Card(suit: .spades, rank: .five, isFaceUp: true),
            Card(suit: .hearts, rank: .five, isFaceUp: true),
            Card(suit: .diamonds, rank: .five, isFaceUp: true),
            Card(suit: .clubs, rank: .five, isFaceUp: true),
            Card(suit: .spades, rank: .nine, isFaceUp: true),
            Card(suit: .hearts, rank: .nine, isFaceUp: true),
            Card(suit: .diamonds, rank: .nine, isFaceUp: true),
        ])
        assertInvariants(dead, "dead deal")
        check(!dead.hasLegalMove(allowRecycle: false), "this deal has no moves left")
        check(dead.hasLegalMove(allowRecycle: true), "an available recycle counts as a move")

        var withStock = dead
        withStock.stock = [Card(suit: .spades, rank: .two)]
        check(withStock.hasLegalMove(allowRecycle: false), "a non-empty stock always leaves a move")

        // A playable waste card revives the position.
        var withWaste = dead
        withWaste.tableaus[6].removeLast()
        withWaste.waste = [Card(suit: .hearts, rank: .nine, isFaceUp: true)]
        withWaste.tableaus[6].append(Card(suit: .spades, rank: .ten, isFaceUp: true))
        check(withWaste.hasLegalMove(allowRecycle: false), "9♥ still plays onto 10♠")

        // Taking a card back off a foundation is not progress, so it does not
        // count: here 5♥ would fit both black sixes and nothing else can move.
        let hearts = Rank.allCases.prefix(5).map { Card(suit: .hearts, rank: $0, isFaceUp: true) }
        var rollback = board(
            tops: [
                Card(suit: .spades, rank: .six, isFaceUp: true),
                Card(suit: .clubs, rank: .six, isFaceUp: true),
                Card(suit: .spades, rank: .nine, isFaceUp: true),
                Card(suit: .hearts, rank: .nine, isFaceUp: true),
                Card(suit: .diamonds, rank: .nine, isFaceUp: true),
                Card(suit: .spades, rank: .two, isFaceUp: true),
                Card(suit: .clubs, rank: .two, isFaceUp: true),
            ],
            excluding: hearts
        )
        rollback.foundations[0] = hearts
        assertInvariants(rollback, "foundation rollback")
        check(rollback.canPlace(hearts[4], onTableau: 0), "5♥ would fit on 6♠")
        check(!rollback.hasLegalMove(allowRecycle: false), "pulling 5♥ back off a foundation is not a move")

        // Relocating a lone king from one empty column to another is not a move.
        var kings = GameState()
        kings.tableaus[0] = [Card(suit: .spades, rank: .king, isFaceUp: true)]
        check(!kings.hasLegalMove(allowRecycle: false), "shuffling a lone king between columns is not a move")
        kings.tableaus[0].insert(Card(suit: .hearts, rank: .four), at: 0)
        check(kings.hasLegalMove(allowRecycle: false), "moving that king now uncovers a card")
    }

    // MARK: - Scoring

    static func scoring() {
        var std = ScoreKeeper(mode: .standard)
        check(std.points == 0, "standard scoring starts at zero")
        std.apply(.foundationToTableau)
        check(std.points == 0, "standard scoring never goes negative")
        std.apply(.tableauToFoundation)
        std.apply(.tableauToFoundation)
        check(std.points == 20, "two foundation moves score 20, got \(std.points)")
        std.apply(.wasteToTableau)
        std.apply(.turnOverTableauCard)
        check(std.points == 30, "waste play and a turned card score 5 each, got \(std.points)")
        // Drawing three shows a third of the deck per pass, so the rules give
        // the player three of them before charging for going round again.
        std.apply(.recycleWaste(drawCount: 3, pass: 2))
        std.apply(.recycleWaste(drawCount: 3, pass: 3))
        check(std.points == 30, "the second and third draw-3 passes are free, got \(std.points)")
        std.apply(.recycleWaste(drawCount: 3, pass: 4))
        check(std.points == 10, "the fourth draw-3 pass costs 20, got \(std.points)")
        // Drawing one shows the whole deck in a single pass, so every pass
        // after the first is going round again.
        std.apply(.recycleWaste(drawCount: 1, pass: 2))
        check(std.points == 0, "a draw-1 recycle costs 100 and clamps at zero, got \(std.points)")

        var vegasRecycle = ScoreKeeper(mode: .vegas)
        vegasRecycle.apply(.recycleWaste(drawCount: 1, pass: 2))
        check(vegasRecycle.points == -52,
              "Vegas charges nothing for turning the deck over, got \(vegasRecycle.points)")

        // Undo restores the score from before a move and then charges the
        // ticks the clock ran up since, so a batch has to land exactly where
        // the same ticks applied one at a time would have.
        var batched = ScoreKeeper(mode: .standard)
        var singly = ScoreKeeper(mode: .standard)
        for _ in 0..<10 { batched.apply(.tableauToFoundation); singly.apply(.tableauToFoundation) }
        batched.applyTimePenalty(times: 7)
        for _ in 0..<7 { singly.applyTimePenalty() }
        check(batched.points == 86 && batched.points == singly.points,
              "seven ticks at once cost 14, got \(batched.points) vs \(singly.points)")
        batched.applyTimePenalty(times: 100)
        check(batched.points == 0, "a batch of ticks clamps at zero, got \(batched.points)")
        batched.applyTimePenalty(times: 0)
        check(batched.points == 0, "an empty batch charges nothing")
        var negativeBatch = ScoreKeeper(mode: .standard)
        negativeBatch.apply(.tableauToFoundation)
        negativeBatch.applyTimePenalty(times: -3)
        check(negativeBatch.points == 10, "a negative batch never pays points out")

        var vegas = ScoreKeeper(mode: .vegas)
        check(vegas.points == -52, "vegas buys the deck for $52")
        for _ in 0..<52 { vegas.apply(.tableauToFoundation) }
        check(vegas.points == 208, "a perfect vegas game wins $208, got \(vegas.points)")
        vegas.apply(.foundationToTableau)
        check(vegas.points == 203, "taking a card back costs $5")
        vegas.applyTimePenalty()
        check(vegas.points == 203, "vegas has no time penalty")

        var none = ScoreKeeper(mode: .none)
        none.apply(.tableauToFoundation)
        none.applyTimePenalty()
        check(none.points == 0, "scoreless mode stays at zero")

        check(ScoreKeeper.timeBonus(elapsedSeconds: 0) == 0, "no bonus, and no divide by zero, at 0 s")
        check(ScoreKeeper.timeBonus(elapsedSeconds: 30) == 0, "no bonus for a 30 s game")
        check(ScoreKeeper.timeBonus(elapsedSeconds: 100) == 7000, "700000/100 = 7000")
        check(ScoreKeeper.allowedPasses(mode: .vegas, drawCount: 1) == 1, "vegas draw-1 allows one pass")
        check(ScoreKeeper.allowedPasses(mode: .vegas, drawCount: 3) == 3, "vegas draw-3 allows three passes")
        check(ScoreKeeper.allowedPasses(mode: .standard, drawCount: 1) == nil, "standard passes are unlimited")
        check(ScoreKeeper.formatVegas(-52) == "-$52", "negative vegas amounts read as -$52")
        check(ScoreKeeper.formatVegas(5) == "$5", "positive vegas amounts read as $5")
    }

    // MARK: - Auto-finish

    static func autoFinish() {
        var s = GameState()
        for (f, suit) in Suit.allCases.enumerated() {
            s.foundations[f] = Rank.allCases.prefix(9).map { Card(suit: suit, rank: $0, isFaceUp: true) }
        }
        let runs: [[Card]] = [
            [Card(suit: .spades, rank: .king), Card(suit: .hearts, rank: .queen),
             Card(suit: .clubs, rank: .jack), Card(suit: .diamonds, rank: .ten)],
            [Card(suit: .hearts, rank: .king), Card(suit: .spades, rank: .queen),
             Card(suit: .diamonds, rank: .jack), Card(suit: .clubs, rank: .ten)],
            [Card(suit: .diamonds, rank: .king), Card(suit: .clubs, rank: .queen),
             Card(suit: .hearts, rank: .jack), Card(suit: .spades, rank: .ten)],
            [Card(suit: .clubs, rank: .king), Card(suit: .diamonds, rank: .queen),
             Card(suit: .spades, rank: .jack), Card(suit: .hearts, rank: .ten)],
        ]
        for (i, run) in runs.enumerated() {
            s.tableaus[i] = run.map { card in
                var c = card
                c.isFaceUp = true
                return c
            }
        }
        check(s.canAutoFinish, "an all-face-up board with an empty stock can auto-finish")
        assertInvariants(s, "auto-finish start")

        var steps = 0
        while case .play(let cardID, let foundation)? = s.nextAutoFinishStep(), steps < 100 {
            guard let (run, loc) = s.movableRun(startingAt: cardID) else { break }
            s.applyMove(run: run, from: loc.pile, to: .foundation(foundation))
            steps += 1
        }
        check(s.isWon, "auto-finish must reach a win (stopped after \(steps) steps)")
        check(!s.canAutoFinish, "a won game offers no auto-finish")

        var withStock = s
        withStock.stock = [Card(suit: .spades, rank: .two)]
        check(!withStock.canAutoFinish, "cards left in the stock block auto-finish")

        // Face up is not on its own enough: the guarantee rests on the columns
        // being descending runs, so a board that only looks the part — every
        // card face up, none of them stacked in order — must be turned away
        // rather than sending the wand off to cycle the deck for 800 steps.
        var faceUpButNotRuns = GameState()
        var deck = Card.orderedDeck.map { card in
            var c = card
            c.isFaceUp = true
            return c
        }
        for column in 0..<7 {
            let depth = column < 3 ? 8 : 7
            faceUpButNotRuns.tableaus[column] = (0..<depth).map { _ in deck.removeLast() }
        }
        check(!GameState.isValidRun(faceUpButNotRuns.tableaus[0]),
              "the fixture has to be the shape the check is for")
        check(!faceUpButNotRuns.canAutoFinish(freeStockCycling: false),
              "columns that are not runs block auto-finish")
        check(!faceUpButNotRuns.canAutoFinish(freeStockCycling: true),
              "and a cyclable stock does not excuse them")
    }

    // MARK: - Auto-finish while the stock can still be cycled

    static func autoFinishThroughStock() {
        // Every tableau card face up, but eight cards are still in the stock
        // and the waste. Cycling a draw-1 deck reaches all of them, so the
        // deal is already won; draw-3 and capped passes are not.
        var s = GameState()
        for (f, suit) in Suit.allCases.enumerated() {
            s.foundations[f] = Rank.allCases.prefix(11).map { Card(suit: suit, rank: $0, isFaceUp: true) }
        }
        s.tableaus[0] = [Card(suit: .spades, rank: .queen, isFaceUp: true)]
        s.tableaus[1] = [Card(suit: .hearts, rank: .queen, isFaceUp: true)]
        s.stock = [Card(suit: .diamonds, rank: .king), Card(suit: .clubs, rank: .queen),
                   Card(suit: .spades, rank: .king), Card(suit: .diamonds, rank: .queen)]
        s.waste = [Card(suit: .hearts, rank: .king, isFaceUp: true),
                   Card(suit: .clubs, rank: .king, isFaceUp: true)]
        assertInvariants(s, "auto-finish through the stock")

        check(!s.canAutoFinish, "the plain condition still requires an empty stock")
        check(s.canAutoFinish(freeStockCycling: true), "free cycling reaches the stock cards")
        check(!s.canAutoFinish(freeStockCycling: false), "without free cycling the stock blocks it")

        var buried = s
        buried.tableaus[0].insert(Card(suit: .clubs, rank: .two), at: 0)
        check(!buried.canAutoFinish(freeStockCycling: true),
              "a face-down tableau card blocks auto-finish however the stock behaves")

        // Play it out the way the view model does.
        var steps = 0
        while !s.isWon, steps < 200 {
            steps += 1
            switch s.nextAutoFinishStep() {
            case .play(let cardID, let foundation):
                guard let (run, loc) = s.movableRun(startingAt: cardID) else { steps = 200; break }
                s.applyMove(run: run, from: loc.pile, to: .foundation(foundation))
            case .draw:
                check(s.drawFromStock(count: 1) == 1, "a draw step must actually draw")
            case .recycle:
                check(!s.waste.isEmpty, "a recycle step needs a waste pile")
                s.recycleWaste()
            case nil:
                steps = 200
            }
            assertInvariants(s, "auto-finish step \(steps)")
        }
        check(s.isWon, "auto-finish through the stock must reach a win (stopped after \(steps) steps)")

        // The step list is exhausted exactly when the game is over.
        check(s.nextAutoFinishStep() == nil, "a won game offers no further step")
    }

    // MARK: - Board validation used before trusting a decoded save

    static func consistency() {
        check(GameState.deal(seed: 9).isConsistent, "a fresh deal is consistent")
        check(GameState().isConsistent == false, "an empty board is not a 52-card deal")

        var won = GameState()
        for (f, suit) in Suit.allCases.enumerated() {
            won.foundations[f] = Rank.allCases.map { Card(suit: suit, rank: $0, isFaceUp: true) }
        }
        check(won.isConsistent, "a completed board is consistent")

        var duplicated = GameState.deal(seed: 9)
        duplicated.tableaus[0][0] = duplicated.tableaus[1][0]
        check(!duplicated.isConsistent, "a duplicated card is caught")

        var faceUpStock = GameState.deal(seed: 9)
        faceUpStock.stock[0].isFaceUp = true
        check(!faceUpStock.isConsistent, "a face-up card in the stock is caught")

        var buriedFaceUp = GameState.deal(seed: 9)
        buriedFaceUp.tableaus[6][0].isFaceUp = true
        check(!buriedFaceUp.isConsistent, "a face-up card buried under face-down cards is caught")

        var brokenRun = GameState.deal(seed: 9)
        let top = brokenRun.tableaus[6].removeLast()
        brokenRun.tableaus[6].append(Card(suit: top.suit, rank: .two, isFaceUp: true))
        brokenRun.tableaus[6].append(Card(suit: top.suit, rank: .nine, isFaceUp: true))
        check(!brokenRun.isConsistent, "a tableau that is not a descending run is caught")

        var wrongFoundation = GameState.deal(seed: 9)
        let moved = wrongFoundation.tableaus[0].removeLast()
        wrongFoundation.foundations[0] = [Card(suit: moved.suit, rank: .five, isFaceUp: true)]
        check(!wrongFoundation.isConsistent, "a foundation not starting at the ace is caught")

        // The deal turns the top card of every column over and so does every
        // move that exposes one, so a column of nothing but face-down cards is
        // a shape the rules cannot reach.
        var coveredColumn = GameState.deal(seed: 9)
        coveredColumn.tableaus[0][0].isFaceUp = false
        check(!coveredColumn.isConsistent, "a column showing nothing is caught")

        // ...and were one to arrive anyway, the hint list must not offer a move
        // from a card that cannot be picked up. `hasLegalMove` already asks for
        // a face-up top; the two have to give the same answer.
        var covered = GameState()
        covered.tableaus[0] = [Card(suit: .spades, rank: .ace, isFaceUp: false)]
        check(covered.movableRun(startingAt: Card(suit: .spades, rank: .ace).id) == nil,
              "a face-down card cannot be picked up")
        let offered = MoveAdvisor.candidates(for: covered, canRecycle: false)
        check(offered.isEmpty, "a covered ace is not a suggestion, got \(offered.count)")
        check(!covered.hasLegalMove(allowRecycle: false), "and it is not a legal move either")
    }

    // MARK: - Suggested moves

    static func suggestions() {
        // Every suggestion has to be a move the rules would actually allow.
        var deal = GameState.deal(seed: 31)
        deal.drawFromStock(count: 1)
        let offered = MoveAdvisor.candidates(for: deal, canRecycle: false)
        check(!offered.isEmpty, "a fresh deal always has something to suggest")
        for c in offered {
            guard let target = c.target else {
                check(c.source == .stock && c.message != nil,
                      "only the stock is suggested without a target, and it explains itself")
                continue
            }
            guard let head = c.cardIDs.first,
                  let (run, loc) = deal.movableRun(startingAt: head) else {
                check(false, "suggested \(c.cardIDs), which cannot even be picked up")
                continue
            }
            check(loc.pile == c.source, "a suggestion must name the pile the run is really on")
            check(run.map(\.id) == c.cardIDs, "a suggestion must carry the whole run")
            check(deal.canDrop(run: run, from: loc.pile, on: target), "suggested an illegal drop onto \(target)")
            check(!loc.pile.isFoundation, "a suggestion never takes a card back off a foundation")
        }
        let keys = offered.map { "\($0.cardIDs.first ?? "-")->\(String(describing: $0.target))" }
        check(Set(keys).count == keys.count, "the hint cycle must not offer the same move twice")

        // Best first: an ace beats every other move on the board.
        let aces = board(tops: [
            Card(suit: .spades, rank: .ace, isFaceUp: true),
            Card(suit: .hearts, rank: .five, isFaceUp: true),
            Card(suit: .diamonds, rank: .five, isFaceUp: true),
            Card(suit: .clubs, rank: .five, isFaceUp: true),
            Card(suit: .spades, rank: .nine, isFaceUp: true),
            Card(suit: .hearts, rank: .nine, isFaceUp: true),
            Card(suit: .diamonds, rank: .nine, isFaceUp: true),
        ])
        let best = MoveAdvisor.candidates(for: aces, canRecycle: false).first
        check(best?.cardIDs == ["spades-1"] && best?.target == .foundation(0),
              "an ace goes to a foundation before anything else is considered")

        // Turning the deck over is a suggestion in its own right.
        var stocked = GameState.deal(seed: 12)
        check(MoveAdvisor.candidates(for: stocked, canRecycle: false).contains { $0.source == .stock },
              "a stock with cards in it is always worth suggesting")
        while stocked.drawFromStock(count: 1) > 0 {}
        check(!MoveAdvisor.candidates(for: stocked, canRecycle: false).contains { $0.source == .stock },
              "an empty stock that may not be recycled is not suggested")
        check(MoveAdvisor.candidates(for: stocked, canRecycle: true).contains { $0.source == .stock },
              "the recycle is suggested once the rules allow it")

        // A dead deal must offer nothing, or the banner and the hint disagree.
        let dead = board(tops: [
            Card(suit: .spades, rank: .five, isFaceUp: true),
            Card(suit: .hearts, rank: .five, isFaceUp: true),
            Card(suit: .diamonds, rank: .five, isFaceUp: true),
            Card(suit: .clubs, rank: .five, isFaceUp: true),
            Card(suit: .spades, rank: .nine, isFaceUp: true),
            Card(suit: .hearts, rank: .nine, isFaceUp: true),
            Card(suit: .diamonds, rank: .nine, isFaceUp: true),
        ])
        check(MoveAdvisor.candidates(for: dead, canRecycle: false).isEmpty,
              "a dead deal offers no suggestion, exactly as the banner claims")
        check(!MoveAdvisor.candidates(for: dead, canRecycle: true).isEmpty,
              "an available recycle is still a suggestion on an otherwise dead deal")

        // Where a tapped card goes.
        var tap = GameState()
        tap.tableaus[0] = [Card(suit: .spades, rank: .king, isFaceUp: true)]
        let queen = Card(suit: .hearts, rank: .queen, isFaceUp: true)
        tap.waste = [queen]
        check(MoveAdvisor.bestTableauTarget(for: [queen], from: CardLocation(pile: .waste, index: 0), in: tap) == .tableau(0),
              "a queen lands on the black king")
        check(MoveAdvisor.bestTableauTarget(for: [Card(suit: .clubs, rank: .queen, isFaceUp: true)],
                                            from: CardLocation(pile: .waste, index: 0), in: tap) == nil,
              "a queen of the wrong colour has nowhere to go")

        let lone = tap.tableaus[0]
        check(MoveAdvisor.bestTableauTarget(for: lone, from: CardLocation(pile: .tableau(0), index: 0), in: tap) == nil,
              "a lone king does not shuttle between empty columns")
        tap.tableaus[0].insert(Card(suit: .hearts, rank: .four), at: 0)
        check(MoveAdvisor.bestTableauTarget(for: lone, from: CardLocation(pile: .tableau(0), index: 1), in: tap) == .tableau(1),
              "the same king moves once there is a card underneath to turn over")
    }

    // MARK: - Saved games

    static func savedGames() {
        var mid = GameState.deal(seed: 4242)
        mid.drawFromStock(count: 3)
        let saved = SavedGame(
            state: mid, seed: 4242, drawCount: 3, scoring: ScoreKeeper(mode: .vegas),
            moves: 7, elapsedSeconds: 63, recyclesUsed: 1, hasStarted: true, vegasSettled: false
        )
        check(saved.isResumable, "a game in progress is worth resuming")
        guard let data = saved.encoded() else {
            check(false, "a saved game must encode")
            return
        }
        check(SavedGame.decode(data) == saved, "a saved game survives the round trip unchanged")

        // Anything that is not a game this build can play must come back nil, so
        // the caller throws the blob away instead of failing on it every launch.
        check(SavedGame.decode(Data()) == nil, "empty data is not a saved game")
        check(SavedGame.decode(Data("not json at all".utf8)) == nil, "garbage is not a saved game")
        check(SavedGame.decode(data.prefix(data.count / 2)) == nil, "a truncated blob is rejected")

        func rejected(_ label: String, _ change: (inout SavedGame) -> Void) {
            var copy = saved
            change(&copy)
            check(!copy.isResumable, "\(label) is not resumable")
            check(copy.encoded().flatMap(SavedGame.decode) == nil, "\(label) survived the decoder")
        }
        rejected("a board with a face-up card in the stock") { $0.state.stock[0].isFaceUp = true }
        rejected("a board missing a card") { $0.state.tableaus[0].removeAll() }
        rejected("a board with a duplicated card") { $0.state.tableaus[0][0] = $0.state.tableaus[1][0] }
        rejected("a deal count no rule produces") { $0.drawCount = 2 }
        rejected("a negative move count") { $0.moves = -1 }
        rejected("a negative clock") { $0.elapsedSeconds = -1 }
        rejected("a negative recycle count") { $0.recyclesUsed = -1 }

        var won = GameState()
        for (f, suit) in Suit.allCases.enumerated() {
            won.foundations[f] = Rank.allCases.map { Card(suit: suit, rank: $0, isFaceUp: true) }
        }
        rejected("a game that was already won") { $0.state = won }

        // The flag added after the first release is optional precisely because
        // the encoder leaves it out — that is the shape an older build wrote.
        var legacy = saved
        legacy.vegasSettled = nil
        guard let legacyData = legacy.encoded() else {
            check(false, "the legacy shape must encode")
            return
        }
        check(!String(decoding: legacyData, as: UTF8.self).contains("vegasSettled"),
              "an unset flag is written as no key at all")
        check(SavedGame.decode(legacyData) == legacy, "a save from before the flag existed still loads")
    }

    // MARK: - The compact board format the undo history is written in

    static func packing() {
        // Every board play can reach survives the round trip unchanged.
        var rng = SeededGenerator(seed: 4242)
        for game in 0..<40 {
            var g = GameState.deal(seed: UInt64(game + 1))
            for _ in 0..<60 {
                let data = g.packed
                check(data.count == 65, "a packed board should be 65 bytes, got \(data.count)")
                guard let back = GameState(packed: data) else {
                    check(false, "a packed board failed to unpack")
                    break
                }
                check(back == g, "a board changed on its way through the packed form")

                let candidates = MoveAdvisor.candidates(for: g, canRecycle: true)
                guard let move = candidates.randomElement(using: &rng) else { break }
                if let target = move.target, let head = move.cardIDs.first,
                   let (run, loc) = g.movableRun(startingAt: head) {
                    g.applyMove(run: run, from: loc.pile, to: target)
                } else if !g.stock.isEmpty {
                    g.drawFromStock(count: 1)
                } else {
                    g.recycleWaste()
                }
            }
        }

        // Which way up each card lies rides along with it.
        var s = GameState.deal(seed: 5)
        s.drawFromStock(count: 3)
        let restored = GameState(packed: s.packed)
        check(restored?.waste.allSatisfy(\.isFaceUp) == true, "the waste comes back face up")
        check(restored?.stock.allSatisfy { !$0.isFaceUp } == true, "the stock comes back face down")

        // Bytes that are not a board are refused rather than read as one.
        check(GameState(packed: Data()) == nil, "empty data is not a board")
        check(GameState(packed: Data(repeating: 0, count: 64)) == nil, "a short buffer is not a board")
        check(GameState(packed: Data(repeating: 0, count: 66)) == nil, "a long buffer is not a board")
        var wrongTotal = [UInt8](GameState.deal(seed: 1).packed)
        wrongTotal[0] &+= 1
        check(GameState(packed: Data(wrongTotal)) == nil, "pile lengths that do not total 52 are refused")
        var badCard = [UInt8](GameState.deal(seed: 1).packed)
        badCard[13] = 52
        check(GameState(packed: Data(badCard)) == nil, "a card index past the end of the deck is refused")
    }

    // MARK: - The undo history that travels with a saved game

    static func undoHistory() {
        var g = GameState.deal(seed: 21)
        var history = UndoHistory()
        var expected: [UndoStep] = []
        for i in 0..<120 {
            let step = UndoStep(
                state: g, points: i * 10 - 52, moves: i, recyclesUsed: i / 30,
                elapsedSeconds: i * 3, movedIDs: [g.stock.last?.id ?? g.waste[0].id]
            )
            expected.append(step)
            history.push(step, limit: 500)
            if g.stock.isEmpty { g.recycleWaste() } else { g.drawFromStock(count: 1) }
        }
        check(history.count == 120, "the history holds one record per move")
        check(history.packed.count == 120 * UndoStep.packedSize,
              "the history is a plain run of fixed-width records")

        // Steps come back off exactly as they went on, newest first.
        var replay = history
        for step in expected.reversed() {
            check(replay.popLast() == step, "a step changed on its way through the packed form")
        }
        check(replay.popLast() == nil, "an emptied history has nothing left to give back")

        // Vegas points go negative, and a move can carry a whole King-to-Ace run.
        let run = (1...13).reversed().map { Card(suit: .spades, rank: Rank(rawValue: $0)!).id }
        let widest = UndoStep(state: g, points: -52, moves: 3, recyclesUsed: 0,
                              elapsedSeconds: 7, movedIDs: run)
        var single = UndoHistory()
        single.push(widest, limit: 500)
        check(single.popLast() == widest, "a full run and a negative score both survive")

        // The recycle count fills a single byte, so the top of its range has to
        // come back as itself rather than wrapping round to nothing.
        let wornOut = UndoStep(state: g, points: 0, moves: 900,
                               recyclesUsed: UndoStep.maxRecycles,
                               elapsedSeconds: 9_000, movedIDs: [])
        var deep = UndoHistory()
        deep.push(wornOut, limit: 500)
        check(deep.popLast() == wornOut, "a deck turned over as often as the format allows survives")

        // The cap drops the oldest records rather than letting the file grow.
        var capped = UndoHistory()
        for i in 0..<40 {
            capped.push(UndoStep(state: g, points: i, moves: i, recyclesUsed: 0,
                                 elapsedSeconds: i, movedIDs: []), limit: 10)
        }
        check(capped.count == 10, "the history stops at its limit")
        check(capped.popLast()?.moves == 39, "and it is the newest steps that are kept")

        // Bytes that are not a history are refused rather than read as one.
        check(UndoHistory(packed: Data()) != nil, "no history at all is a history of nothing")
        check(UndoHistory(packed: Data(repeating: 0, count: 5)) == nil, "a part record is not a history")
        check(UndoHistory(packed: Data(repeating: 0, count: UndoStep.packedSize)) == nil,
              "a record whose board is not a board is refused")
        var cheated = g
        cheated.foundations[0] = [Card(suit: .spades, rank: .king, isFaceUp: true)]
        let impossible = UndoStep(state: cheated, points: 0, moves: 0, recyclesUsed: 0,
                                  elapsedSeconds: 0, movedIDs: [])
        check(UndoHistory(packed: Data(impossible.packedBytes)) == nil,
              "a step whose board breaks the rules is refused")

        // The history travels with the game.
        let saved = SavedGame(
            state: g, seed: 21, drawCount: 1, scoring: ScoreKeeper(mode: .standard),
            moves: 120, elapsedSeconds: 360, recyclesUsed: 4, hasStarted: true,
            vegasSettled: false, history: history.packed
        )
        guard let data = saved.encoded() else {
            check(false, "a game carrying a history should encode")
            return
        }
        check(SavedGame.decode(data) == saved, "a game round trips with its history intact")
        // The save is rewritten after every single move, so it has to stay small
        // enough that doing so costs nothing worth noticing.
        check(data.count < 20_000, "120 moves of history came to \(data.count) bytes")

        // A history that does not check out costs the history, not the game.
        var corrupt = saved
        corrupt.history = Data(repeating: 0, count: UndoStep.packedSize * 3)
        guard let corruptData = corrupt.encoded(), let salvaged = SavedGame.decode(corruptData) else {
            check(false, "a game with a broken history should still load")
            return
        }
        check(salvaged.history == nil, "a broken history is dropped")
        check(salvaged.state == g, "the board itself survives a broken history")

        // A save written before histories existed still loads.
        var legacy = saved
        legacy.history = nil
        guard let legacyData = legacy.encoded() else { return }
        check(!String(decoding: legacyData, as: UTF8.self).contains("history"),
              "an absent history is written as no key at all")
        check(SavedGame.decode(legacyData) == legacy, "a save from before histories existed still loads")
    }

    // MARK: - The clock

    static func timeFormatting() {
        check(TimeFormat.clock(0) == "0:00", "zero reads 0:00")
        check(TimeFormat.clock(9) == "0:09", "seconds are padded")
        check(TimeFormat.clock(65) == "1:05", "a minute rolls over")
        check(TimeFormat.clock(3599) == "59:59", "under an hour stays m:ss")
        check(TimeFormat.clock(3600) == "1:00:00", "an hour widens the clock to h:mm:ss")
        check(TimeFormat.clock(3661) == "1:01:01", "hours, minutes and seconds all read")
        check(TimeFormat.clock(TimeFormat.maxSeconds) == "99:59:59", "the clock stops at 99:59:59")
        check(TimeFormat.clock(-5) == "0:00", "a negative clock is not printed as one")
    }

    // MARK: - Layout

    static func layout() {
        // Board areas roughly matching real devices: the screen less the
        // status bar above it and the control bar below.
        let boards: [(String, CGSize)] = [
            ("iPhone SE portrait", CGSize(width: 375, height: 553)),
            ("iPhone 17 Pro portrait", CGSize(width: 402, height: 760)),
            ("iPhone 17 Pro Max portrait", CGSize(width: 440, height: 842)),
            ("iPhone landscape", CGSize(width: 874, height: 280)),
            ("iPad 11 portrait", CGSize(width: 834, height: 1080)),
            ("iPad 13 portrait", CGSize(width: 1024, height: 1252)),
            ("iPad 13 landscape", CGSize(width: 1366, height: 910)),
        ]
        // Six face-down cards under a full King-to-Ace run: the deepest a
        // column ever gets, and the shape the fan has to keep on the board.
        var deepest = GameState()
        var deck = Card.orderedDeck
        var column: [Card] = []
        for _ in 0..<6 {
            var card = deck.removeLast()
            card.isFaceUp = false
            column.append(card)
        }
        for i in 0..<13 {
            let suit: Suit = i.isMultiple(of: 2) ? .spades : .hearts
            column.append(Card(suit: suit, rank: Rank(rawValue: 13 - i)!, isFaceUp: true))
        }
        deepest.tableaus[0] = column

        for (name, size) in boards {
            for leftHanded in [false, true] {
                let m = BoardLayout.metrics(for: size, leftHanded: leftHanded)
                let who = leftHanded ? "\(name) (left-handed)" : name
                check(m.cardSize.width > 0 && m.cardSize.width.isFinite, "\(who): card width \(m.cardSize.width)")
                for point in m.foundationCenters + m.tableauTopCenters + [m.stockCenter, m.wasteCenter] {
                    check(point.x.isFinite && point.y.isFinite, "\(who): a pile landed at a non-finite point")
                }

                let placements = BoardLayout.placements(for: deepest, metrics: m, drawCount: 3)
                var bottom: CGFloat = 0
                for card in deepest.tableaus[0] {
                    if let p = placements[card.id] {
                        bottom = max(bottom, p.position.y + m.cardSize.height / 2)
                    }
                }

                // A column's drop target has to end where the column does —
                // half a card past its last one, the same overhang every pile
                // gets — whatever squeezing the two went through to get there.
                let targets = BoardLayout.dropTargets(for: deepest, metrics: m)
                if let column = targets.first(where: { $0.pile == .tableau(0) }) {
                    let overhang = column.frame.maxY - bottom
                    check(abs(overhang - m.cardSize.height / 2) < 0.5,
                          "\(who): the deepest column's hit area overhangs it by \(overhang), not half a card")
                }
                check(bottom <= size.height + 0.5, "\(who): the deepest column runs \(bottom - size.height) pt off the board")

                // Face-down cards are the ones with nothing to read, so they
                // never fan wider than the cards that have.
                check(m.fanDown <= m.fanUp * 0.85 + 0.5,
                      "\(who): face-down cards fan at \(m.fanDown), too close to the face-up step \(m.fanUp) to read as covered")
                // ...and never tighter than the ratio they had before the fan
                // started handing them the height nothing else was using.
                check(m.fanDown >= m.fanUp * 0.48 - 0.5,
                      "\(who): face-down step \(m.fanDown) is below the floor for a fan-up of \(m.fanUp)")

                // No height is left on the table: either the column the fan is
                // budgeted for runs to the bottom of the board, or the leftover
                // has already taken the face-down step as far as it may go.
                let reference = m.tableauTopCenters[0].y
                    + 6 * m.fanDown + 6 * m.fanUp + m.cardSize.height / 2
                check(reference >= m.tableauMaxBottom - 0.5 || m.fanDown >= m.fanUp * 0.85 - 0.5,
                      "\(who): the reference column stops \(m.tableauMaxBottom - reference) pt short with the fan not yet at its limit")

                guard !m.isLandscape else { continue }
                let topRowBottom = m.stockCenter.y + m.cardSize.height / 2
                let tableauTop = m.tableauTopCenters[0].y - m.cardSize.height / 2
                check(topRowBottom <= tableauTop + 0.5, "\(who): the top row overlaps the columns")
                // The third card of a draw-3 fan must stop short of the
                // foundations — on either side, since the layout mirrors.
                let fanEdge = m.wasteCenter.x + m.wasteFanStep.dx * 2
                let gap = leftHanded
                    ? (fanEdge - m.cardSize.width / 2) - (m.foundationCenters[0].x + m.cardSize.width / 2)
                    : (m.foundationCenters[0].x - m.cardSize.width / 2) - (fanEdge + m.cardSize.width / 2)
                check(gap >= -0.5, "\(who): the draw-3 waste fan overlaps the foundations by \(-gap) pt")
            }
        }

        // A GeometryReader reports sizes no board ever has — zero during a
        // rotation, a sliver mid-resize. None may reach the drawing code as a
        // measurement it cannot take.
        let degenerate = [
            CGSize.zero,
            CGSize(width: 3, height: 900),
            CGSize(width: CGFloat.nan, height: 700),
            CGSize(width: 500, height: CGFloat.infinity),
        ]
        for size in degenerate {
            let m = BoardLayout.metrics(for: size, leftHanded: false)
            check(m.cardSize.width > 0 && m.cardSize.width.isFinite, "degenerate \(size): card width \(m.cardSize.width)")
            check(m.cardSize.height > 0 && m.cardSize.height.isFinite, "degenerate \(size): card height \(m.cardSize.height)")
            check(m.fanUp >= 0 && m.fanUp.isFinite, "degenerate \(size): fan step \(m.fanUp)")
        }
    }

    // MARK: - Preferences and lifetime statistics

    static func preferences() {
        let suiteName = "solitaire.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            check(false, "could not open a scratch defaults suite")
            return
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        // What a player who has never opened Settings gets.
        let settings = GameSettings(defaults: defaults)
        check(settings.drawCount == 1, "a new player draws one card")
        check(settings.scoringMode == .standard, "a new player scores the standard way")
        check(settings.soundsEnabled && settings.hapticsEnabled, "sound and haptics start on")
        check(settings.tableTheme == .forest && settings.cardBack == .crimson, "the table starts green")
        check(!settings.leftHandMode && !settings.vegasCumulative, "the optional modes start off")

        // Every one of them survives a relaunch.
        settings.drawCount = 3
        settings.scoringMode = .vegas
        settings.vegasCumulative = true
        settings.leftHandMode = true
        settings.tableTheme = .ocean
        settings.cardBack = .night
        settings.soundsEnabled = false
        settings.hapticsEnabled = false
        let reopened = GameSettings(defaults: defaults)
        check(reopened.drawCount == 3, "the draw count is remembered")
        check(reopened.scoringMode == .vegas, "the scoring mode is remembered")
        check(reopened.vegasCumulative, "the cumulative Vegas flag is remembered")
        check(reopened.leftHandMode, "the left-handed layout is remembered")
        check(reopened.tableTheme == .ocean && reopened.cardBack == .night, "the appearance is remembered")
        check(!reopened.soundsEnabled && !reopened.hapticsEnabled, "sound and haptics stay off")

        // Nonsense in the store falls back instead of taking the app with it.
        defaults.set("no-such-theme", forKey: "settings.tableTheme")
        defaults.set(7, forKey: "settings.drawCount")
        let salvaged = GameSettings(defaults: defaults)
        check(salvaged.tableTheme == .forest, "an unknown theme falls back to the default")
        check(salvaged.drawCount == 1, "an impossible draw count falls back to one")

        // Statistics: streaks build and break, records only improve.
        let stats = Statistics(defaults: defaults)
        check(stats.data.gamesPlayed == 0, "a new player has no games behind them")
        stats.recordGameStarted()
        check(stats.recordWin(drawCount: 1, timeSeconds: 300, moves: 200, standardScore: 900) == (true, true, true),
              "the first win sets every record")
        stats.recordGameStarted()
        check(stats.recordWin(drawCount: 1, timeSeconds: 400, moves: 250, standardScore: 800) == (false, false, false),
              "a worse game sets no records")
        // Draw 3 keeps its own bests. The same game that set no record above
        // sets all three here, because it is the first of its kind.
        stats.recordGameStarted()
        check(stats.recordWin(drawCount: 3, timeSeconds: 400, moves: 250, standardScore: 800) == (true, true, true),
              "the first draw-3 win sets the draw-3 records")
        check(stats.data.drawOne.bestTimeSeconds == 300, "a draw-3 game leaves the draw-1 best alone")
        check(stats.data.drawThree.bestTimeSeconds == 400, "and draw 3 keeps its own")
        check(stats.data.currentStreak == 3 && stats.data.bestStreak == 3, "three wins make a streak of three")
        stats.recordGameStarted()
        stats.recordLoss()
        check(stats.data.currentStreak == 0, "a loss breaks the streak")
        check(stats.data.bestStreak == 3, "the best streak stands after a loss")
        check(stats.data.gamesPlayed == 4 && stats.data.gamesWon == 3, "four played, three won")
        check(abs(stats.data.winRate - 0.75) < 0.0001, "the win rate is wins over games played")
        stats.addVegasResult(-52)
        stats.addVegasResult(30)
        check(stats.data.vegasBalance == -22, "Vegas results add up")
        check(Statistics(defaults: defaults).data == stats.data, "statistics survive a relaunch")
        stats.reset()
        check(stats.data == StatisticsData(), "reset clears everything")
        check(Statistics(defaults: defaults).data == StatisticsData(), "and the reset is written through")

        // A table written before the records were split still loads, and keeps
        // the bests it had rather than starting the player over.
        let pooled = """
        {"gamesPlayed":9,"gamesWon":4,"currentStreak":1,"bestStreak":3,"vegasBalance":-30,\
        "bestTimeSeconds":212,"fewestMoves":140,"bestStandardScore":1120}
        """
        defaults.set(Data(pooled.utf8), forKey: "solitaire.statistics.v1")
        let migrated = Statistics(defaults: defaults).data
        check(migrated.gamesPlayed == 9 && migrated.gamesWon == 4, "the counters survive the split")
        check(migrated.bestStreak == 3 && migrated.vegasBalance == -30, "so do the streak and the balance")
        check(migrated.drawOne == StatisticsData.Records(bestTimeSeconds: 212, fewestMoves: 140, bestStandardScore: 1120),
              "the old bests land in the draw-1 table")
        check(migrated.drawThree == StatisticsData.Records(), "and draw 3 starts empty")
    }

    // MARK: - Fuzz

    static func fuzz(deals: Int = 400) {
        var rng = SeededGenerator(seed: 99)
        var wins = 0, finishable = 0

        for game in 0..<deals {
            var g = GameState.deal(seed: UInt64(game + 1))
            let drawCount = game.isMultiple(of: 2) ? 1 : 3
            var recycles = 0

            for step in 0..<1500 {
                assertInvariants(g, "fuzz game \(game) step \(step)")
                if g.isWon { break }
                if g.canAutoFinish { finishable += 1; break }

                func uncovers(_ move: (run: [Card], from: PileID, to: PileID)) -> Bool {
                    guard case .tableau(let i) = move.from else { return false }
                    let below = g.tableaus[i].count - move.run.count - 1
                    return below >= 0 && !g.tableaus[i][below].isFaceUp
                }
                // Relocating a whole column into an empty one changes nothing;
                // any other column-emptying move is real progress.
                func pointless(_ move: (run: [Card], from: PileID, to: PileID)) -> Bool {
                    guard case .tableau(let i) = move.from,
                          case .tableau(let j) = move.to else { return false }
                    return g.tableaus[i].count == move.run.count && g.tableaus[j].isEmpty
                }

                var moves: [(run: [Card], from: PileID, to: PileID)] = []
                for pile in GameState.allPiles where !pile.isFoundation {
                    for card in g[pile] where card.isFaceUp {
                        guard let (run, loc) = g.movableRun(startingAt: card.id) else { continue }
                        for target in GameState.allPiles where g.canDrop(run: run, from: loc.pile, on: target) {
                            moves.append((run, loc.pile, target))
                        }
                    }
                }

                // The destinations read out to a VoiceOver reader are the moves
                // a drag would allow and nothing else — every column that would
                // take the card, plus a foundation when one would. Only one
                // foundation: an ace fits all four empty ones, and four
                // identical choices help nobody.
                //
                // Sampled rather than run every step. Asking all 52 cards costs
                // a scan of the board apiece, which on every step of every deal
                // is forty times the price of the whole sweep — and this is a
                // property of the function, not of any particular depth of
                // play, so a few thousand positions spread across the fuzz
                // establish it just as well. `suggestions()` pins the cases
                // worth naming.
                if step.isMultiple(of: 100) {
                    // Built here rather than alongside `moves`: filling it in
                    // that loop costs a dictionary write per legal move on
                    // every step of every deal, which on its own was twenty
                    // times the price of the whole sweep.
                    var legalTargets: [String: Set<PileID>] = [:]
                    for move in moves {
                        guard let id = move.run.first?.id else { continue }
                        legalTargets[id, default: []].insert(move.to)
                    }
                    for pile in GameState.allPiles where !pile.isFoundation {
                        for card in g[pile] where card.isFaceUp {
                            let offered = MoveAdvisor.destinations(forCardID: card.id, in: g)
                            let legal = legalTargets[card.id] ?? []
                            let context = "fuzz game \(game) step \(step), \(card.id)"
                            check(Set(offered).count == offered.count,
                                  "\(context): a destination offered twice")
                            check(offered.allSatisfy { legal.contains($0) },
                                  "\(context): offered a destination a drag would refuse")
                            check(Set(offered.filter(\.isTableau)) == legal.filter(\.isTableau),
                                  "\(context): a column a drag allows must be offered too")
                            check(offered.filter(\.isFoundation).count
                                    == (legal.contains(where: \.isFoundation) ? 1 : 0),
                                  "\(context): exactly one foundation is offered, and only when one accepts")
                        }
                    }
                }

                // The banner must never appear while the player still has a move:
                // whenever the bot sees a real one, the engine has to agree.
                let recycleAvailable = g.stock.isEmpty && !g.waste.isEmpty && recycles < 8
                if !g.stock.isEmpty || recycleAvailable || moves.contains(where: { !pointless($0) }) {
                    check(g.hasLegalMove(allowRecycle: recycleAvailable),
                          "fuzz game \(game) step \(step): engine reported a dead end with moves left")
                }
                // The hint list and the banner read the same board: one has to
                // find a move exactly when the other says there is one.
                let suggested = !MoveAdvisor.candidates(for: g, canRecycle: recycleAvailable).isEmpty
                check(suggested == g.hasLegalMove(allowRecycle: recycleAvailable),
                      "fuzz game \(game) step \(step): hint list and dead-end check disagree")

                if let f = moves.first(where: { $0.to.isFoundation }) {
                    g.applyMove(run: f.run, from: f.from, to: f.to)
                } else if let u = moves.first(where: { uncovers($0) && !$0.to.isFoundation }) {
                    g.applyMove(run: u.run, from: u.from, to: u.to)
                } else if let w = moves.first(where: { $0.from == .waste }) {
                    g.applyMove(run: w.run, from: w.from, to: w.to)
                } else if !g.stock.isEmpty {
                    g.drawFromStock(count: drawCount)
                } else if !g.waste.isEmpty, recycles < 8 {
                    g.recycleWaste()
                    recycles += 1
                } else if let move = moves.filter({ !pointless($0) }).randomElement(using: &rng) {
                    g.applyMove(run: move.run, from: move.from, to: move.to)
                } else {
                    // Nothing left worth doing: the engine must agree.
                    check(!g.hasLegalMove(allowRecycle: recycles < 8 && !g.waste.isEmpty),
                          "fuzz game \(game): bot gave up while a move was still available")
                    break
                }
            }
            if g.isWon { wins += 1 }
        }
        print("fuzz: \(wins) wins, \(finishable) reached auto-finish, of \(deals) deals")
        check(wins + finishable > 0, "the heuristic bot should finish at least some deals")
    }
}
