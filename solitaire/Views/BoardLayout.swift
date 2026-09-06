//
//  BoardLayout.swift
//  solitaire
//
//  Computes card positions for the current board size. Portrait keeps the
//  classic top-row layout; landscape moves stock and foundations to the
//  sides so the tableau gets maximum height.
//

import SwiftUI

struct CardPlacement {
    var position: CGPoint
    var zIndex: Double
}

struct BoardMetrics {
    var cardSize: CGSize = CGSize(width: 50, height: 72)
    var stockCenter: CGPoint = .zero
    var wasteCenter: CGPoint = .zero
    var wasteFanStep: CGVector = .zero
    var foundationCenters: [CGPoint] = []
    var tableauTopCenters: [CGPoint] = []
    var fanDown: CGFloat = 8
    /// The face-down step a squeezed column falls back to — see `fanSteps`.
    var fanDownTight: CGFloat = 8
    var fanUp: CGFloat = 18
    var tableauMaxBottom: CGFloat = 0
    var isLandscape = false
}

enum BoardLayout {
    static let cardAspect: CGFloat = 1.44

    /// Cards stop growing past this width, so the board keeps playable
    /// proportions on iPad instead of stretching across the whole screen.
    ///
    /// Set against how tall a column gets rather than by eye: below about this
    /// the fan hits its cap long before the columns reach the bottom of an
    /// iPad, and the whole game ends up marooned in the top third of the
    /// screen. At this width a full column runs to within a few points of the
    /// bottom of an iPad board, portrait or landscape.
    ///
    /// A tall phone is the one shape where the cap still binds — seven columns
    /// have to fit across a narrow screen, so the cards come out small and the
    /// fan runs out of reasons to grow before it runs out of height. Columns
    /// there run about three quarters of the way down rather than to the foot
    /// of the board, and the deepest of them all the way. A freshly dealt one
    /// stops around two fifths and cannot do better: its cards are nearly all
    /// face down, and those stay stacked tight on purpose. The board fills as
    /// the deal opens up.
    ///
    /// Set just clear of the width seven columns work out to on the largest
    /// iPad, in either orientation, so that shape is sized by its own screen
    /// rather than by this number — the old 120 pt clipped a few points off it
    /// for no reason. A full column still lands inside the board there.
    static let maxCardWidth: CGFloat = 132

