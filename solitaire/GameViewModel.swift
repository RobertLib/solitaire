//
//  GameViewModel.swift
//  solitaire
//
//  Drives a Klondike game: rules, scoring, undo, hints, timer, persistence.
//

import SwiftUI
import Observation

struct Hint: Equatable {
    var cardIDs: [String] = []
    var target: PileID?
    var message: String?
}

@MainActor
@Observable
final class GameViewModel {
    let settings: GameSettings
    let statistics: Statistics
    private let defaults: UserDefaults

    // Rules snapshot for the current deal (settings changes apply next deal).
    private(set) var drawCount = 1
    private(set) var scoring = ScoreKeeper(mode: .standard)
    private(set) var seed: UInt64 = 0

    // Game state
    private(set) var state = GameState()
    private(set) var moves = 0
    private(set) var elapsedSeconds = 0
    private(set) var recyclesUsed = 0
    private(set) var isWon = false { didSet { syncTimer() } }
    private(set) var isDealing = false { didSet { syncTimer() } }
    private(set) var isAutoFinishing = false
    private(set) var hasStarted = false { didSet { syncTimer() } }

    /// Set once this deal's Vegas result has been added to the lifetime
    /// balance, so the balance on screen never counts it twice.
    private(set) var vegasSettled = false

    // Win details for the results screen
    private(set) var timeBonus = 0
    private(set) var newRecords: (time: Bool, moves: Bool, score: Bool) = (false, false, false)

    // Transient UI state
    private(set) var hint: Hint?
    var isPaused = false { didSet { syncTimer() } }

    /// Cards that just moved keep an elevated z-index while their move
    /// animation plays, so they fly over other piles instead of under them.
    private(set) var recentlyMoved: Set<String> = []

    /// Every move of this deal, in the same packed form it is saved in, so
    /// writing the save after a move copies bytes that are already laid out
    /// instead of encoding the whole history again.
    private var history = UndoHistory()
    private var elevationTokens: [String: Int] = [:]
    private var nextElevationToken = 0
    private var dealGeneration = 0
    private var lastHintIndex = -1

    // Held outside the main actor's isolation so `deinit`, which runs
    // nonisolated, can still cancel them. Every other access is on the main
    // actor, where the compiler keeps them to one thread as usual.
    @ObservationIgnored private nonisolated(unsafe) var timerTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated(unsafe) var hintClearTask: Task<Void, Never>?

    /// How far back undo reaches. Far past any real game — the cap is there so
    /// a runaway loop cannot grow the history, and the save file with it,
    /// without bound.
    private static let maxUndoDepth = 500

    var canUndo: Bool { !history.isEmpty && !isDealing && !isAutoFinishing && !isWon }
    var interactionLocked: Bool { isDealing || isAutoFinishing || isWon }

    /// Every stock card is reachable: passes are unlimited and each draw turns
    /// a single card, so cycling the deck eventually offers all of them.
    private var hasFreeStockCycling: Bool { drawCount == 1 && allowedPasses == nil }

    var canAutoFinish: Bool {
        state.canAutoFinish(freeStockCycling: hasFreeStockCycling) && !interactionLocked
    }

    /// The deal is dead: nothing left to draw, recycle or play. Purely
    /// informational — the board stays fully interactive.
    var isStuck: Bool {
        guard hasStarted, !interactionLocked else { return false }
        return !state.hasLegalMove(allowRecycle: canRecycle)
    }

    /// Passes through the deck still allowed? nil = unlimited.
    private var allowedPasses: Int? { ScoreKeeper.allowedPasses(mode: scoring.mode, drawCount: drawCount) }

    var canRecycle: Bool {
        guard state.stock.isEmpty, !state.waste.isEmpty else { return false }
        guard let allowed = allowedPasses else { return true }
        return recyclesUsed < allowed - 1
    }

    /// What the score block is showing. Only the figure that carries between
    /// deals is a balance; a single deal's dollars are its score like any other.
    var scoreLabel: String {
        scoring.mode == .vegas && settings.vegasCumulative ? L10n.balance : L10n.score
    }

