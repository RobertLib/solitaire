//
//  BoardView.swift
//  solitaire
//
//  The interactive play area: renders all piles from a single source of
//  truth so every state change animates, and handles drag & drop plus
//  tap-to-auto-move.
//

import SwiftUI

struct BoardView: View {
    var vm: GameViewModel

    @State private var drag: DragInfo?
    @State private var settling: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverRunning

    private struct DragInfo {
        var run: [Card]
        var cardIDs: Set<String>
        var leadID: String
        var translation: CGSize = .zero
        var hoverTarget: PileID?
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = BoardLayout.metrics(for: geo.size, leftHanded: vm.settings.leftHandMode)
            let placements = BoardLayout.placements(for: vm.state, metrics: metrics, drawCount: vm.drawCount)
            let targets = BoardLayout.dropTargets(for: vm.state, metrics: metrics)

            ZStack {
                placeholderLayer(metrics: metrics)
                cardLayer(metrics: metrics, placements: placements, targets: targets)
                hintToast(metrics: metrics)
            }
            .coordinateSpace(name: "board")
        }
        // A drag is cleared by `onEnded`, which SwiftUI does not call when the
        // gesture is cancelled rather than finished — a Control Centre pull, a
        // swipe up to the app switcher, an incoming call. The run left behind
        // would sit frozen at its last offset, and worse, every later drag
        // checks `drag == nil` before it starts, so a single cancelled gesture
        // would stop the board taking any drag at all until the view was
        // rebuilt. Both of those arrive as the scene leaving `.active`.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { cancelDrag() }
        }
        // A deal handed over mid-drag — new game, restart, the wand, a win —
        // takes the dragged cards off the board with it.
        .onChange(of: vm.interactionLocked) { _, locked in
            if locked { cancelDrag() }
        }
    }

    /// Drops a drag that will never end on its own, putting the run back where
    /// the board says it is.
    private func cancelDrag() {
        guard drag != nil else { return }
        withAnimation(Motion.animation(.snappy(duration: 0.32))) { drag = nil }
    }

    // MARK: - Placeholders

    @ViewBuilder
    private func placeholderLayer(metrics m: BoardMetrics) -> some View {
        let cs = m.cardSize

        // Stock (tappable even when empty, for recycling).
        PilePlaceholder(size: cs) {
            if vm.state.stock.isEmpty {
                if vm.canRecycle {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: cs.width * 0.34, weight: .semibold))
                        .foregroundStyle(UIStyle.placeholderStroke)
                } else if !vm.state.waste.isEmpty {
                    // A recycle would help but the rules forbid it.
                    Image(systemName: "nosign")
                        .font(.system(size: cs.width * 0.34, weight: .semibold))
                        .foregroundStyle(UIStyle.placeholderStroke)
                }
            }
        }
        .position(m.stockCenter)
        .contentShape(RoundedRectangle(cornerRadius: cs.width * 0.11))
        .onTapGesture { vm.tapStock() }
        .accessibilityLabel(L10n.stockPile)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(vm.state.stock.isEmpty
                            ? L10n.emptyPile
                            : L10n.cardsRemaining(vm.state.stock.count))
        .accessibilityHint(vm.state.stock.isEmpty
                           ? (vm.canRecycle ? L10n.stockRecycleHint : "")
                           : L10n.stockDrawHint)
        .accessibilitySortPriority(Self.readingOrder(.stock))

        PilePlaceholder(size: cs) { EmptyView() }
            .position(m.wasteCenter)
            .accessibilityLabel(L10n.wastePile)
            .accessibilityValue(vm.state.waste.isEmpty ? L10n.emptyPile : "")
            .accessibilitySortPriority(Self.readingOrder(.waste))

        ForEach(0..<4, id: \.self) { f in
            let highlighted = isPileHighlighted(.foundation(f))
            PilePlaceholder(size: cs, highlighted: highlighted) {
                Text("A")
                    .font(.system(size: cs.width * 0.42, weight: .medium, design: .serif))
                    .foregroundStyle(UIStyle.placeholderStroke)
            }
            .position(m.foundationCenters[f])
            .accessibilityLabel(L10n.foundationPile(f + 1))
            .accessibilityValue(vm.state.foundations[f].isEmpty ? L10n.emptyPile : "")
            .accessibilitySortPriority(Self.readingOrder(.foundation(f)))
        }

        ForEach(0..<7, id: \.self) { t in
            let pile = vm.state.tableaus[t]
            let highlighted = pile.isEmpty && isPileHighlighted(.tableau(t))
            let faceDown = pile.filter { !$0.isFaceUp }.count
            PilePlaceholder(size: cs, highlighted: highlighted) { EmptyView() }
                .position(m.tableauTopCenters[t])
                .accessibilityLabel(L10n.tableauPile(t + 1))
                // Face-down cards are not offered individually — nothing can be
                // done with them — so the column reports how many it is hiding.
                .accessibilityValue(pile.isEmpty
                                    ? L10n.emptyPile
                                    : (faceDown > 0 ? L10n.faceDownCount(faceDown) : ""))
                .accessibilitySortPriority(Self.readingOrder(.tableau(t)))
        }
    }

    /// VoiceOver reads the board the way a player scans it: stock, waste, the
    /// four foundations, then each column from its bottom card up to the top.
    /// Higher priority is read first, and a pile's placeholder introduces it.
    private static func readingOrder(_ pile: PileID, index: Int = -1) -> Double {
        let base: Int
        switch pile {
        case .stock: base = 0
        case .waste: base = 100
        case .foundation(let i): base = 200 + i * 100
        case .tableau(let i): base = 600 + i * 100
        }
        return Double(2000 - base - min(index + 1, 99))
    }

    /// A pile placeholder lights up when it is a hint target or a valid
    /// hovered drop target.
    private func isPileHighlighted(_ pile: PileID) -> Bool {
        if drag?.hoverTarget == pile { return true }
        if vm.hint?.target == pile {
            // Only highlight the placeholder itself when the pile is empty;
            // otherwise its top card gets the glow.
            return vm.state[pile].isEmpty
        }
        return false
    }

    // MARK: - Cards

    @ViewBuilder
    private func cardLayer(metrics m: BoardMetrics, placements: [String: CardPlacement], targets: [(pile: PileID, frame: CGRect)]) -> some View {
        let cards = vm.state.allCards.sorted { $0.id < $1.id }
        let hintTopID = hintTargetTopCardID
        let hoverTopID = hoverTargetTopCardID
        let locations = cardLocations

        ForEach(cards) { card in
            if let placement = placements[card.id] {
                let isDragged = drag?.cardIDs.contains(card.id) ?? false
                let elevated = isDragged || settling.contains(card.id) || vm.recentlyMoved.contains(card.id)
                let isHinted = vm.hint?.cardIDs.contains(card.id) ?? false || card.id == hintTopID

                CardView(card: card, backStyle: vm.settings.cardBack, size: m.cardSize)
                    .overlay {
                        if isHinted {
                            GlowOverlay(size: m.cardSize, color: .yellow)
                        } else if card.id == hoverTopID {
                            GlowOverlay(size: m.cardSize, color: .white)
                        }
                    }
                    .shadow(
                        color: .black.opacity(isDragged ? 0.38 : 0.18),
                        radius: isDragged ? m.cardSize.width * 0.13 : 1.6,
                        y: isDragged ? m.cardSize.width * 0.10 : 1
                    )
                    .scaleEffect(isDragged ? 1.04 : 1)
                    .position(
                        x: placement.position.x + (isDragged ? drag!.translation.width : 0),
                        y: placement.position.y + (isDragged ? drag!.translation.height : 0)
                    )
                    .zIndex(placement.zIndex + (elevated ? 10_000 : 0))
                    .onTapGesture { vm.smartMove(cardID: card.id) }
                    .gesture(dragGesture(for: card, placements: placements, metrics: m, targets: targets))
                    .allowsHitTesting(!vm.interactionLocked)
                    // The face and the back each declare themselves accessible
                    // so they read correctly on their own elsewhere; on the
                    // board the card is one element that knows where it lies.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel(for: card, at: locations[card.id]))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(card.isFaceUp ? L10n.cardMoveHint : "")
                    // A buried face-down card cannot be played and its pile
                    // already reports the count, so it is only noise here.
                    .accessibilityHidden(!card.isFaceUp)
                    .accessibilitySortPriority(
                        locations[card.id].map { Self.readingOrder($0.pile, index: $0.index) } ?? 0
                    )
                    // Dragging is the only way to choose *which* pile a card
                    // goes to, and dragging is exactly what a reader cannot do.
                    // The rotor gets the same choice by name.
                    .accessibilityActions {
                        ForEach(accessibilityMoves(for: card), id: \.id) { move in
                            Button(move.name) { vm.attemptMove(cardID: card.id, to: move.target) }
                        }
                    }
            }
        }
    }

    /// Where every card currently sits, so each one can say so out loud.
    private var cardLocations: [String: CardLocation] {
        var result: [String: CardLocation] = [:]
        result.reserveCapacity(52)
        for pile in GameState.allPiles {
            for (i, card) in vm.state[pile].enumerated() {
                result[card.id] = CardLocation(pile: pile, index: i)
            }
        }
        return result
    }

    /// A name for each destination `MoveAdvisor.destinations` offers.
    ///
    /// Worked out only while VoiceOver is running. This is asked of all 52
    /// cards every time the board redraws, and each answer walks the piles
    /// looking for the card and then tries eleven destinations — cheap enough
    /// a few times a second for the reader who needs it, and pure waste for
    /// everyone else. The environment value re-runs `body` when the reader
    /// turns VoiceOver on, so the actions appear the moment they are wanted.
    private struct CardMove: Identifiable {
        var id: String
        var name: String
        var target: PileID
    }

    private func accessibilityMoves(for card: Card) -> [CardMove] {
        guard voiceOverRunning, !vm.interactionLocked, card.isFaceUp else { return [] }
        return MoveAdvisor.destinations(forCardID: card.id, in: vm.state).compactMap { target in
            switch target {
            case .foundation:
                return CardMove(id: "foundation", name: L10n.moveToFoundation, target: target)
            case .tableau(let t):
                return CardMove(id: "tableau\(t)", name: L10n.moveToColumn(t + 1), target: target)
            case .stock, .waste:
                // `destinations` never offers these; nothing is dropped on them.
                return nil
            }
        }
    }

    private func accessibilityLabel(for card: Card, at location: CardLocation?) -> String {
        let name = card.isFaceUp
            ? "\(L10n.rankName(card.rank)) — \(L10n.suitName(card.suit))"
            : L10n.faceDownCard
        switch location?.pile {
        case .stock: return L10n.cardInStock(name)
        case .waste: return L10n.cardInWaste(name)
        case .foundation(let i): return L10n.cardInFoundation(name, i + 1)
        case .tableau(let i): return L10n.cardInColumn(name, i + 1)
        case nil: return name
        }
    }

    /// Top card of the pile the current hint points at (nil for empty piles).
    private var hintTargetTopCardID: String? {
        guard let target = vm.hint?.target, target.isFoundation || target.isTableau else { return nil }
        return vm.state[target].last?.id
    }

    private var hoverTargetTopCardID: String? {
        guard let target = drag?.hoverTarget else { return nil }
        return vm.state[target].last?.id
    }

    // MARK: - Drag & drop

    private func dragGesture(for card: Card, placements: [String: CardPlacement], metrics m: BoardMetrics, targets: [(pile: PileID, frame: CGRect)]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("board"))
            .onChanged { value in
                if drag == nil {
                    guard !vm.interactionLocked,
                          let (run, loc) = vm.state.movableRun(startingAt: card.id),
                          loc.pile != .stock else { return }
                    drag = DragInfo(run: run, cardIDs: Set(run.map(\.id)), leadID: card.id)
                    Haptics.tap(enabled: vm.settings.hapticsEnabled)
                }
                guard var d = drag, d.leadID == card.id else { return }
                d.translation = value.translation
                d.hoverTarget = resolveTarget(for: d, placements: placements, metrics: m, targets: targets)
                drag = d
            }
            .onEnded { value in
                // Only the card being dragged ends the drag. A second finger
                // has a gesture of its own on whatever card it landed on, and
                // that gesture ends too — clearing `drag` here would drop the
                // run the first finger is still carrying, snapping it home
                // mid-move. Nothing to reset either way: a gesture that never
                // became the drag never wrote to it.
                guard var d = drag, d.leadID == card.id else { return }
                d.translation = value.translation
                let target = resolveTarget(for: d, placements: placements, metrics: m, targets: targets)

                // Keep the run on top while it animates home or to the target.
                settling.formUnion(d.cardIDs)
                let settled = d.cardIDs
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    settling.subtract(settled)
                }

                withAnimation(Motion.animation(.snappy(duration: 0.32))) {
                    drag = nil
                }
                if let target {
                    vm.attemptMove(cardID: d.leadID, to: target)
                }
            }
    }

    /// Finds the valid drop pile with the largest overlap with the lead card.
    private func resolveTarget(for d: DragInfo, placements: [String: CardPlacement], metrics m: BoardMetrics, targets: [(pile: PileID, frame: CGRect)]) -> PileID? {
        guard let base = placements[d.leadID] else { return nil }
        let center = CGPoint(
            x: base.position.x + d.translation.width,
            y: base.position.y + d.translation.height
        )
        let cardFrame = CGRect(
            x: center.x - m.cardSize.width / 2,
            y: center.y - m.cardSize.height / 2,
            width: m.cardSize.width,
            height: m.cardSize.height
        )
        let cardArea = cardFrame.width * cardFrame.height
        var best: (pile: PileID, overlap: CGFloat)?

        guard let source = vm.state.location(of: d.leadID)?.pile else { return nil }

        for target in targets {
            guard vm.state.canDrop(run: d.run, from: source, on: target.pile) else { continue }
            let overlap = cardFrame.intersection(target.frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > cardArea * 0.18, area > (best?.overlap ?? 0) {
                best = (target.pile, area)
            }
        }
        return best?.pile
    }

    // MARK: - Hint toast

    @ViewBuilder
    private func hintToast(metrics m: BoardMetrics) -> some View {
        if let message = vm.hint?.message {
            let edge: Edge = toastGoesToTop(m) ? .top : .bottom
            // Reduce Motion: the toast fades in where it belongs rather than
            // sliding in from the edge of the board.
            let arrival: AnyTransition = reduceMotion
                ? .opacity
                : .opacity.combined(with: .move(edge: edge))
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.black.opacity(0.55), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .top ? .top : .bottom)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .zIndex(50_000)
                .transition(arrival)
                .allowsHitTesting(false)
        }
    }

    /// The toast normally rides along the bottom of the board, where it is out
    /// of the way — except in landscape, and whenever the wand button or the
    /// dead-end banner has already claimed that spot.
    private func toastGoesToTop(_ m: BoardMetrics) -> Bool {
        m.isLandscape || vm.canAutoFinish || vm.isStuck
    }
}

