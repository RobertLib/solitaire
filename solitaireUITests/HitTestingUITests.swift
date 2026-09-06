//
//  HitTestingUITests.swift
//  solitaireUITests
//
//  The one thing none of the other checks in this project can see.
//
//  `simctl` cannot tap, and every unit test reaches the model directly and asks
//  it to make a move — so a pile whose tap area is the wrong size is invisible
//  to all of them. That is how the stock came to answer taps anywhere on the
//  table and stayed that way through two releases: the model was right about
//  every move it was asked to make, and nothing ever asked it the way a finger
//  does. These cases do.
//
//  SwiftUI makes this a correctness matter rather than a matter of taste:
//  `.position` claims all the space it is offered, so a `.contentShape` applied
//  after it is a board-sized hit area rather than a card-sized one, and the
//  board draws every pile through `.position`.
//

import XCTest

// Every `XCUIApplication` and `XCUIElement` member below is main-actor
// isolated, so without this the target compiles with a concurrency warning per
// line that touches one. The test targets cannot take
// `SWIFT_DEFAULT_ACTOR_ISOLATION` from the app — `XCTestCase`'s initialisers
// are nonisolated and every subclass's inherited init would conflict — so the
// classes say it themselves, as `solitaireTests` already does.
@MainActor
final class HitTestingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The app on a fixed board: four cards left in the stock, two lone cards in
    /// the columns, and the rest of the table bare — so a tap that lands where
    /// nothing is has plenty of room to go wrong, and dealing is the thing that
    /// goes wrong first.
    ///
    /// The scenario also skips the deal animation, so nothing here has to wait
    /// out the cards flying to their places before it can tap.
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-scenario-autofinish-stock",
            // Piles are found by name below, so the language is pinned rather
            // than left to whatever the runner's simulator happens to be set to.
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    /// The move counter out of the status bar, which is the shortest way to ask
    /// the app whether a tap did anything at all.
    private func moves(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> String? {
        let counter = app.descendants(matching: .any)["hud.moves"]
        XCTAssertTrue(counter.waitForExistence(timeout: 30), "the move counter never appeared", file: file, line: line)
        return counter.value as? String
    }

    func testATapOnBareFeltPlaysNothing() {
        let app = launch()
        XCTAssertEqual(moves(app), "0", "the scenario starts with no moves made")

        // The middle of the table on this board is felt and nothing else. A pile
        // that had quietly grown to the size of the board would answer here, and
        // the stock answers by dealing a card — which is a move.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()

        XCTAssertEqual(moves(app), "0", "a tap on bare felt played something")
    }

    func testTappingTheStockDeals() {
        let app = launch()
        let stock = app.descendants(matching: .any)["Stock"]
        XCTAssertTrue(stock.waitForExistence(timeout: 30), "the stock never appeared")

        // Card-sized, not board-sized. A pile that had claimed the whole board
        // would be centred on the board, and this says so before the tap does —
        // the tap below would then land in the middle of the table and pass for
        // the wrong reason.
        XCTAssertLessThan(stock.frame.width, app.frame.width * 0.4, "the stock is wider than a card")
        XCTAssertLessThan(stock.frame.height, app.frame.height * 0.4, "the stock is taller than a card")

        stock.tap()
        XCTAssertEqual(moves(app), "1", "tapping the stock did not deal")
    }

    /// A card by rank and suit, whatever the label puts between them.
    ///
    /// The piles above are matched by their whole label because that label is
    /// the whole string; a card's is assembled from a rank, a suit, the pile it
    /// is lying on and the punctuation the translator chose to join them with.
    /// Matching on the two halves that name the card keeps these cases about
    /// where the card is rather than about how it is read out.
    private func card(_ app: XCUIApplication, _ rank: String, _ suit: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", rank, suit))
            .firstMatch
    }

    /// Tap-to-move, through a finger.
    ///
    /// The other cases here tap piles, and a pile is a placeholder with a
    /// `contentShape` of its own. A card is the one thing on the board carrying
    /// both an `onTapGesture` and a `DragGesture`, both applied after
    /// `.position` — the modifier order this file exists to hold to account —
    /// and until now nothing tapped one. The board leaves the queen of spades
    /// alone in column 1 with its foundation already up to the jack, so the tap
    /// has somewhere to go.
    func testTappingACardMovesIt() {
        let app = launch()
        XCTAssertEqual(moves(app), "0", "the scenario starts with no moves made")

        let queen = card(app, "Queen", "Spades")
        XCTAssertTrue(queen.waitForExistence(timeout: 30), "the queen of spades is not on the board")
        // Card-sized, for the same reason the stock is measured before it is
        // tapped: a card that had claimed the board would be tapped at the
        // centre of the board and pass for the wrong reason.
        XCTAssertLessThan(queen.frame.width, app.frame.width * 0.4, "the queen is wider than a card")

        queen.tap()
        XCTAssertEqual(moves(app), "1", "tapping a card did not move it")
    }

    /// The same card again, dragged rather than tapped — the other half of the
    /// gesture pair, and the half a tap cannot prove works.
    func testDraggingACardMovesIt() {
        let app = launch()
        XCTAssertEqual(moves(app), "0", "the scenario starts with no moves made")

        let queen = card(app, "Queen", "Spades")
        XCTAssertTrue(queen.waitForExistence(timeout: 30), "the queen of spades is not on the board")
        // The jack on top of the spade foundation, not the foundation itself:
        // the placeholder is buried under eleven cards and cannot be dropped
        // on, which is exactly where a player aims anyway.
        let jack = card(app, "Jack", "Spades")
        XCTAssertTrue(jack.waitForExistence(timeout: 30), "the spade foundation is not on the board")

        queen.press(forDuration: 0.1, thenDragTo: jack)
        XCTAssertEqual(moves(app), "1", "dragging a card did not move it")
    }

    /// Every pile the reader is offered has to be somewhere in particular.
    func testEveryPileIsCardSized() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["Stock"].waitForExistence(timeout: 30))

        var names = ["Stock", "Waste"]
        names += (1...4).map { "Foundation \($0)" }
        names += (1...7).map { "Column \($0)" }
        for name in names {
            let pile = app.descendants(matching: .any)[name]
            XCTAssertTrue(pile.exists, "\(name) is not on the board at all")
            XCTAssertLessThan(pile.frame.width, app.frame.width * 0.4, "\(name) is wider than a card")
        }
    }
}