    var displayScore: String {
        switch scoring.mode {
        case .none: return "—"
        case .standard: return "\(scoring.points)"
        case .vegas:
            return ScoreKeeper.formatVegas(settings.vegasCumulative ? vegasBalance : scoring.points)
        }
    }

    /// Lifetime Vegas balance including this deal, counted only once.
    var vegasBalance: Int {
        statistics.data.vegasBalance + (vegasSettled ? 0 : scoring.points)
    }

    var formattedTime: String { TimeFormat.clock(elapsedSeconds) }

    // MARK: - Lifecycle

    /// `defaults` is the store the saved game lives in. It is a parameter so the
    /// tests can hand over a scratch suite instead of writing a game into the
    /// defaults of whoever is running them.
    init(settings: GameSettings, statistics: Statistics, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.statistics = statistics
        self.defaults = defaults
        if !restoreSavedGame() {
            newGame()
        }
        syncTimer()
    }

    deinit {
        // Both outlive the model otherwise: the timer wakes once a second
        // forever, and a hint that has not faded yet holds a strong reference
        // to a model nothing else is using.
        timerTask?.cancel()
        hintClearTask?.cancel()
    }

    // MARK: - New game / restart

    func newGame(seed newSeed: UInt64? = nil, animated: Bool = true) {
        finalizeAbandonedGameIfNeeded()
        dealGeneration += 1

        seed = newSeed ?? UInt64.random(in: 1...999_999)
        drawCount = settings.drawCount
        scoring = ScoreKeeper(mode: settings.scoringMode)
        moves = 0
        elapsedSeconds = 0
        recyclesUsed = 0
        isWon = false
        isAutoFinishing = false
        hasStarted = false
        vegasSettled = false
        timeBonus = 0
        newRecords = (false, false, false)
        history.removeAll()
        clearHint()
        recentlyMoved = []
        elevationTokens = [:]
        clearSavedGame()

        // Reduce Motion takes the second branch: the cards arrive on the
        // table, they just do not fly there. The board is identical either way
        // — dealing step by step off the shuffled stock and `GameState.deal`
        // walk the same deck in the same order — so only the journey is
        // skipped, not the deal.
        if animated, !Motion.isReduced {
            // Start with the whole shuffled deck in the stock and deal
            // step-by-step so cards visibly fly to their places.
            var deck = Card.orderedDeck
            var rng = SeededGenerator(seed: seed)
            deck.shuffle(using: &rng)
            var s = GameState()
            s.stock = deck
            state = s
            isDealing = true
            let generation = dealGeneration
            Task { await runDealAnimation(generation: generation) }
        } else {
            state = GameState.deal(seed: seed)
            isDealing = false
            // A deal is still worth hearing when it is over before it starts.
            // `animated: false` is the door the tests come in by and stays
            // silent, so no test run builds an audio engine.
            if animated {
                SoundManager.play(.shuffle, enabled: settings.soundsEnabled)
            }
            saveGame()
        }
    }

    func restartDeal() {
        newGame(seed: seed)
    }

    private func runDealAnimation(generation: Int) async {
        SoundManager.play(.shuffle, enabled: settings.soundsEnabled)
        try? await Task.sleep(for: .milliseconds(150))
        for (row, column) in GameState.dealSteps {
            guard generation == dealGeneration else { return }
            withAnimation(.snappy(duration: 0.28)) {
                guard var card = state.stock.popLast() else { return }
                card.isFaceUp = row == column
                state.tableaus[column].append(card)
            }
            if row == column {
                SoundManager.play(.place, enabled: settings.soundsEnabled)
            }
            try? await Task.sleep(for: .milliseconds(34))
        }
        guard generation == dealGeneration else { return }
        isDealing = false
        // `saveGame` skips anything mid-animation, so without this the deal is
        // only written once the player moves. Force-quit before that and the
        // deal number is gone — along with, in Vegas, a buy-in already on screen.
        saveGame()
    }

