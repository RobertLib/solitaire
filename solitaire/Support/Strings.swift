//
//  Strings.swift
//  solitaire
//
//  Centralised UI strings. Every string goes through `String(localized:)`, so
//  the compiler exports it to Localizable.xcstrings and a translation can be
//  dropped in without touching any call site.
//

import Foundation

enum L10n {
    // MARK: - General
    static let appTitle = String(localized: "Solitaire")
    static let menu = String(localized: "Menu")
    static let done = String(localized: "Done")
    static let cancel = String(localized: "Cancel")
    static let close = String(localized: "Close")

    // MARK: - Game actions
    static let newGame = String(localized: "New Game")
    static let restartDeal = String(localized: "Restart This Deal")
    static let resume = String(localized: "Resume")
    static let undo = String(localized: "Undo")
    static let hint = String(localized: "Hint")
    static let autoFinish = String(localized: "Auto-finish")
    static let settings = String(localized: "Settings")
    static let statistics = String(localized: "Statistics")
    static let howToPlay = String(localized: "How to Play")
    static func dealNumber(_ n: String) -> String { String(localized: "Deal #\(n)") }

    // MARK: - HUD
    static let score = String(localized: "Score")
    static let time = String(localized: "Time")
    static let moves = String(localized: "Moves")
    static let balance = String(localized: "Balance")

    // MARK: - Hints
    static let hintDrawStock = String(localized: "Draw from the stock")
    static let hintRecycle = String(localized: "Recycle the waste pile")
    static let hintNoMoves = String(localized: "No useful moves found")

    // MARK: - Dead end
    static let noMovesLeft = String(localized: "No moves left")
    static let noMovesLeftDetail = String(localized: "Take a move back or start a new deal.")
    // Offered when there is nothing to take back: a save whose undo history
    // did not survive validation is dropped, and the deal it belongs to can
    // still be played on to a dead end.
    static let noMovesLeftDetailNoUndo = String(localized: "Start a new deal to keep playing.")

    // MARK: - Win screen
    static let youWon = String(localized: "You Won!")
    static let congratulations = String(localized: "Congratulations — the deal is complete.")
    static let newRecord = String(localized: "New record!")
    static let playAgain = String(localized: "Play Again")
    static let replayDeal = String(localized: "Replay This Deal")
    static let thisDeal = String(localized: "This deal")
    static let timeBonus = String(localized: "Time bonus")

    // MARK: - Settings
    static let gameplay = String(localized: "Gameplay")
    static let draw = String(localized: "Draw")
    static let drawOne = String(localized: "Draw 1")
    static let drawThree = String(localized: "Draw 3")
    static let scoring = String(localized: "Scoring")
    static let scoringNone = String(localized: "None")
    static let scoringStandard = String(localized: "Standard")
    static let scoringVegas = String(localized: "Vegas")
    static let vegasCumulative = String(localized: "Cumulative Vegas balance")
    static let vegasCumulativeFooter = String(localized: "Your Vegas winnings carry over between games.")
    static let appliesNextDeal = String(localized: "Changes apply to the next deal.")
    static let leftHandMode = String(localized: "Left-handed layout")
    static let appearance = String(localized: "Appearance")
    static let tableTheme = String(localized: "Table")
    static let cardBack = String(localized: "Card back")
    static let feedback = String(localized: "Sound & Haptics")
    static let sounds = String(localized: "Sounds")
    static let haptics = String(localized: "Haptics")

    // MARK: - Theme names
    static let themeForest = String(localized: "Classic Green")
    static let themeMidnight = String(localized: "Midnight")
    static let themeOcean = String(localized: "Ocean")
    static let themeWine = String(localized: "Wine")

    // MARK: - Card back names
    static let backCrimson = String(localized: "Crimson")
    static let backRoyal = String(localized: "Royal Blue")
    static let backEmerald = String(localized: "Emerald")
    static let backNight = String(localized: "Night Sky")

    // MARK: - Statistics
    static let gamesPlayed = String(localized: "Games played")
    static let gamesWon = String(localized: "Games won")
    static let winRate = String(localized: "Win rate")
    static let currentStreak = String(localized: "Current streak")
    static let bestStreak = String(localized: "Best streak")
    static let bestTime = String(localized: "Best time")
    static let fewestMoves = String(localized: "Fewest moves")
    static let bestScore = String(localized: "Best score")
    static let vegasBalance = String(localized: "Vegas balance")
    static let resetStats = String(localized: "Reset Statistics")
    static let resetStatsConfirm = String(localized: "This permanently clears all statistics.")
    static let reset = String(localized: "Reset")

