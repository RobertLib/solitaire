//
//  ScreenshotScenes.swift
//  solitaire
//
//  Deterministic poses for the App Store screenshots and the App Preview,
//  picked by `-shot <name>`. The shot list lives in AppStore/screenshots.md and
//  the script that drives them in Tools/appstore_media.sh.
//
//  The whole file is Debug-only, so none of it reaches an App Store build.
//
//  A pose is a *real* deal that happens to come out the same way every time,
//  not a mocked board: a numbered deal, played forward by the app's own move
//  advisor — the same suggestions the Hint button offers, taken best first.
//  That matters, because a mocked board drifts away from the game as the game
//  changes, whereas a pose built out of legal moves either still plays or stops
//  rendering, and the score, the clock and the move count on it are the ones
//  the deal actually earned.
//
//  The seeds come from compiling the engine on its own — the same trick
//  Tests/run.sh uses — and playing it through hundreds of thousands of deals,
//  scoring each board on what photographs well: cards on all four foundations,
//  a waste fan, no empty column, something still face down to look at. Three of
//  them are rarer than that. The dead-end board had to be a deal the advisor
//  plays to a position with no legal move anywhere, recycling included, and with
//  a score still on it — two deals in two hundred thousand. The wand and the win
//  are the same deal, one stopping where the win becomes certain and the other
//  tapping the wand, which is about one deal in a hundred.
//
//  Unlike a hand of poker, a pose here is built *synchronously* — the deal is
//  laid out unanimated and the moves are applied one after another before the
//  first frame is drawn — so nothing has to wait for the game to get anywhere.
//  What the marker below waits out is only SwiftUI settling: a sheet presenting,
//  the wand springing in, the victory cascade landing.
//
//  These poses write settings, statistics and a saved game to UserDefaults like
//  any other play would. That is why Tools/appstore_media.sh reinstalls the app
//  before a run and why this file is Debug-only: it is meant for a throwaway
//  simulator, not for the device in your pocket.
//
#if DEBUG
import Foundation

// MARK: - Pose

/// One posed screen: the deal to lay out, how far to play it, the rules and
/// appearance to set, and how long to let the animations land before saying the
/// shot is ready.
struct ShotScene {
    /// The deal to pose, by the number the game itself gives it.
    var seed: UInt64
    /// Advisor moves to play into it, best suggestion first.
    var plays: Int
    var drawCount = 3
    var scoring: ScoringMode = .standard
    var vegasCumulative = false
    var theme: TableTheme = .forest
    var cardBack: CardBackStyle = .crimson

    /// Seconds to put on the clock afterwards, charged tick by tick so the
    /// standard scoring penalties land exactly as they would in a real game.
    var clock = 0
    /// Lifetime Vegas balance to bank before the shot, for the deals that show
    /// a running balance rather than one deal's dollars.
    var vegasBalance = 0
    /// Fill the statistics table in.
    var statistics = false
    /// Keep a hint ring on the board.
    var hint = false
    /// How long to let SwiftUI settle before the shot is declared ready.
    var settle = 1.4
    /// Tap the auto-finish wand this many seconds in. The win screen and the
    /// preview's cascade both come from this rather than from a faked win.
    var wandAfter: Double?
}

// MARK: - Catalogue

enum Shots {

    /// `-shot <name>`, or nil in an ordinary run.
    static var requestedName: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-shot"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static let catalogue: [String: ShotScene] = [

        // 1 — the hero shot, and the one that has to read as solitaire in a
        // quarter of a second. Deal 16371 at draw 3, thirty-four moves in: all
        // four foundations open, every column still holding something and three
        // cards fanned on the waste.
        "01-board": ShotScene(
            seed: 16371, plays: 34,
            clock: 218),

        // 2 — the payoff, and where the "no ads" caption goes. Deal 6477 is one
        // of the roughly one in a hundred the advisor plays all the way to the
        // point where the win can no longer be lost: half the deck up on the
        // foundations, eighty-two moves and a score of 405 on the board, and the
        // wand offering to play out the rest.
        "02-autofinish": ShotScene(
            seed: 6477, plays: 82,
            drawCount: 1,
            theme: .midnight,
            cardBack: .royal,
            clock: 292,
            settle: 1.8),

        // 3 — the feature nobody else in the category has. Deal 105909 is one of
        // two deals in two hundred thousand that the advisor plays to a genuine
        // dead end with a score still on the board: eighty-eight moves, stock and
        // waste both empty, twenty-four cards home, seven still face down, and
        // not one legal move anywhere.
        "03-stuck": ShotScene(
            seed: 105909, plays: 88,
            clock: 301,
            settle: 1.8),