    /// Closing out the deal being replaced: record the loss if it was under
    /// way, and settle its Vegas balance.
    ///
    /// The Vegas buy-in is settled even for a deal the player never touched.
    /// The HUD shows the -$52 the moment the cards are dealt, so charging only
    /// once a card moves would let a player deal their way to a comfortable
    /// board for free — and would silently discard a balance already on screen.
    private func finalizeAbandonedGameIfNeeded() {
        guard !isWon else { return }
        if hasStarted { statistics.recordLoss() }
        settleVegasResult()
    }

    /// Adds this deal's Vegas result to the lifetime balance, once.
    private func settleVegasResult() {
        guard scoring.mode == .vegas, !vegasSettled else { return }
        vegasSettled = true
        statistics.addVegasResult(scoring.points)
    }

    // MARK: - Player actions

    /// Tap on the stock (or a stock card): deal cards or recycle the waste.
    /// Returns false when the rules allow neither — an empty stock the player
    /// has no pass left to turn over.
    @discardableResult
    func tapStock() -> Bool {
        guard !interactionLocked else { return false }
        clearHint()
        let acted = drawOrRecycle()
        if !acted {
            Haptics.error(enabled: settings.hapticsEnabled)
        }
        saveGame()
        return acted
    }

    /// Deals from the stock, or turns the waste back over when the stock has
    /// run out. Returns false when the rules allow neither.
    @discardableResult
    private func drawOrRecycle() -> Bool {
        if !state.stock.isEmpty {
            let drawnIDs = state.stock.suffix(drawCount).map(\.id)
            pushUndo(moving: drawnIDs)
            markStarted()
            elevate(drawnIDs)
            withAnimation(Motion.animation(.snappy(duration: 0.3))) {
                _ = state.drawFromStock(count: drawCount)
            }
            moves += 1
            SoundManager.play(.draw, enabled: settings.soundsEnabled)
            Haptics.tap(enabled: settings.hapticsEnabled)
            return true
        } else if canRecycle {
            pushUndo(moving: [])
            markStarted()
            withAnimation(Motion.animation(.snappy(duration: 0.35))) {
                state.recycleWaste()
            }
            // Stops where the undo record stops, so the live count and the
            // saved one can never part company. See `UndoStep.maxRecycles`.
            recyclesUsed = min(recyclesUsed + 1, UndoStep.maxRecycles)
            // `recyclesUsed` counts the turns of the deck and the deal is
            // pass 1, so this recycle begins the pass after it.
            scoring.apply(.recycleWaste(drawCount: drawCount, pass: recyclesUsed + 1))
            moves += 1
            SoundManager.play(.shuffle, enabled: settings.soundsEnabled)
            Haptics.tap(enabled: settings.hapticsEnabled)
            return true
        }
        return false
    }

    /// Tap a card: send it to the best legal spot. Returns false if no move.
    @discardableResult
    func smartMove(cardID: String) -> Bool {
        guard !interactionLocked else { return false }
        clearHint()

        var cardID = cardID
        if let loc = state.location(of: cardID) {
            if loc.pile == .stock {
                return tapStock()
            }
            // The draw-3 fan leaves the two older waste cards half visible, and
            // a tap on one of them means the pile rather than that card. Play
            // the one actually on top instead of buzzing at the player.
            if loc.pile == .waste, let top = state.waste.last {
                cardID = top.id
            }
        }
        // Tapping a face-down card is a no-op, not an error.
        if let card = state.card(withID: cardID), !card.isFaceUp {
            return false
        }
        guard let (run, loc) = state.movableRun(startingAt: cardID) else {
            Haptics.error(enabled: settings.hapticsEnabled)
            return false
        }
        // Taking a card back off a foundation is not progress — neither the hint
        // list nor the dead-end check counts it as a move — so a stray tap on a
        // foundation is a no-op rather than a silent 15-point penalty. Dragging
        // one back is still allowed; that takes deliberate aim.
        if loc.pile.isFoundation { return false }

        // Prefer the foundation for single cards.
        if run.count == 1, let f = state.foundationTarget(for: run[0]) {
            performMove(run: run, from: loc.pile, to: .foundation(f))
            return true
        }

        if let target = MoveAdvisor.bestTableauTarget(for: run, from: loc, in: state) {
            performMove(run: run, from: loc.pile, to: target)
            return true
        }

        Haptics.error(enabled: settings.hapticsEnabled)
        return false
    }

