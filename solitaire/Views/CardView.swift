//
//  CardView.swift
//  solitaire
//
//  Card rendering: authentic pip layouts, court cards, corner indices,
//  four procedurally drawn back designs, and a 3-D flip animation.
//

import SwiftUI

// MARK: - Card container with flip animation

struct CardView: View {
    var card: Card
    var backStyle: CardBackStyle
    var size: CGSize

    var body: some View {
        FlippableCard(
            progress: card.isFaceUp ? 1 : 0,
            front: CardFaceView(card: card, size: size),
            back: CardBackView(style: backStyle, size: size)
        )
        .frame(width: size.width, height: size.height)
    }
}

/// Animates between back (progress 0) and front (progress 1) with a Y-axis flip.
struct FlippableCard<Front: View, Back: View>: View, Animatable {
    var progress: Double
    var front: Front
    var back: Back

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    init(progress: Double, front: Front, back: Back) {
        self.progress = progress
        self.front = front
        self.back = back
    }

    var body: some View {
        ZStack {
            back
                .opacity(progress < 0.5 ? 1 : 0)
            front
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(progress < 0.5 ? 0 : 1)
        }
        .rotation3DEffect(.degrees(progress * 180), axis: (x: 0, y: 1, z: 0), perspective: 0.25)
    }
}

// MARK: - Face

struct CardFaceView: View {
    var card: Card
    var size: CGSize

    private var suitColor: Color {
        card.isRed
            ? Color(red: 0.78, green: 0.12, blue: 0.16)
            : Color(red: 0.10, green: 0.10, blue: 0.14)
    }

    private var w: CGFloat { size.width }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.99, green: 0.99, blue: 0.975), Color(red: 0.93, green: 0.93, blue: 0.91)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                .strokeBorder(Color.black.opacity(0.22), lineWidth: 0.8)

            cornerIndex
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, w * 0.055)
                .padding(.top, w * 0.03)
            cornerIndex
                .rotationEffect(.degrees(180))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, w * 0.055)
                .padding(.bottom, w * 0.03)

            centerContent
                .padding(.horizontal, w * 0.20)
                .padding(.vertical, w * 0.24)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel("\(L10n.rankName(card.rank)) — \(L10n.suitName(card.suit))")
    }

    private var cornerIndex: some View {
        VStack(spacing: -w * 0.02) {
            Text(card.rank.label)
                .font(.system(size: w * 0.21, weight: .bold, design: .rounded))
            Text(card.suit.symbol)
                .font(.system(size: w * 0.17))
        }
        .foregroundStyle(suitColor)
        .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var centerContent: some View {
        switch card.rank {
        case .ace:
            Text(card.suit.symbol)
                .font(.system(size: w * 0.52))
                .foregroundStyle(suitColor)
        case .jack, .queen, .king:
            CourtCardView(card: card, size: size, suitColor: suitColor)
        default:
            PipGridView(card: card, suitColor: suitColor, pipSize: w * 0.215)
        }
    }
}

// MARK: - Pips (2–10)

private struct PipGridView: View {
    var card: Card
    var suitColor: Color
    var pipSize: CGFloat

    /// Normalised pip positions (x, y in -1...1; y grows downward).
    /// Matches traditional playing-card layouts.
    private static let layouts: [Int: [(CGFloat, CGFloat)]] = [
        2: [(0, -1), (0, 1)],
        3: [(0, -1), (0, 0), (0, 1)],
        4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
        5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
        6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
        7: [(-1, -1), (1, -1), (0, -0.5), (-1, 0), (1, 0), (-1, 1), (1, 1)],
        8: [(-1, -1), (1, -1), (0, -0.5), (-1, 0), (1, 0), (0, 0.5), (-1, 1), (1, 1)],
        9: [(-1, -1), (1, -1), (-1, -0.333), (1, -0.333), (0, 0), (-1, 0.333), (1, 0.333), (-1, 1), (1, 1)],
        10: [(-1, -1), (1, -1), (0, -0.667), (-1, -0.333), (1, -0.333), (-1, 0.333), (1, 0.333), (0, 0.667), (-1, 1), (1, 1)],
    ]

    var body: some View {
        GeometryReader { geo in
            let positions = Self.layouts[card.rank.rawValue] ?? []
            ForEach(Array(positions.enumerated()), id: \.offset) { _, pos in
                Text(card.suit.symbol)
                    .font(.system(size: pipSize))
                    .foregroundStyle(suitColor)
                    .rotationEffect(pos.1 > 0 ? .degrees(180) : .zero)
                    .position(
                        x: geo.size.width / 2 + pos.0 * geo.size.width * 0.36,
                        y: geo.size.height / 2 + pos.1 * geo.size.height * 0.41
                    )
            }
        }
    }
}

// MARK: - Court cards (J, Q, K)

private struct CourtCardView: View {
    var card: Card
    var size: CGSize
    var suitColor: Color

    private var w: CGFloat { size.width }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                .fill(suitColor.opacity(0.07))
            RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                .strokeBorder(suitColor.opacity(0.55), lineWidth: 1)
            RoundedRectangle(cornerRadius: w * 0.035, style: .continuous)
                .strokeBorder(suitColor.opacity(0.28), lineWidth: 0.7)
                .padding(w * 0.035)

            VStack(spacing: 0) {
                Text(card.suit.symbol)
                    .font(.system(size: w * 0.14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, w * 0.075)
                Spacer(minLength: 0)
                Text(card.suit.symbol)
                    .font(.system(size: w * 0.14))
                    .rotationEffect(.degrees(180))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, w * 0.075)
            }
            .padding(.vertical, w * 0.075)
            .foregroundStyle(suitColor)

            Text(card.rank.label)
                .font(.system(size: w * 0.42, weight: .semibold, design: .serif))
                .foregroundStyle(suitColor)
        }
    }
}

