//
//  MoveAdvisor.swift
//  solitaire
//
//  Picks the moves the game offers on the player's behalf: the hint cycle, the
//  destination a tapped card flies to, and the moves the autoplay bot makes.
//  No UI dependency, so the agreement between these suggestions and the engine's
//  own dead-end verdict can be asserted from the command-line tests.
//

import Foundation

/// A move the game is prepared to suggest.
///
/// `target` is nil only for the stock, which is not a destination anything is
/// dropped on — `message` carries the instruction instead.
struct CandidateMove: Equatable {
    var cardIDs: [String]
    var source: PileID
    var target: PileID?
    var message: String?
}

enum MoveAdvisor {
    /// Identifies a suggested move, so the same one is never offered twice in
    /// the hint cycle when two categories both turn it up.
    private struct HintKey: Hashable {
        var head: String?
        var target: PileID?
    }

    /// Ordered list of suggested moves, best first.
    ///
    /// The last category makes the list agree with `GameState.hasLegalMove`:
    /// whenever the board still has a move in it the hint finds one, so the
    /// suggestion and the dead-end banner can never contradict each other.
    /// `canRecycle` must be the same answer the caller gives `hasLegalMove`.
    static func candidates(for state: GameState, canRecycle: Bool) -> [CandidateMove] {
        var result: [CandidateMove] = []
        var seen: Set<HintKey> = []

        func add(_ move: CandidateMove) {
            guard seen.insert(HintKey(head: move.cardIDs.first, target: move.target)).inserted else { return }
            result.append(move)
        }

        // 1. Tableau tops to foundations.
        for (i, pile) in state.tableaus.enumerated() {
            // `isFaceUp` cannot be false on a board the rules produced, and
            // `hasLegalMove` asks for it too — the two have to agree even on
            // a board that came from somewhere else.
            guard let top = pile.last, top.isFaceUp,
                  let f = state.foundationTarget(for: top) else { continue }
            add(CandidateMove(cardIDs: [top.id], source: .tableau(i), target: .foundation(f)))
        }
        // 2. Waste top to a foundation.
        if let top = state.waste.last, let f = state.foundationTarget(for: top) {
            add(CandidateMove(cardIDs: [top.id], source: .waste, target: .foundation(f)))
        }
        // 3. Tableau runs whose move exposes a face-down card or frees a column for a waiting king.
        for (i, pile) in state.tableaus.enumerated() {
            guard let firstFaceUp = pile.firstIndex(where: { $0.isFaceUp }) else { continue }
            let run = Array(pile[firstFaceUp...])
            guard let head = run.first else { continue }
            let uncoversSomething = firstFaceUp > 0
            let freesColumnForKing = firstFaceUp == 0 && head.rank != .king && kingIsWaiting(in: state)
            guard uncoversSomething || freesColumnForKing else { continue }
            for j in 0..<7 where j != i && state.canPlace(head, onTableau: j) && !state.tableaus[j].isEmpty {
                add(CandidateMove(cardIDs: run.map(\.id), source: .tableau(i), target: .tableau(j)))
                break
            }
            if head.rank == .king && uncoversSomething,
               let j = (0..<7).first(where: { $0 != i && state.tableaus[$0].isEmpty }) {
                add(CandidateMove(cardIDs: run.map(\.id), source: .tableau(i), target: .tableau(j)))
            }
        }
        // 4. Waste top to a tableau pile.
        if let top = state.waste.last {
            for i in 0..<7 where state.canPlace(top, onTableau: i) {
                add(CandidateMove(cardIDs: [top.id], source: .waste, target: .tableau(i)))
                break
            }
        }
        // 5. Draw or recycle.
        if !state.stock.isEmpty {
            add(CandidateMove(cardIDs: [], source: .stock, target: nil, message: L10n.hintDrawStock))
        } else if canRecycle {
            add(CandidateMove(cardIDs: [], source: .stock, target: nil, message: L10n.hintRecycle))
        }
        // 6. Every remaining legal tableau move, part-runs included. These
        // rarely get the player anywhere, which is why they come last — but
        // the dead-end banner counts them, so the hint has to know them too
        // rather than announcing a finished board while the banner stays away.
        for (i, pile) in state.tableaus.enumerated() {
            guard let firstFaceUp = pile.firstIndex(where: { $0.isFaceUp }) else { continue }
            for start in firstFaceUp..<pile.count {
                let run = Array(pile[start...])
                guard let head = run.first else { continue }
                for j in 0..<7 where j != i && state.canPlace(head, onTableau: j) {
                    // Relocating a whole column into another empty one achieves
                    // nothing, exactly as `hasLegalMove` judges it.
                    guard !state.tableaus[j].isEmpty || start > 0 else { continue }
                    add(CandidateMove(cardIDs: run.map(\.id), source: .tableau(i), target: .tableau(j)))
                }
            }
        }
        return result
    }

    /// A king is available (waste top or a movable tableau run) to take an empty column.
    private static func kingIsWaiting(in state: GameState) -> Bool {
        if state.waste.last?.rank == .king { return true }
        for pile in state.tableaus {
            guard let firstFaceUp = pile.firstIndex(where: { $0.isFaceUp }) else { continue }
            if pile[firstFaceUp].rank == .king && firstFaceUp > 0 { return true }
        }
        return false
    }

    /// Every pile the given card may legally move to, the foundation first.
    ///
    /// Tap-to-move picks one destination and dragging picks any of them, which
    /// leaves a VoiceOver reader with only the first: they cannot drag. This is
    /// that same choice, as a list to be read out.
    ///
    /// At most one foundation is listed. A card fits at most one anyway, and
    /// which of the four it is carries no meaning to a reader hearing them.
    /// Unlike the hint list this makes no judgement about whether a move is
    /// worth making — a drag does not either, and second-guessing a reader's
    /// intent is exactly the difference this is here to remove.
    static func destinations(forCardID cardID: String, in state: GameState) -> [PileID] {
        guard let (run, loc) = state.movableRun(startingAt: cardID) else { return [] }
        var result: [PileID] = []
        if let f = (0..<4).first(where: { state.canDrop(run: run, from: loc.pile, on: .foundation($0)) }) {
            result.append(.foundation(f))
        }
        for t in 0..<7 where state.canDrop(run: run, from: loc.pile, on: .tableau(t)) {
            result.append(.tableau(t))
        }
        return result
    }

    /// Where a tapped run should go when no foundation will take it; nil when
    /// no column accepts it, or when the move would achieve nothing.
    static func bestTableauTarget(for run: [Card], from loc: CardLocation, in state: GameState) -> PileID? {
        guard let first = run.first else { return nil }
        var nonEmpty: [Int] = []
        var empty: [Int] = []
        for i in 0..<7 {
            if case .tableau(let src) = loc.pile, src == i { continue }
            guard state.canPlace(first, onTableau: i) else { continue }
            if state.tableaus[i].isEmpty { empty.append(i) } else { nonEmpty.append(i) }
        }
        if let i = nonEmpty.first { return .tableau(i) }
        if let i = empty.first {
            // Don't shuttle a lone king between empty columns.
            if loc.pile.isTableau, first.rank == .king, loc.index == 0 { return nil }
            return .tableau(i)
        }
        return nil
    }
}