    /// Drag-and-drop entry point. Returns true when the move was legal.
    @discardableResult
    func attemptMove(cardID: String, to target: PileID) -> Bool {
        guard !interactionLocked else { return false }
        clearHint()
        guard let (run, loc) = state.movableRun(startingAt: cardID),
              state.canDrop(run: run, from: loc.pile, on: target) else {
            return false
        }
        performMove(run: run, from: loc.pile, to: target)
        return true
    }

    func undo() {
        guard canUndo, let step = history.popLast() else { return }
        clearHint()
        elevate(step.movedIDs)
        withAnimation(Motion.animation(.snappy(duration: 0.32))) {
            state = step.state
            scoring.points = step.points
            // Taking the move back does not give the time back, so the ticks
            // charged since the step was recorded are charged again. Without
            // this, idling and then pressing undo would pay the penalties out.
            scoring.applyTimePenalty(times: elapsedSeconds / 10 - step.elapsedSeconds / 10)
            moves = step.moves
            recyclesUsed = step.recyclesUsed
        }
        SoundManager.play(.undo, enabled: settings.soundsEnabled)
        Haptics.tap(enabled: settings.hapticsEnabled)
        saveGame()
    }

    func autoFinish() {
        guard canAutoFinish else { return }
        isAutoFinishing = true
        clearHint()
        let generation = dealGeneration
        Task {
            // 52 cards to place plus the draws it takes to reach the ones still
            // in the stock. A deck ordered against the wand needs a pass per
            // card it frees, which works out under 400 steps; the bound is set
            // clear of that so only an unexpected state can stop the run early.
            let limit = 800
            var steps = 0
            while generation == dealGeneration, !state.isWon, steps < limit {
                steps += 1
                switch state.nextAutoFinishStep() {
                case .play(let cardID, let foundation):
                    guard let (run, loc) = state.movableRun(startingAt: cardID) else { steps = limit; break }
                    performMove(run: run, from: loc.pile, to: .foundation(foundation), fast: true)
                    try? await Task.sleep(for: .milliseconds(90))
                case .draw, .recycle:
                    // Recycling costs the same points here as it would by hand:
                    // the wand plays the deal out, it does not play it for free.
                    guard drawOrRecycle() else { steps = limit; break }
                    saveGame()
                    try? await Task.sleep(for: .milliseconds(70))
                case nil:
                    steps = limit
                }
            }
            if generation == dealGeneration {
                isAutoFinishing = false
            }
        }
    }

    // MARK: - Core move

    private func performMove(run: [Card], from source: PileID, to target: PileID, fast: Bool = false) {
        pushUndo(moving: run.map(\.id))
        markStarted()
        elevate(run.map(\.id))

        var flipped = false
        withAnimation(Motion.animation(fast ? .snappy(duration: 0.22) : .snappy(duration: 0.32))) {
            flipped = state.applyMove(run: run, from: source, to: target)
        }

        switch (source, target) {
        case (.waste, .tableau): scoring.apply(.wasteToTableau)
        case (.waste, .foundation): scoring.apply(.wasteToFoundation)
        case (.tableau, .foundation): scoring.apply(.tableauToFoundation)
        case (.foundation, .tableau): scoring.apply(.foundationToTableau)
        default: break
        }
        if flipped {
            scoring.apply(.turnOverTableauCard)
        }
        moves += 1

        if target.isFoundation {
            SoundManager.play(.foundation, enabled: settings.soundsEnabled)
            Haptics.success(enabled: settings.hapticsEnabled)
        } else {
            SoundManager.play(.place, enabled: settings.soundsEnabled)
            Haptics.drop(enabled: settings.hapticsEnabled)
        }

        checkForWin()
        saveGame()
    }