    // MARK: - How to play
    static let helpObjectiveTitle = String(localized: "Objective")
    static let helpObjective = String(localized: "Move all 52 cards to the four foundations, building each suit up from Ace to King.")
    static let helpTableauTitle = String(localized: "Tableau")
    static let helpTableau = String(localized: "Build the seven columns downward in alternating colors (red on black, black on red). Any face-up run can be moved as a group. Only a King may be placed on an empty column. Turning over a face-down card opens up new moves.")
    static let helpStockTitle = String(localized: "Stock & Waste")
    static let helpStock = String(localized: "Tap the stock to deal cards onto the waste pile. Only the top waste card is playable. When the stock runs out, tap it again to recycle the waste (Vegas rules limit the number of passes).")
    static let helpControlsTitle = String(localized: "Controls")
    static let helpControls = String(localized: "Drag cards to move them, or simply tap a card to send it to the best spot automatically. Use Undo freely — every move can be taken back. The wand button finishes the game for you once every card is face up.")
    static let helpScoringTitle = String(localized: "Scoring")
    static let helpScoring = String(localized: "Standard: +10 for each card moved to a foundation, +5 for waste-to-column moves and for turning over a card; recycling the stock costs points. Vegas: you buy the deck for $52 and earn $5 for every card you place on a foundation.")

    // MARK: - Accessibility
    static let faceDownCard = String(localized: "Face-down card")
    static let stockPile = String(localized: "Stock")
    static let wastePile = String(localized: "Waste")
    static func foundationPile(_ n: Int) -> String { String(localized: "Foundation \(n)") }
    static let emptyPile = String(localized: "Empty")
    static func tableauPile(_ n: Int) -> String { String(localized: "Column \(n)") }
    // A card read out together with the pile it is sitting on, so VoiceOver
    // says where it is: "Ace — Spades, Column 3". One phrase per kind of pile
    // rather than a separator, so translators get the whole sentence.
    static func cardInStock(_ card: String) -> String { String(localized: "\(card), in the stock") }
    static func cardInWaste(_ card: String) -> String { String(localized: "\(card), on the waste") }
    static func cardInFoundation(_ card: String, _ n: Int) -> String { String(localized: "\(card), on foundation \(n)") }
    static func cardInColumn(_ card: String, _ n: Int) -> String { String(localized: "\(card), in column \(n)") }
    // Both carry plural variations in the catalog, so VoiceOver says "1 card"
    // rather than "1 cards" — and a translator gets one bucket per plural form
    // their language distinguishes instead of a single fixed phrase.
    static func cardsRemaining(_ n: Int) -> String { String(localized: "\(n) cards") }
    static func faceDownCount(_ n: Int) -> String { String(localized: "\(n) face down") }
    static let cardMoveHint = String(localized: "Double tap to move this card to the best spot")
    static let stockDrawHint = String(localized: "Double tap to draw")
    static let stockRecycleHint = String(localized: "Double tap to recycle the waste pile")
    // Named destinations offered as VoiceOver actions. A double tap plays the
    // best spot, which is the right default and the wrong only option: a reader
    // who wants this card on *that* column has no way to say so by touch, so
    // every legal destination is offered by name instead.
    static let moveToFoundation = String(localized: "Move to a foundation")
    static func moveToColumn(_ n: Int) -> String { String(localized: "Move to column \(n)") }

    static func rankName(_ rank: Rank) -> String {
        switch rank {
        case .ace: return String(localized: "Ace")
        case .two: return String(localized: "Two")
        case .three: return String(localized: "Three")
        case .four: return String(localized: "Four")
        case .five: return String(localized: "Five")
        case .six: return String(localized: "Six")
        case .seven: return String(localized: "Seven")
        case .eight: return String(localized: "Eight")
        case .nine: return String(localized: "Nine")
        case .ten: return String(localized: "Ten")
        case .jack: return String(localized: "Jack")
        case .queen: return String(localized: "Queen")
        case .king: return String(localized: "King")
        }
    }

    static func suitName(_ suit: Suit) -> String {
        switch suit {
        case .spades: return String(localized: "Spades")
        case .hearts: return String(localized: "Hearts")
        case .diamonds: return String(localized: "Diamonds")
        case .clubs: return String(localized: "Clubs")
        }
    }
}