// MARK: - Backs

struct CardBackView: View {
    var style: CardBackStyle
    var size: CGSize

    private var w: CGFloat { size.width }

    private var colors: (base: Color, deep: Color, pattern: Color) {
        switch style {
        case .crimson:
            return (Color(red: 0.62, green: 0.13, blue: 0.16), Color(red: 0.38, green: 0.05, blue: 0.08), .white)
        case .royal:
            return (Color(red: 0.15, green: 0.28, blue: 0.62), Color(red: 0.06, green: 0.12, blue: 0.36), .white)
        case .emerald:
            return (Color(red: 0.09, green: 0.46, blue: 0.32), Color(red: 0.02, green: 0.25, blue: 0.16), .white)
        case .night:
            return (Color(red: 0.16, green: 0.16, blue: 0.28), Color(red: 0.05, green: 0.05, blue: 0.12), Color(red: 1.0, green: 0.88, blue: 0.55))
        }
    }

    var body: some View {
        let c = colors
        ZStack {
            RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                .fill(LinearGradient(colors: [c.base, c.deep], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: w * 0.11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: max(1, w * 0.02))

            pattern(c.pattern)
                .clipShape(RoundedRectangle(cornerRadius: w * 0.07, style: .continuous).inset(by: 0))
                .padding(w * 0.09)

            RoundedRectangle(cornerRadius: w * 0.07, style: .continuous)
                .strokeBorder(c.pattern.opacity(0.7), lineWidth: 0.8)
                .padding(w * 0.09)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement()
        .accessibilityLabel(L10n.faceDownCard)
    }

    @ViewBuilder
    private func pattern(_ tint: Color) -> some View {
        switch style {
        case .crimson:
            // Diagonal lattice.
            Canvas { context, canvasSize in
                let step = canvasSize.width / 5
                context.opacity = 0.35
                var offset: CGFloat = -canvasSize.height
                while offset < canvasSize.width + canvasSize.height {
                    var path = Path()
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + canvasSize.height, y: canvasSize.height))
                    context.stroke(path, with: .color(tint), lineWidth: 0.8)
                    var path2 = Path()
                    path2.move(to: CGPoint(x: offset + canvasSize.height, y: 0))
                    path2.addLine(to: CGPoint(x: offset, y: canvasSize.height))
                    context.stroke(path2, with: .color(tint), lineWidth: 0.8)
                    offset += step
                }
            }
        case .royal:
            // Concentric rounded frames.
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                        .strokeBorder(tint.opacity(0.5 - Double(i) * 0.12), lineWidth: 0.8)
                        .padding(CGFloat(i) * w * 0.075 + w * 0.03)
                }
                Text("♛")
                    .font(.system(size: w * 0.30))
                    .foregroundStyle(tint.opacity(0.65))
            }
        case .emerald:
            // Fine diagonal stripes.
            Canvas { context, canvasSize in
                context.opacity = 0.28
                var offset: CGFloat = -canvasSize.height
                while offset < canvasSize.width + canvasSize.height {
                    var path = Path()
                    path.move(to: CGPoint(x: offset, y: canvasSize.height))
                    path.addLine(to: CGPoint(x: offset + canvasSize.height, y: 0))
                    context.stroke(path, with: .color(tint), lineWidth: 2.2)
                    offset += canvasSize.width / 7
                }
            }
        case .night:
            // Starfield with a moon.
            Canvas { context, canvasSize in
                let stars: [(CGFloat, CGFloat, CGFloat)] = [
                    (0.18, 0.15, 1.1), (0.72, 0.10, 0.8), (0.45, 0.28, 1.3), (0.85, 0.35, 0.9),
                    (0.25, 0.45, 0.8), (0.60, 0.52, 1.2), (0.15, 0.68, 1.0), (0.80, 0.72, 0.8),
                    (0.40, 0.82, 1.2), (0.65, 0.90, 0.9), (0.30, 0.06, 0.7), (0.90, 0.55, 0.7),
                ]
                for star in stars {
                    let rect = CGRect(
                        x: star.0 * canvasSize.width, y: star.1 * canvasSize.height,
                        width: star.2 * 2, height: star.2 * 2
                    )
                    context.opacity = 0.8
                    context.fill(Path(ellipseIn: rect), with: .color(tint))
                }
                let moon = CGRect(
                    x: canvasSize.width * 0.58, y: canvasSize.height * 0.16,
                    width: canvasSize.width * 0.22, height: canvasSize.width * 0.22
                )
                context.opacity = 0.9
                context.fill(Path(ellipseIn: moon), with: .color(tint))
                context.blendMode = .destinationOut
                context.fill(Path(ellipseIn: moon.offsetBy(dx: -moon.width * 0.28, dy: -moon.width * 0.12)), with: .color(.black))
            }
        }
    }
}

// MARK: - Previews

#Preview("Faces") {
    let size = CGSize(width: 80, height: 116)
    return VStack(spacing: 8) {
        HStack(spacing: 8) {
            CardFaceView(card: Card(suit: .spades, rank: .ace, isFaceUp: true), size: size)
            CardFaceView(card: Card(suit: .hearts, rank: .seven, isFaceUp: true), size: size)
            CardFaceView(card: Card(suit: .diamonds, rank: .ten, isFaceUp: true), size: size)
            CardFaceView(card: Card(suit: .clubs, rank: .king, isFaceUp: true), size: size)
        }
        HStack(spacing: 8) {
            CardBackView(style: .crimson, size: size)
            CardBackView(style: .royal, size: size)
            CardBackView(style: .emerald, size: size)
            CardBackView(style: .night, size: size)
        }
    }
    .padding()
    .background(Color(red: 0.1, green: 0.4, blue: 0.25))
}