    private func pushUndo(moving movedIDs: [String]) {
        history.push(
            UndoStep(
                state: state, points: scoring.points, moves: moves,
                recyclesUsed: recyclesUsed, elapsedSeconds: elapsedSeconds, movedIDs: movedIDs
            ),
            limit: Self.maxUndoDepth
        )
    }

    /// Keeps the given cards on top of everything for the duration of a move
    /// animation. Each call expires on its own schedule: a second move must not
    /// cut short — or prolong — the elevation of the cards the first one raised.
    private func elevate(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        nextElevationToken += 1
        let token = nextElevationToken
        for id in ids { elevationTokens[id] = token }
        recentlyMoved.formUnion(ids)
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            // A later move may have raised some of these cards again; those
            // keep their own timing and stay up.
            let expired = ids.filter { elevationTokens[$0] == token }
            for id in expired { elevationTokens.removeValue(forKey: id) }
            recentlyMoved.subtract(expired)
        }
    }

    private func markStarted() {
        guard !hasStarted else { return }
        hasStarted = true
        statistics.recordGameStarted()
    }

    private func checkForWin() {
        guard state.isWon, !isWon else { return }
        isWon = true
        isAutoFinishing = false

        if scoring.mode == .standard {
            timeBonus = ScoreKeeper.timeBonus(elapsedSeconds: elapsedSeconds)
            scoring.points += timeBonus
        }
        newRecords = statistics.recordWin(
            drawCount: drawCount,
            timeSeconds: elapsedSeconds,
            moves: moves,
            standardScore: scoring.mode == .standard ? scoring.points : nil
        )
        settleVegasResult()
        clearSavedGame()
        SoundManager.play(.win, enabled: settings.soundsEnabled)
        Haptics.celebrate(enabled: settings.hapticsEnabled)
    }

    // MARK: - Hints

    /// The suggestions this deal currently offers, best first.
    private func hintCandidates() -> [CandidateMove] {
        MoveAdvisor.candidates(for: state, canRecycle: canRecycle)
    }

    func requestHint() {
        guard !interactionLocked else { return }
        let candidates = hintCandidates()
        guard !candidates.isEmpty else {
            showHint(Hint(message: L10n.hintNoMoves))
            return
        }
        lastHintIndex = (lastHintIndex + 1) % candidates.count
        let c = candidates[lastHintIndex]
        showHint(Hint(cardIDs: c.cardIDs, target: c.target, message: c.message))
    }

    private func showHint(_ newHint: Hint) {
        hintClearTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { hint = newHint }
        hintClearTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { hint = nil }
            // The board has not changed, but the cycle has gone cold. Asking
            // again should open with the best suggestion rather than resuming
            // wherever the last request left off.
            lastHintIndex = -1
        }
    }

    private func clearHint() {
        hintClearTask?.cancel()
        if hint != nil {
            hint = nil
        }
        // Every player action changes the board, so the next hint should start
        // again from the best suggestion instead of resuming mid-cycle.
        lastHintIndex = -1
    }

    // MARK: - Timer

    /// Whether the clock should be running. The timer task exists for exactly
    /// as long as this is true and not a second longer.
    private var clockRuns: Bool {
        hasStarted && !isWon && !isPaused && !isDealing && elapsedSeconds < TimeFormat.maxSeconds
    }

    /// Brings the timer into line with `clockRuns`.
    ///
    /// Called from the observers on the flags it reads, so no caller has to
    /// remember it. A timer that runs regardless and lets `tick` throw the
    /// wake-ups away costs nothing on a game being played, but a finished deal
    /// left on the table — or one sitting behind the settings sheet — goes on
    /// waking the app once a second for as long as it is open, with nothing to
    /// do each time.
    private func syncTimer() {
        if clockRuns {
            guard timerTask == nil else { return }
            startTimer()
        } else {
            timerTask?.cancel()
            timerTask = nil
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            // Tick on absolute deadlines: sleeping "for one second" in a loop
            // slowly loses time, which would understate every game's duration.
            var deadline = ContinuousClock.now.advanced(by: .seconds(1))
            while !Task.isCancelled {
                try? await Task.sleep(until: deadline, clock: .continuous)
                guard let self, !Task.isCancelled else { return }
                deadline = deadline.advanced(by: .seconds(1))
                // Resynchronise after the app was suspended for a while.
                let now = ContinuousClock.now
                if deadline < now { deadline = now.advanced(by: .seconds(1)) }
                self.tick()
            }
        }
    }

    /// One second of game time. Split out from the timer so the tests can run
    /// the clock forward — and the scoring penalties with it — without waiting
    /// out a real minute.
    func tick() {
        guard hasStarted, !isWon, !isPaused, !isDealing else { return }
        guard elapsedSeconds < TimeFormat.maxSeconds else { return }
        elapsedSeconds += 1
        if scoring.mode == .standard, elapsedSeconds.isMultiple(of: 10) {
            scoring.applyTimePenalty()
        }
        // Reaching the ceiling stops the clock, and no flag says so.
        if elapsedSeconds == TimeFormat.maxSeconds { syncTimer() }
    }

    // MARK: - Persistence

    private static let savedGameKey = "solitaire.savedGame.v1"

    func saveGame() {
        guard !isWon, !isDealing else { return }
        let saved = SavedGame(
            state: state, seed: seed, drawCount: drawCount, scoring: scoring,
            moves: moves, elapsedSeconds: elapsedSeconds,
            recyclesUsed: recyclesUsed, hasStarted: hasStarted,
            vegasSettled: vegasSettled,
            history: history.packed
        )
        if let data = saved.encoded() {
            defaults.set(data, forKey: Self.savedGameKey)
        }
    }

    private func clearSavedGame() {
        defaults.removeObject(forKey: Self.savedGameKey)
    }