    /// Caps the card at a comfortable size and floors it above zero.
    ///
    /// The floor is not for any board a player will ever see: it is for the
    /// degenerate passes a `GeometryReader` can report — zero during a rotation,
    /// a sliver while an iPad window is being resized. A negative width from
    /// those propagates into `frame`, `cornerRadius` and `Font.system(size:)`,
    /// none of which accept one.
    private static func clampedCardWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return 1 }
        return max(1, min(width, maxCardWidth))
    }

    /// How far a column fans per card, sized from the height actually on hand.
    ///
    /// Seven columns have to fit across the width, so on a tall phone the cards
    /// come out narrow and there is height to spare; a fan fixed as a fraction
    /// of the card leaves the board hugging the top with the bottom half bare.
    /// Tuning the step to the room available spends that height instead.
    ///
    /// `available` is the fan span a column may occupy. It is shared out over a
    /// reference column of six face-down cards under a seven-card run, which
    /// covers 99% of the columns that come up in play; anything deeper still
    /// compresses in `placements`.
    /// The reference column the fan is budgeted for: six face-down cards under
    /// a seven-card run, which covers 99% of the columns that come up in play.
    private static let referenceFaceUpGaps: CGFloat = 6
    private static let referenceFaceDownGaps: CGFloat = 6

    /// Face-down cards carry nothing to read, so they stay tightly stacked.
    private static let tightRatio: CGFloat = 0.48

    /// Below this fraction of the card the rank in the corner starts to
    /// disappear under the card above it, so the fan never goes tighter of its
    /// own accord — and `landscapeMetrics` will not hand it a card so large
    /// that it would have to.
    private static let minUpRatio: CGFloat = 0.28

    private static func fanSteps(cardHeight: CGFloat, available: CGFloat) -> (up: CGFloat, down: CGFloat, tight: CGFloat) {
        let faceUpGaps = referenceFaceUpGaps
        let faceDownGaps = referenceFaceDownGaps
        let downRatio = tightRatio
        let raw = available / (faceUpGaps + faceDownGaps * downRatio)
        // Below ~0.28 the rank in the corner starts to disappear under the card
        // above; the ceiling is what keeps a column reading as one pile rather
        // than a row of loose cards.
        //
        // Only a tall phone ever reaches the ceiling — every other shape is
        // sized by the budget above — and it is set as high as a pile still
        // reads at, because that is the shape with height going spare. Every
        // column shows more of every card for it, the deepest included: it
        // compresses a little where before it did not need to, and still comes
        // out fanned wider than the old ceiling allowed.
        let up = min(max(raw, cardHeight * minUpRatio), cardHeight * 0.62)
        let tight = up * downRatio

        // Where that ceiling binds — only ever a tall phone — the reference
        // column stops short of the bottom with height going spare, and a
        // freshly dealt one stops very much shorter: six tight gaps and a
        // card, ending around two fifths of the way down an otherwise empty
        // table. The leftover goes to the face-down gaps, which are what a
        // fresh deal is almost entirely made of — but only up to a fraction of
        // the face-up step, never level with it. A rub is worth showing less of
        // than a card that can be read, and the gap between the two steps is
        // what makes turning a card over land as an opening rather than a
        // recolouring. Every other shape is sized by the budget above, leaves
        // nothing over, and is unchanged by this.
        let ceiling = up * 0.85
        let leftover = available - (faceUpGaps * up + faceDownGaps * tight)
        let down = leftover > 0 ? min(ceiling, tight + leftover / faceDownGaps) : tight
        return (up, down, tight)
    }

    static func metrics(for size: CGSize, leftHanded: Bool) -> BoardMetrics {
        // Everything below is arithmetic on the board size: one non-finite value
        // in and every position comes out non-finite, which SwiftUI will not
        // take. Treat a size that is not a real size as no size at all.
        let size = (size.width.isFinite && size.height.isFinite) ? size : .zero
        return size.width > size.height
            ? landscapeMetrics(for: size, leftHanded: leftHanded)
            : portraitMetrics(for: size, leftHanded: leftHanded)
    }

    // MARK: - Portrait

    private static func portraitMetrics(for size: CGSize, leftHanded: Bool) -> BoardMetrics {
        var m = BoardMetrics()
        let sideMargin = max(8, size.width * 0.022)
        let spacing = max(4, size.width * 0.014)
        let cardW = clampedCardWidth((size.width - 2 * sideMargin - 6 * spacing) / 7)
        let cardH = cardW * cardAspect
        m.cardSize = CGSize(width: cardW, height: cardH)

        // Centre the seven columns; on a wide screen the board sits in the
        // middle rather than being pinned to the left margin.
        let boardWidth = 7 * cardW + 6 * spacing
        let originX = (size.width - boardWidth) / 2

        func columnX(_ i: Int) -> CGFloat {
            let index = leftHanded ? 6 - i : i
            return originX + cardW / 2 + CGFloat(index) * (cardW + spacing)
        }

        let topRowGap = cardH * 0.24
        // Top row centre down to the tableau's first card centre.
        let tableauOffset = cardH / 2 + topRowGap + cardH / 2
        m.tableauMaxBottom = size.height - 6

        let topRowY = 12 + cardH / 2
        let fan = fanSteps(
            cardHeight: cardH,
            available: max(0, m.tableauMaxBottom - cardH / 2 - (topRowY + tableauOffset))
        )
        m.fanUp = fan.up
        m.fanDown = fan.down
        m.fanDownTight = fan.tight
        m.stockCenter = CGPoint(x: columnX(0), y: topRowY)
        m.wasteCenter = CGPoint(x: columnX(1), y: topRowY)
        m.wasteFanStep = CGVector(dx: (leftHanded ? -1 : 1) * cardW * 0.34, dy: 0)
        m.foundationCenters = (0..<4).map { CGPoint(x: columnX(3 + $0), y: topRowY) }

        let tableauTopY = topRowY + tableauOffset
        m.tableauTopCenters = (0..<7).map { CGPoint(x: columnX($0), y: tableauTopY) }
        return m
    }

    // MARK: - Landscape

    /// The largest card that fits with the foundations laid out `rows` deep and
    /// `columns` across: the block has to stack inside the height, and the
    /// seven tableau columns, the stock's one and the foundations' have to sit
    /// side by side across the width.
    private static func widthFittingFoundations(
        rows: Int, columns: Int,
        size: CGSize, vMargin: CGFloat, spacing: CGFloat, sideMargin: CGFloat
    ) -> CGFloat {
        let byHeight = (size.height - 2 * vMargin - CGFloat(rows - 1) * spacing) / CGFloat(rows) / cardAspect
        let lanes = CGFloat(7 + 1 + columns)
        let byWidth = (size.width - 2 * sideMargin - 2 * spacing * 4 - 6 * spacing) / lanes
        return min(byHeight, byWidth)
    }

    /// The tallest card whose reference column still fans at the face-up step
    /// `fanSteps` will not go tighter than, in the height on hand.
    ///
    /// A card that outgrows the height is a worse deal than a small one: the
    /// column compresses to stay on the board, and past a point the rank in the
    /// corner disappears under the card above it — a board of big cards nobody
    /// can read. `span` is the room from the top of the columns' margin to the
    /// bottom of the board.
    private static func cardHeightFittingFan(span: CGFloat) -> CGFloat {
        let gaps = (referenceFaceUpGaps + referenceFaceDownGaps * tightRatio) * minUpRatio
        // The column is its own height plus the gaps, and it starts half a card
        // below the margin and ends half a card above its last centre — which
        // adds up to one whole card either way.
        return span / (1 + gaps)
    }

    private static func landscapeMetrics(for size: CGSize, leftHanded: Bool) -> BoardMetrics {
        var m = BoardMetrics()
        m.isLandscape = true

        let vMargin: CGFloat = 10
        let spacing = max(5, size.height * 0.016)
        let sideMargin = max(10, size.width * 0.015)
        m.tableauMaxBottom = size.height - 6

        // Two ways to park the four foundations beside the tableau: stacked in
        // one column, or in a 2×2 block. The column is narrow and tall, the
        // block wide and short, and which of them lets the card come out bigger
        // is a question about the shape of the board rather than about the
        // device — so both are measured and the better one wins.
        //
        // A landscape iPad is wide enough that the seven columns are what binds
        // and the tall arrangement takes it, unchanged. A landscape phone is
        // short, and there the column of four was the only thing holding the
        // card down — to a little over half the width that was going spare.
        let stackedWidth = widthFittingFoundations(
            rows: 4, columns: 1, size: size, vMargin: vMargin, spacing: spacing, sideMargin: sideMargin
        )
        let blockWidth = widthFittingFoundations(
            rows: 2, columns: 2, size: size, vMargin: vMargin, spacing: spacing, sideMargin: sideMargin
        )
        let useBlock = blockWidth > stackedWidth
        let rows = useBlock ? 2 : 4
        let columns = useBlock ? 2 : 1

        // ...and no bigger than the columns can fan, whichever arrangement won.
        // Only landscape ever needs this: a portrait card is seven across a
        // screen and comes out well inside it.
        let fanWidth = cardHeightFittingFan(span: m.tableauMaxBottom - vMargin) / cardAspect
        let cardW = clampedCardWidth(min(max(stackedWidth, blockWidth), fanWidth))
        let cardH = cardW * cardAspect
        m.cardSize = CGSize(width: cardW, height: cardH)

        // Stock and foundations stay anchored to the screen edges; only the
        // card size is capped, so the tableau keeps the full width to spread in.
        let leftX = sideMargin + cardW / 2
        let rightX = size.width - sideMargin - cardW / 2
        let stockSideX = leftHanded ? rightX : leftX
        // The foundations take the far side from the stock. `inward` points
        // from there towards the tableau, so one expression places the block's
        // second column and the tableau's edge for either handedness.
        let foundationOuterX = leftHanded ? leftX : rightX
        let inward: CGFloat = leftHanded ? 1 : -1
        let foundationInnerX = foundationOuterX + inward * CGFloat(columns - 1) * (cardW + spacing)

        m.stockCenter = CGPoint(x: stockSideX, y: vMargin + cardH / 2)
        m.wasteCenter = CGPoint(x: stockSideX, y: vMargin + cardH / 2 + cardH + spacing * 1.5)
        m.wasteFanStep = CGVector(dx: 0, dy: cardH * 0.30)

        // The foundations fill the height only while the card is sized by their
        // own block; once the width or a cap takes over they fall short, so the
        // block centres instead of hanging off the top with the tableau running
        // the full height beside it.
        let blockHeight = CGFloat(rows) * cardH + CGFloat(rows - 1) * spacing
        let blockTop = max(vMargin, (size.height - blockHeight) / 2) + cardH / 2
        // Reading order across the block, so foundation 1 is the leftmost on
        // screen whichever side of the board the block has been put on. With
        // one column both entries are the same x and this reduces to the stack.
        let columnXs = leftHanded
            ? [foundationOuterX, foundationInnerX]
            : [foundationInnerX, foundationOuterX]
        m.foundationCenters = (0..<4).map { i in
            CGPoint(x: columnXs[i % columns], y: blockTop + CGFloat(i / columns) * (cardH + spacing))
        }

        // Tableau centred between the two side blocks, three spacings clear of
        // each. `inward` points away from the stock, so its edge is the same
        // expression with the sign turned round.
        let foundationEdge = foundationInnerX + inward * (cardW / 2 + spacing * 3)
        let stockEdge = stockSideX - inward * (cardW / 2 + spacing * 3)
        let innerLeft = min(stockEdge, foundationEdge)
        let innerRight = max(stockEdge, foundationEdge)
        let tableauSpan = innerRight - innerLeft
        let tableauSpacing = (tableauSpan - 7 * cardW) / 6
        let tableauTopY = vMargin + cardH / 2
        m.tableauTopCenters = (0..<7).map {
            CGPoint(x: innerLeft + cardW / 2 + CGFloat($0) * (cardW + tableauSpacing), y: tableauTopY)
        }
        let fan = fanSteps(cardHeight: cardH, available: max(0, m.tableauMaxBottom - cardH / 2 - tableauTopY))
        m.fanUp = fan.up
        m.fanDown = fan.down
        m.fanDownTight = fan.tight
        return m
    }

    // MARK: - Placements

    /// The steps a particular column actually fans by, after being squeezed to
    /// stay on the board.
    ///
    /// `fanSteps` budgets for a column of six face-down cards under a
    /// seven-card run, and hands whatever height is left over to the face-down
    /// gaps so a freshly dealt column fills its share of the table. A deeper
    /// one — the whole deck can end up in a single column — has to give that
    /// back, so the face-down gaps tighten first, all the way to the step they
    /// would have had without the leftover: they carry nothing to read, and
    /// spending the squeeze on them leaves the face-up run at full spread. Only
    /// once they are back to tight does the whole column scale down together,
    /// exactly as it did before there was a leftover to hand out.
    ///
    /// Shared by the card placements and the drop targets so a column's hit
    /// area always ends exactly where the column does.
    private static func fanSteps(for pile: [Card], metrics m: BoardMetrics, topY: CGFloat) -> (up: CGFloat, down: CGFloat) {
        var upGaps: CGFloat = 0, downGaps: CGFloat = 0
        for card in pile.dropLast() {
            if card.isFaceUp { upGaps += 1 } else { downGaps += 1 }
        }
        let allowed = max(0, m.tableauMaxBottom - m.cardSize.height / 2 - topY)
        guard upGaps * m.fanUp + downGaps * m.fanDown > allowed else { return (m.fanUp, m.fanDown) }

        let tightened = upGaps * m.fanUp + downGaps * m.fanDownTight
        if downGaps > 0, tightened <= allowed {
            return (m.fanUp, (allowed - upGaps * m.fanUp) / downGaps)
        }
        guard tightened > 0 else { return (m.fanUp, m.fanDownTight) }
        let scale = min(1, max(0, allowed / tightened))
        return (m.fanUp * scale, m.fanDownTight * scale)
    }

    /// Positions and z-order for every card in the given state.
    static func placements(for state: GameState, metrics m: BoardMetrics, drawCount: Int) -> [String: CardPlacement] {
        var result: [String: CardPlacement] = [:]
        result.reserveCapacity(52)

        // Stock: aligned stack with a subtle depth offset.
        for (i, card) in state.stock.enumerated() {
            let depth = CGFloat(min(i, 14)) * 0.3
            result[card.id] = CardPlacement(
                position: CGPoint(x: m.stockCenter.x - depth * 0.4, y: m.stockCenter.y - depth),
                zIndex: Double(i)
            )
        }

        // Waste: the most recent (up to 3 in draw-3) cards fan out.
        let wasteCount = state.waste.count
        let fanVisible = drawCount == 3 ? 3 : 1
        for (i, card) in state.waste.enumerated() {
            let fanIndex = i - max(0, wasteCount - fanVisible)
            let clamped = CGFloat(max(0, min(fanIndex, fanVisible - 1)))
            result[card.id] = CardPlacement(
                position: CGPoint(
                    x: m.wasteCenter.x + m.wasteFanStep.dx * clamped,
                    y: m.wasteCenter.y + m.wasteFanStep.dy * clamped
                ),
                zIndex: 100 + Double(i)
            )
        }

        // Foundations.
        for f in 0..<4 {
            for (i, card) in state.foundations[f].enumerated() {
                result[card.id] = CardPlacement(
                    position: m.foundationCenters[f],
                    zIndex: 200 + Double(f) * 20 + Double(i)
                )
            }
        }

        // Tableau columns with per-pile fan compression.
        for c in 0..<7 {
            let pile = state.tableaus[c]
            guard !pile.isEmpty else { continue }
            let top = m.tableauTopCenters[c]
            let fan = fanSteps(for: pile, metrics: m, topY: top.y)

            var y = top.y
            for (i, card) in pile.enumerated() {
                result[card.id] = CardPlacement(
                    position: CGPoint(x: top.x, y: y),
                    zIndex: 300 + Double(c) * 40 + Double(i)
                )
                y += card.isFaceUp ? fan.up : fan.down
            }
        }

        return result
    }

    /// Frames used for drag-and-drop hit testing.
    static func dropTargets(for state: GameState, metrics m: BoardMetrics) -> [(pile: PileID, frame: CGRect)] {
        var targets: [(PileID, CGRect)] = []
        let cs = m.cardSize

        for f in 0..<4 {
            let c = m.foundationCenters[f]
            targets.append((.foundation(f), CGRect(
                x: c.x - cs.width * 0.75, y: c.y - cs.height * 0.65,
                width: cs.width * 1.5, height: cs.height * 1.3
            )))
        }
        for t in 0..<7 {
            let pile = state.tableaus[t]
            let top = m.tableauTopCenters[t]
            var bottomY = top.y
            if !pile.isEmpty {
                // Same compression the cards themselves get, so the hit area
                // ends where the column ends.
                let fan = fanSteps(for: pile, metrics: m, topY: top.y)
                for card in pile.dropLast() { bottomY += card.isFaceUp ? fan.up : fan.down }
            }
            let rect = CGRect(
                x: top.x - cs.width * 0.7,
                y: top.y - cs.height * 0.6,
                width: cs.width * 1.4,
                height: (bottomY - top.y) + cs.height * 1.6
            )
            targets.append((.tableau(t), rect))
        }
        return targets
    }
}