        // 4 — a hint ring on a card. Deal 5803 was picked for the one property
        // that matters here: thirty moves in, the *top* suggestion is a card
        // move rather than "draw from the stock", so the ring lands on the board
        // instead of on the deck.
        "04-hint": ShotScene(
            seed: 5803, plays: 30,
            drawCount: 1,
            theme: .ocean,
            cardBack: .emerald,
            clock: 164,
            hint: true,
            settle: 0.4),

        // 5 — Vegas, with a balance that carries between deals. Deal 14650 at
        // draw 3, where the waste fan is eight deep and the felt is wine.
        "05-vegas": ShotScene(
            seed: 14650, plays: 34,
            scoring: .vegas,
            vegasCumulative: true,
            theme: .wine,
            cardBack: .night,
            clock: 262,
            vegasBalance: 332),

        // 6 — the results screen. The same deal as shot 2, with the wand
        // actually tapped, so the time, the move count and the time bonus on the
        // panel are the ones a hundred and fourteen real moves earned rather
        // than numbers written into a mock.
        "06-win": ShotScene(
            seed: 6477, plays: 82,
            drawCount: 1,
            clock: 292,
            settle: 6.5,
            wandAfter: 0.4),

        // 7 and 8 — the two sheets. They are opened by `-open-stats` /
        // `-open-settings`, which ContentView already handles; the pose only has
        // to put something worth reading on them and a board worth glimpsing
        // behind them.
        "07-stats": ShotScene(
            seed: 16371, plays: 34,
            clock: 218,
            vegasBalance: 332,
            statistics: true,
            settle: 2.2),

        "08-settings": ShotScene(
            seed: 16371, plays: 20,
            scoring: .vegas,
            vegasCumulative: true,
            theme: .ocean,
            cardBack: .emerald,
            settle: 2.2),

        // App Preview clips. These need motion, so `preview-play` is dealt
        // *animated* — the staggered deal is the opening shot — and handed to
        // the advisor bot with `-autoplay`, which takes the top suggestion once
        // every 200 ms, about the pace of somebody who knows what they are
        // doing.
        //
        // Deal 27122 was picked for one reason: the bot stops the moment a board
        // comes round twice, and most deals stall inside a minute. This one runs
        // 120 moves before the win is even certain — twenty-four seconds of
        // continuous play, which is longer than the usable part of a simulator
        // recording. The clock starts at zero and counts up through the clip,
        // because that is the one number in the HUD a still frame cannot show
        // moving.
        "preview-play": ShotScene(
            seed: 27122, plays: 0,
            settle: 0),

