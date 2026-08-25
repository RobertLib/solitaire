//
//  GameViewModelTests.swift
//  solitaireTests
//
//  The game flow the engine suites cannot reach: undo against a live clock,
//  the saved game, the Vegas ledger, statistics bookkeeping and the wand.
//
//  Every case runs against a scratch defaults suite, so a test run never reads
//  or writes the preferences of whoever is running it. The one-second timer is
//  left alone and the clock is driven through `tick()` instead — these cases
//  finish in milliseconds, long before it would fire on its own.
//

import XCTest
@testable import solitaire

@MainActor
final class GameViewModelTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard
    private var settings: GameSettings!
    private var statistics: Statistics!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "solitaire.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        settings = GameSettings(defaults: defaults)
        // Nothing in a test run should reach the speaker or the Taptic Engine.
        settings.soundsEnabled = false
        settings.hapticsEnabled = false
        statistics = Statistics(defaults: defaults)
    }

    override func tearDown() async throws {
        settings = nil
        statistics = nil
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// A model on the scratch suite, holding a known deal.
    ///
    /// The deal is planted in the store for the model to pick up rather than
    /// dealt afterwards: constructing the model already deals one, so calling
    /// `newGame` on top would deal twice — and under Vegas the throwaway deal
    /// would bank a buy-in before the test had done anything.
    private func makeGame(seed: UInt64 = 4242) -> GameViewModel {
        let deal = SavedGame(
            state: GameState.deal(seed: seed), seed: seed, drawCount: settings.drawCount,
            scoring: ScoreKeeper(mode: settings.scoringMode), moves: 0, elapsedSeconds: 0,
            recyclesUsed: 0, hasStarted: false, vegasSettled: false, history: Data()
        )
        defaults.set(deal.encoded(), forKey: "solitaire.savedGame.v1")
        return GameViewModel(settings: settings, statistics: statistics, defaults: defaults)
    }

    /// A model that picks up whatever the scratch suite already holds — what
    /// happens when the app is launched again.
    private func relaunch() -> GameViewModel {
        GameViewModel(settings: settings, statistics: statistics, defaults: defaults)
    }

    /// Plays the first move the hint list offers. Returns false when the only
    /// thing left to do is turn the deck over.
    @discardableResult
    private func playOneMove(_ vm: GameViewModel) -> Bool {
        let candidates = MoveAdvisor.candidates(for: vm.state, canRecycle: vm.canRecycle)
        guard let move = candidates.first(where: { $0.target != nil }),
              let target = move.target, let head = move.cardIDs.first
        else { return false }
        return vm.attemptMove(cardID: head, to: target)
    }

    // MARK: - Dealing

    func testANewDealIsABoardTheRulesCouldHaveProduced() {
        let vm = makeGame()
        XCTAssertTrue(vm.state.isConsistent)
        XCTAssertEqual(vm.state.allCards.count, 52)
        XCTAssertEqual(vm.state.stock.count, 24)
        XCTAssertEqual(vm.state.tableaus.map(\.count), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(vm.moves, 0)
        XCTAssertFalse(vm.hasStarted)
        XCTAssertFalse(vm.canUndo)
    }

    func testTheSameSeedDealsTheSameBoard() {
        XCTAssertEqual(makeGame(seed: 777).state, makeGame(seed: 777).state)
        XCTAssertNotEqual(makeGame(seed: 777).state, makeGame(seed: 778).state)
    }

    // MARK: - Undo

    func testUndoPutsTheBoardAndTheScoreBack() {
        let vm = makeGame()
        let before = vm.state
        let scoreBefore = vm.scoring.points

        XCTAssertTrue(playOneMove(vm), "the opening board should offer a move")
        XCTAssertNotEqual(vm.state, before)
        XCTAssertEqual(vm.moves, 1)
        XCTAssertTrue(vm.canUndo)

        vm.undo()
        XCTAssertEqual(vm.state, before)
        XCTAssertEqual(vm.scoring.points, scoreBefore)
        XCTAssertEqual(vm.moves, 0)
        XCTAssertFalse(vm.canUndo)
    }

    func testUndoUnwindsAWholeGameMoveByMove() {
        let vm = makeGame()
        var boards = [vm.state]
        for _ in 0..<25 {
            if !playOneMove(vm) { vm.tapStock() }
            boards.append(vm.state)
        }
        while vm.canUndo {
            boards.removeLast()
            vm.undo()
            XCTAssertEqual(vm.state, boards.last)
        }
        XCTAssertEqual(boards.count, 1)
        XCTAssertEqual(vm.moves, 0)
    }

    func testUndoRechargesThePenaltiesTheClockRanUpMeanwhile() {
        let vm = makeGame()
        XCTAssertEqual(vm.scoring.mode, .standard)
        let scoreBeforeMove = vm.scoring.points

        XCTAssertTrue(playOneMove(vm))
        // Twenty seconds pass while the move stands: two ten-second ticks.
        for _ in 0..<20 { vm.tick() }
        XCTAssertEqual(vm.elapsedSeconds, 20)

        vm.undo()
        // The board is back where it was, but the time is spent: the score is
        // the pre-move score less the two penalties charged since.
        XCTAssertEqual(vm.scoring.points, max(0, scoreBeforeMove - 4))
    }

    // MARK: - The saved game

    func testAGameInProgressComesBackAfterARelaunch() {
        let vm = makeGame(seed: 31337)
        for _ in 0..<12 where !playOneMove(vm) { vm.tapStock() }
        for _ in 0..<45 { vm.tick() }
        vm.saveGame()

        let board = vm.state
        let score = vm.scoring.points
        let moves = vm.moves
        let elapsed = vm.elapsedSeconds

        let resumed = relaunch()
        XCTAssertEqual(resumed.state, board)
        XCTAssertEqual(resumed.scoring.points, score)
        XCTAssertEqual(resumed.moves, moves)
        XCTAssertEqual(resumed.elapsedSeconds, elapsed)
        XCTAssertEqual(resumed.seed, 31337)
    }

    /// The point of persisting the history: a player who reopens the app —
    /// especially into a dead deal — can still take the last move back.
    func testUndoStillWorksAfterARelaunch() {
        let vm = makeGame(seed: 909)
        var boards: [GameState] = []
        for _ in 0..<10 {
            boards.append(vm.state)
            if !playOneMove(vm) { vm.tapStock() }
        }
        vm.saveGame()

        let resumed = relaunch()
        XCTAssertTrue(resumed.canUndo, "the history should survive the relaunch")
        while let expected = boards.popLast() {
            XCTAssertTrue(resumed.canUndo)
            resumed.undo()
            XCTAssertEqual(resumed.state, expected)
        }
        XCTAssertFalse(resumed.canUndo, "the history should run out exactly at the deal")
        XCTAssertEqual(resumed.moves, 0)
    }

    func testTheHistoryIsCappedRatherThanGrowingForever() {
        let vm = makeGame()
        // Turning the deck over is always available, so this runs the counter
        // well past the cap without needing a board that allows 700 real moves.
        for _ in 0..<700 { vm.tapStock() }
        var undone = 0
        while vm.canUndo {
            vm.undo()
            undone += 1
            XCTAssertLessThanOrEqual(undone, 600, "undo should not run past the cap")
        }
        XCTAssertEqual(undone, 500, "the history should hold the last 500 moves")
    }

    func testAWonGameLeavesNoSaveBehind() async throws {
        let vm = makeGame()
        vm.loadAutoFinishScenario()
        XCTAssertTrue(vm.canAutoFinish)

        vm.autoFinish()
        try await waitUntil("the wand finishes the deal") { vm.isWon }

        XCTAssertNil(defaults.data(forKey: "solitaire.savedGame.v1"))
        XCTAssertEqual(statistics.data.gamesWon, 1)
        // Nothing to resume: the next launch deals a fresh board.
        XCTAssertFalse(relaunch().isWon)
    }

    func testBytesThatAreNotAGameAreThrownAway() {
        defaults.set(Data("not a saved game".utf8), forKey: "solitaire.savedGame.v1")
        let vm = relaunch()
        XCTAssertTrue(vm.state.isConsistent, "an unreadable save should give way to a fresh deal")
        XCTAssertEqual(vm.moves, 0)
    }

    func testASaveDescribingAnImpossibleBoardIsRefused() throws {
        var broken = GameState.deal(seed: 5)
        broken.tableaus[0] = []   // the missing card makes it 51
        let save = SavedGame(
            state: broken, seed: 5, drawCount: 1, scoring: ScoreKeeper(mode: .standard),
            moves: 3, elapsedSeconds: 9, recyclesUsed: 0, hasStarted: true,
            vegasSettled: false, history: nil
        )
        defaults.set(try XCTUnwrap(save.encoded()), forKey: "solitaire.savedGame.v1")

        let vm = relaunch()
        XCTAssertTrue(vm.state.isConsistent)
        XCTAssertEqual(vm.state.allCards.count, 52)
    }

    // MARK: - Vegas

    func testTheVegasBuyInIsChargedOncePerDeal() {
        settings.scoringMode = .vegas
        let vm = makeGame()
        XCTAssertEqual(vm.scoring.points, -52, "the deck is bought up front")
        XCTAssertEqual(statistics.data.vegasBalance, 0, "the deal in play is not banked yet")
        XCTAssertEqual(vm.vegasBalance, -52, "but it does show in the balance on screen")

        vm.newGame(animated: false)
        XCTAssertEqual(statistics.data.vegasBalance, -52, "abandoning the deal banks its buy-in")
        vm.newGame(animated: false)
        XCTAssertEqual(statistics.data.vegasBalance, -104, "and again for the next one")
    }

    func testAResumedVegasDealIsNotChargedTwice() {
        settings.scoringMode = .vegas
        let vm = makeGame()
        vm.saveGame()
        XCTAssertEqual(statistics.data.vegasBalance, 0)

        let resumed = relaunch()
        XCTAssertEqual(resumed.scoring.points, -52)
        XCTAssertEqual(statistics.data.vegasBalance, 0, "resuming does not bank anything")
        resumed.newGame(animated: false)
        XCTAssertEqual(statistics.data.vegasBalance, -52, "the buy-in is banked exactly once")
    }

    func testVegasLimitsThePassesThroughTheDeck() {
        settings.scoringMode = .vegas
        settings.drawCount = 1
        let vm = makeGame()
        while !vm.state.stock.isEmpty { vm.tapStock() }
        XCTAssertFalse(vm.canRecycle, "draw-1 Vegas allows a single pass")

        settings.drawCount = 3
        let three = makeGame()
        var recycles = 0
        for _ in 0..<200 {
            if three.state.stock.isEmpty {
                guard three.canRecycle else { break }
                recycles += 1
            }
            three.tapStock()
        }
        XCTAssertEqual(recycles, 2, "draw-3 Vegas allows three passes, so two turns of the deck")
    }

    // MARK: - Statistics

    func testAnAbandonedGameCountsAsPlayedAndBreaksTheStreak() {
        let vm = makeGame()
        XCTAssertEqual(statistics.data.gamesPlayed, 0, "a deal nobody has touched is not a game")

        XCTAssertTrue(playOneMove(vm))
        XCTAssertEqual(statistics.data.gamesPlayed, 1, "the first move starts the game")

        vm.newGame(animated: false)
        XCTAssertEqual(statistics.data.gamesPlayed, 1, "abandoning it does not count it twice")
        XCTAssertEqual(statistics.data.currentStreak, 0)
        XCTAssertEqual(statistics.data.gamesWon, 0)
    }

    func testResumingDoesNotCountTheGameAgain() {
        let vm = makeGame()
        XCTAssertTrue(playOneMove(vm))
        vm.saveGame()
        XCTAssertEqual(statistics.data.gamesPlayed, 1)

        _ = relaunch()
        _ = relaunch()
        XCTAssertEqual(statistics.data.gamesPlayed, 1, "reopening the app is not a new game")
    }

    func testARecordIsFiledUnderTheRulesItWasSetUnder() async throws {
        settings.drawCount = 3
        let vm = makeGame()
        XCTAssertEqual(vm.drawCount, 3)
        vm.loadAutoFinishScenario()
        vm.autoFinish()
        try await waitUntil("the wand finishes the deal") { vm.isWon }

        XCTAssertNotNil(statistics.data.drawThree.bestTimeSeconds, "a draw-3 win sets a draw-3 record")
        XCTAssertNil(statistics.data.drawOne.bestTimeSeconds, "and leaves the draw-1 table alone")
    }

    // MARK: - The score block

    func testTheScoreBlockOnlyCallsItselfABalanceWhenItIsOne() {
        settings.scoringMode = .standard
        XCTAssertEqual(makeGame().scoreLabel, L10n.score)

        // Vegas without the running total is still just this deal's dollars.
        settings.scoringMode = .vegas
        settings.vegasCumulative = false
        let single = makeGame()
        XCTAssertEqual(single.scoreLabel, L10n.score)
        XCTAssertEqual(single.displayScore, "-$52", "the buy-in for this deal alone")

        settings.vegasCumulative = true
        XCTAssertEqual(makeGame().scoreLabel, L10n.balance, "the figure that carries between deals")
    }

    // MARK: - Auto-finish

    func testTheWandWaitsUntilTheDealIsCertain() {
        let vm = makeGame()
        XCTAssertFalse(vm.canAutoFinish, "a fresh deal is not a certainty")

        vm.loadAutoFinishScenario()
        XCTAssertTrue(vm.canAutoFinish, "every card face up and the deck spent is")
    }

    func testTheWandWillNotOfferItselfWhenTheStockIsOutOfReach() {
        // Draw-3 keeps two cards in every three out of reach, so a stock with
        // cards in it is not a guaranteed win however the columns look.
        settings.drawCount = 3
        let vm = makeGame()
        vm.loadAutoFinishThroughStockScenario()
        XCTAssertFalse(vm.canAutoFinish)

        // Draw-1 with unlimited passes can reach every card, so it is.
        settings.drawCount = 1
        let single = makeGame()
        single.loadAutoFinishThroughStockScenario()
        XCTAssertTrue(single.canAutoFinish)
    }

    func testTheWandPlaysTheDealOutThroughTheStock() async throws {
        let vm = makeGame()
        vm.loadAutoFinishThroughStockScenario()
        vm.autoFinish()
        try await waitUntil("the wand works the deck") { vm.isWon }
        XCTAssertTrue(vm.state.isWon)
        XCTAssertEqual(vm.state.foundations.map(\.count), [13, 13, 13, 13])
    }

    // MARK: - Dead ends

    func testADeadDealSaysSoAndAHintAgrees() {
        let vm = makeGame()
        vm.loadStuckScenario()
        XCTAssertTrue(vm.isStuck)

        vm.requestHint()
        XCTAssertEqual(vm.hint?.message, L10n.hintNoMoves)
        XCTAssertFalse(vm.canAutoFinish)
    }

    func testALiveDealNeverSaysItIsDead() {
        let vm = makeGame()
        for _ in 0..<40 {
            XCTAssertFalse(vm.isStuck, "a board with the stock still full has moves in it")
            if !playOneMove(vm) { vm.tapStock() }
        }
    }

    // MARK: - Tapping

    func testTappingAFoundationDoesNothing() {
        let vm = makeGame()
        vm.loadAutoFinishScenario()
        let top = try? XCTUnwrap(vm.state.foundations[0].last)
        let before = vm.state

        XCTAssertFalse(vm.smartMove(cardID: try! XCTUnwrap(top).id),
                       "a stray tap on a foundation should not undo progress")
        XCTAssertEqual(vm.state, before)
        XCTAssertEqual(vm.moves, 0)
    }

    func testTappingTheStockDealsAndTappingAgainRecycles() {
        let vm = makeGame()
        XCTAssertEqual(vm.state.waste.count, 0)
        vm.tapStock()
        XCTAssertEqual(vm.state.waste.count, 1)
        XCTAssertEqual(vm.state.stock.count, 23)

        while !vm.state.stock.isEmpty { vm.tapStock() }
        XCTAssertEqual(vm.state.waste.count, 24)
        XCTAssertTrue(vm.canRecycle, "unlimited passes outside Vegas")
        vm.tapStock()
        XCTAssertEqual(vm.state.stock.count, 24)
        XCTAssertEqual(vm.state.waste.count, 0)
        XCTAssertEqual(vm.recyclesUsed, 1)
    }

    func testAStockWithNothingLeftToGiveSaysSo() {
        settings.scoringMode = .vegas
        settings.drawCount = 1
        let vm = makeGame()
        while !vm.state.stock.isEmpty { XCTAssertTrue(vm.tapStock()) }
        XCTAssertFalse(vm.canRecycle, "draw-1 Vegas allows a single pass")

        let before = vm.state
        let moves = vm.moves
        XCTAssertFalse(vm.tapStock(), "an exhausted stock with no pass left did nothing")
        // A tap on the pile and a tap on a card sitting in it are the same
        // gesture, so they have to give the same answer.
        let waste = try? XCTUnwrap(vm.state.waste.last)
        XCTAssertFalse(vm.smartMove(cardID: try! XCTUnwrap(waste).id),
                       "nor did tapping the card the failed draw would have covered")
        XCTAssertEqual(vm.state, before)
        XCTAssertEqual(vm.moves, moves)
    }

    // MARK: - Hints

    func testAskingAgainOffersADifferentSuggestion() {
        let vm = makeGame()
        vm.requestHint()
        let first = vm.hint
        vm.requestHint()
        XCTAssertNotNil(first)
        XCTAssertNotEqual(vm.hint, first, "the hint should cycle rather than repeat itself")
    }

    // MARK: - The clock

    func testTheClockOnlyRunsOnceTheGameHasStarted() {
        let vm = makeGame()
        vm.tick()
        XCTAssertEqual(vm.elapsedSeconds, 0, "an untouched deal is not being timed")

        XCTAssertTrue(playOneMove(vm))
        vm.tick()
        XCTAssertEqual(vm.elapsedSeconds, 1)

        vm.isPaused = true
        vm.tick()
        XCTAssertEqual(vm.elapsedSeconds, 1, "a paused game is not being timed either")
    }

    func testTheClockStopsRatherThanWideningForever() {
        let vm = makeGame()
        XCTAssertTrue(playOneMove(vm))
        for _ in 0..<(TimeFormat.maxSeconds + 50) { vm.tick() }
        XCTAssertEqual(vm.elapsedSeconds, TimeFormat.maxSeconds)
        XCTAssertEqual(vm.formattedTime, "99:59:59")
    }

    // MARK: - Helpers

    /// Polls until `condition` holds. The wand runs on its own task with a
    /// deliberate pause between cards, so there is nothing to await directly.
    private func waitUntil(
        _ what: String,
        timeout: TimeInterval = 30,
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("timed out waiting for \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