#if DEBUG
    // MARK: - QA scaffolding (simulator only)

    /// Applies launch-argument scenarios used for automated visual testing.
    func applyLaunchScenario() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-scenario-autofinish") { loadAutoFinishScenario() }
        if args.contains("-scenario-autofinish-stock") { loadAutoFinishThroughStockScenario() }
        if args.contains("-scenario-nomoves") { loadStuckScenario() }
        if args.contains("-autoplay") { startAutoplayBot() }
    }

    /// A dead deal: stock and waste empty, no playable card anywhere.
    func loadStuckScenario() {
        dealGeneration += 1
        isDealing = false
        isWon = false
        moves = 12
        recyclesUsed = 0
        hasStarted = true
        scoring = ScoreKeeper(mode: settings.scoringMode)

        // Face-up tops that neither reach a foundation nor stack on each other.
        let tops = [
            Card(suit: .spades, rank: .five, isFaceUp: true),
            Card(suit: .hearts, rank: .five, isFaceUp: true),
            Card(suit: .diamonds, rank: .five, isFaceUp: true),
            Card(suit: .clubs, rank: .five, isFaceUp: true),
            Card(suit: .spades, rank: .nine, isFaceUp: true),
            Card(suit: .hearts, rank: .nine, isFaceUp: true),
            Card(suit: .diamonds, rank: .nine, isFaceUp: true),
        ]
        var buried = Card.orderedDeck.filter { card in !tops.contains(where: { $0.id == card.id }) }
        var s = GameState()
        for column in 0..<7 {
            let depth = column < 4 ? 6 : 7
            s.tableaus[column] = (0..<depth).map { _ in buried.removeLast() } + [tops[column]]
        }
        state = s
        history.removeAll()
    }

    /// Everything face up, one wand-tap from victory.
    func loadAutoFinishScenario() {
        dealGeneration += 1
        isDealing = false
        isWon = false
        moves = 0
        // A plausible clock so the results screen shows a real time and,
        // under standard scoring, a real time bonus.
        elapsedSeconds = 95
        recyclesUsed = 0
        hasStarted = false
        scoring = ScoreKeeper(mode: settings.scoringMode)
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
        state = s
        history.removeAll()
    }

    /// Every tableau card face up but eight cards still to come out of the
    /// stock: the wand has to work the deck as well as the columns.
    func loadAutoFinishThroughStockScenario() {
        dealGeneration += 1
        isDealing = false
        isWon = false
        moves = 0
        elapsedSeconds = 95
        recyclesUsed = 0
        hasStarted = false
        scoring = ScoreKeeper(mode: settings.scoringMode)

        var s = GameState()
        for (f, suit) in Suit.allCases.enumerated() {
            s.foundations[f] = Rank.allCases.prefix(11).map { Card(suit: suit, rank: $0, isFaceUp: true) }
        }
        s.tableaus[0] = [Card(suit: .spades, rank: .queen, isFaceUp: true)]
        s.tableaus[3] = [Card(suit: .hearts, rank: .queen, isFaceUp: true)]
        s.stock = [Card(suit: .diamonds, rank: .king), Card(suit: .clubs, rank: .queen),
                   Card(suit: .spades, rank: .king), Card(suit: .diamonds, rank: .queen)]
        s.waste = [Card(suit: .hearts, rank: .king, isFaceUp: true),
                   Card(suit: .clubs, rank: .king, isFaceUp: true)]
        state = s
        history.removeAll()
    }

    /// Plays the game by itself through the same code paths a player uses.
    private func startAutoplayBot() {
        Task {
            var actions = 0
            // Every board the bot has already played from.
            //
            // The suggestion list puts drawing from the stock ahead of the
            // tableau shuffling that rarely gets anyone anywhere, which is the
            // right order for a player and a trap for a bot: on a board whose
            // only moves are turning the deck over, the bot goes round the deck
            // for as long as its budget lasts and the position never changes. A
            // board it has played from before is that loop closing, and nothing
            // a real game reaches twice — the bot never undoes, and no
            // suggestion ever takes a card back off a foundation.
            var seen: Set<Data> = []
            while !isWon, actions < 300 {
                try? await Task.sleep(for: .milliseconds(200))
                guard !isDealing, !isAutoFinishing else { continue }
                if canAutoFinish {
                    autoFinish()
                    continue
                }
                guard seen.insert(state.packed).inserted else { break }
                // Take the top suggestion, whatever it is. Cherry-picking card
                // moves out of the list would have the bot shuffling the
                // tableau where a player would simply turn the deck over.
                guard let move = hintCandidates().first else { break }
                if let target = move.target, let head = move.cardIDs.first {
                    attemptMove(cardID: head, to: target)
                } else {
                    tapStock()
                }
                actions += 1
            }
        }
    }
#endif

    private func restoreSavedGame() -> Bool {
        guard let data = defaults.data(forKey: Self.savedGameKey) else { return false }
        guard let saved = SavedGame.decode(data) else {
            // Unreadable bytes, a board the rules could not have produced, or a
            // game that was already won: none of it is worth carrying forward,
            // and leaving it in place would only fail again at every launch.
            clearSavedGame()
            return false
        }
        state = saved.state
        seed = saved.seed
        drawCount = saved.drawCount
        scoring = saved.scoring
        moves = saved.moves
        elapsedSeconds = saved.elapsedSeconds
        // An older build counted past what a record can hold; bring it back
        // inside the range rather than letting undo restore a different figure.
        recyclesUsed = min(saved.recyclesUsed, UndoStep.maxRecycles)
        hasStarted = saved.hasStarted
        vegasSettled = saved.vegasSettled ?? false
        // `decode` has already thrown out a history that did not check out;
        // reading it back through the same door is the belt to that braces.
        history = saved.history.flatMap(UndoHistory.init(packed:)) ?? UndoHistory()
        return true
    }
}