        // The cascade: deal 6477 at the wand again, tapped two seconds in so the
        // clip opens on a board rather than on cards already in flight. Thirty-two
        // cards fly home, and then the confetti.
        "preview-finish": ShotScene(
            seed: 6477, plays: 82,
            drawCount: 1,
            theme: .midnight,
            cardBack: .royal,
            clock: 292,
            settle: 0,
            wandAfter: 2.0),
    ]

    // MARK: - Applying a pose

    /// Builds the requested pose. Called from `AppModel.init`, after the game
    /// exists and before the first frame is drawn.
    static func apply(settings: GameSettings, statistics: Statistics, game: GameViewModel) {
        guard let name = requestedName, let scene = catalogue[name] else { return }
        clearReadyMarker()

        // Appearance and rules first: the draw count and the scoring mode are
        // read when a deal is dealt, so they have to be in place before one is.
        settings.drawCount = scene.drawCount
        settings.scoringMode = scene.scoring
        settings.vegasCumulative = scene.vegasCumulative
        settings.tableTheme = scene.theme
        settings.cardBack = scene.cardBack
        settings.leftHandMode = false
        // Left on. The settings sheet is one of the shots, and two switches
        // photographed in the off position is not the impression to give — the
        // simulator's audio never reaches a screenshot, and the App Preview
        // replaces the whole audio track with the music bed anyway.
        settings.soundsEnabled = true
        settings.hapticsEnabled = true

        // Animated only for the preview clip, which wants the deal to fly in.
        // A screenshot wants the board already there.
        let animated = ProcessInfo.processInfo.arguments.contains("-autoplay")
        game.newGame(seed: scene.seed, animated: animated)
        playForward(game, moves: scene.plays)

        // The clock is wound forward a second at a time rather than assigned,
        // so a standard-scoring pose carries the −2 every ten seconds it would
        // have been charged had someone really sat there that long.
        for _ in 0..<scene.clock { game.tick() }

        // Last, and always — not only when a pose asks for a table. Dealing a
        // board counts a game as started and settles the previous deal's Vegas
        // result, and the shots run one after another against one install, so a
        // pose that did not clear the slate would photograph whatever the shot
        // before it happened to leave behind.
        statistics.reset()
        if scene.statistics {
            fillStatistics(statistics)
        }
        if scene.vegasBalance != 0 {
            statistics.addVegasResult(scene.vegasBalance)
        }

        if scene.hint {
            keepHintOnScreen(game)
        }
        if let delay = scene.wandAfter {
            wandTask = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                game.autoFinish()
            }
        }
        if scene.settle > 0 {
            markReady(after: scene.settle)
        }
    }

    /// Plays `moves` advisor moves, taking the top suggestion every time.
    ///
    /// Deliberately the same rule the autoplay bot follows: cherry-picking card
    /// moves out of the list would have the pose shuffling the tableau where a
    /// player would simply turn the deck over, and the board would stop looking
    /// like one somebody had played. The loop stops early rather than looping
    /// if a board ever comes round twice, which is how a changed advisor
    /// announces itself instead of hanging the launch.
    private static func playForward(_ game: GameViewModel, moves: Int) {
        var seen: Set<Data> = []
        for _ in 0..<moves {
            guard seen.insert(game.state.packed).inserted else { return }
            let candidates = MoveAdvisor.candidates(for: game.state, canRecycle: game.canRecycle)
            guard let move = candidates.first else { return }
            if let target = move.target, let head = move.cardIDs.first {
                guard game.attemptMove(cardID: head, to: target) else { return }
            } else {
                guard game.tapStock() else { return }
            }
        }
    }

    /// A hint fades after 2.6 s, which is shorter than the round trip between
    /// the marker being written and the screenshot being taken. So the ring is
    /// asked for again every two seconds, and the shot is declared ready almost
    /// immediately after the first request — early enough that the picture is
    /// normally the *first* suggestion, and if the script is having a slow day
    /// it is the second rather than an empty board.
    private static func keepHintOnScreen(_ game: GameViewModel) {
        game.requestHint()
        hintTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                game.requestHint()
            }
        }
    }

    /// Owners for the two tasks a pose can leave running. Nothing else holds
    /// them, and a `Task` whose only reference goes out of scope is cancelled at
    /// the first suspension point — which is before either has done anything.
    /// One shot per launch, so one slot each is enough.
    private static var hintTask: Task<Void, Never>?
    private static var wandTask: Task<Void, Never>?

    /// A statistics table worth photographing.
    ///
    /// Built by playing the real bookkeeping rather than by writing the numbers
    /// in: 56 abandoned deals, then runs of 9, 8, 6 and 4 wins with a loss
    /// between them, and the two record deals on the end of the last run. That
    /// gives 88 played, 29 won, a 33% win rate, a current streak of 6 and a best
    /// of 9 — figures that cannot contradict each other, because the same code
    /// produced them that produces a real player's.
    private static func fillStatistics(_ statistics: Statistics) {
        statistics.reset()

        func loss() {
            statistics.recordGameStarted()
            statistics.recordLoss()
        }
        func win(draw: Int, time: Int, moves: Int, score: Int?) {
            statistics.recordGameStarted()
            statistics.recordWin(drawCount: draw, timeSeconds: time, moves: moves,
                                 standardScore: score)
        }

        for _ in 0..<56 { loss() }
        // Ordinary wins, deliberately worse than the records below on every
        // count, so the bests come from the two deals meant to set them.
        let runs = [9, 8, 6, 4]
        var played = 0
        for (index, length) in runs.enumerated() {
            if index > 0 { loss() }
            for step in 0..<length {
                played += 1
                let draw = played.isMultiple(of: 2) ? 3 : 1
                win(draw: draw,
                    time: 380 + step * 17,
                    moves: 190 + step * 6,
                    score: 1_200 + step * 40)
            }
        }
        // The two record deals. They are inside the last run, so the streak
        // that follows them is the one on screen.
        win(draw: 1, time: 143, moves: 108, score: 3_420)
        win(draw: 3, time: 251, moves: 141, score: 2_615)
    }

    // MARK: - Readiness marker

    /// The app drops this file when the shot is on screen, and
    /// `wait_ready` in Tools/appstore_media.sh waits for it. A pose is built
    /// before the first frame, so this only has to outlast the animations —
    /// but the length of those differs per shot and per device, and a script
    /// that slept for a guess would photograph a sheet halfway up.
    private static let readyMarker = URL.documentsDirectory.appending(path: "shot-ready")

    static func clearReadyMarker() {
        try? FileManager.default.removeItem(at: readyMarker)
    }

    static func markReady(after delay: Double) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            try? Data().write(to: readyMarker)
        }
    }
}
#endif