// MARK: - Supporting views

struct PilePlaceholder<Content: View>: View {
    var size: CGSize
    var highlighted: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.11, style: .continuous)
                .fill(UIStyle.placeholderFill)
            RoundedRectangle(cornerRadius: size.width * 0.11, style: .continuous)
                .strokeBorder(
                    highlighted ? Color.white.opacity(0.9) : UIStyle.placeholderStroke,
                    lineWidth: highlighted ? 2.5 : 1.2
                )
            content
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: highlighted ? .white.opacity(0.5) : .clear, radius: highlighted ? 6 : 0)
    }
}

/// Pulsing outline used for hints and hovered drop targets.
struct GlowOverlay: View {
    var size: CGSize
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                // Reduce Motion: the ring still marks the card, it just holds
                // still. Of everything on the board this is the animation that
                // never ends on its own, so leaving it running would be the
                // one thing always moving in a game asked to keep still.
                ring
            } else {
                ring
                    .phaseAnimator([0.45, 1.0]) { view, phase in
                        view.opacity(phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.55)
                    }
            }
        }
        .allowsHitTesting(false)
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: size.width * 0.11, style: .continuous)
            .strokeBorder(color, lineWidth: 2.5)
            .shadow(color: color.opacity(0.9), radius: 5)
    }
}
