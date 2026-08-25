//
//  WinView.swift
//  solitaire
//
//  Victory overlay: bouncing-card cascade, confetti, and the results panel.
//

import SwiftUI

struct WinView: View {
    var vm: GameViewModel
    var theme: TableTheme

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// An iPhone held sideways. The panel stacked vertically is roughly 520pt
    /// tall and no iPhone offers that in landscape, so it lays out side by side
    /// instead of having the trophy and the replay button clipped off.
    private var isShort: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            // Forty-four cards raining down the screen for seven seconds is
            // the most movement the app ever makes. Reduce Motion gets the
            // trophy, the score and the fade, and none of the weather.
            if !reduceMotion {
                CelebrationView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            // Centred while it fits, scrollable once it does not — the side by
            // side layout covers landscape, this covers the largest text sizes.
            GeometryReader { geo in
                ScrollView(.vertical) {
                    resultsPanel
                        .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var resultsPanel: some View {
        Group {
            if isShort {
                HStack(spacing: 26) {
                    headline
                    VStack(spacing: 12) {
                        scoreboard
                        actions
                    }
                }
            } else {
                VStack(spacing: 14) {
                    headline
                    scoreboard
                    actions
                }
            }
        }
        .padding(isShort ? 20 : 24)
        .frame(maxWidth: isShort ? 620 : 340)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        )
        .padding(isShort ? 16 : 30)
    }

    private var headline: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.85, blue: 0.35), Color(red: 0.95, green: 0.62, blue: 0.10)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: isShort ? 62 : 74, height: isShort ? 62 : 74)
                    .shadow(color: .orange.opacity(0.6), radius: 14)
                Image(systemName: "trophy.fill")
                    .font(.system(size: isShort ? 28 : 34))
                    .foregroundStyle(.white)
            }
            .padding(.top, 4)

            Text(L10n.youWon)
                .font(.system(isShort ? .title : .largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(.white)

            Text(L10n.congratulations)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
    }

    private var scoreboard: some View {
        VStack(spacing: 8) {
                switch vm.scoring.mode {
                case .none:
                    EmptyView()
                case .standard:
                    if vm.timeBonus > 0 {
                        resultRow(label: L10n.timeBonus, value: "+\(vm.timeBonus)", record: false)
                    }
                    resultRow(label: L10n.score, value: "\(vm.scoring.points)", record: vm.newRecords.score)
                case .vegas:
                    resultRow(
                        label: L10n.thisDeal,
                        value: ScoreKeeper.formatVegas(vm.scoring.points),
                        record: false
                    )
                    if vm.settings.vegasCumulative {
                        resultRow(
                            label: L10n.balance,
                            value: ScoreKeeper.formatVegas(vm.vegasBalance),
                            record: false
                        )
                    }
                }
                resultRow(label: L10n.time, value: vm.formattedTime, record: vm.newRecords.time)
                resultRow(label: L10n.moves, value: "\(vm.moves)", record: vm.newRecords.moves)
        }
        .padding(.vertical, 6)
    }

    private var actions: some View {
        VStack(spacing: 14) {
            Button {
                vm.newGame()
            } label: {
                Text(L10n.playAgain)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                vm.restartDeal()
            } label: {
                Text(L10n.replayDeal)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func resultRow(label: String, value: String, record: Bool) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.65))
            Spacer()
            if record {
                Text(L10n.newRecord)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(red: 1, green: 0.83, blue: 0.35), in: Capsule())
            }
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .font(.subheadline)
    }
}

// MARK: - Celebration (bouncing cards + confetti)

struct CelebrationView: View {
    @State private var sim = CelebrationSim()
    @State private var settled = false

    var body: some View {
        // Once every card and confetto has left the screen there is nothing to
        // redraw, so the per-frame timeline stops instead of running forever.
        TimelineView(.animation(paused: settled)) { timeline in
            Canvas { context, size in
                sim.advance(to: timeline.date.timeIntervalSinceReferenceDate, in: size)

                for piece in sim.confetti {
                    var ctx = context
                    ctx.translateBy(x: piece.x, y: piece.y)
                    ctx.rotate(by: .radians(piece.angle))
                    ctx.opacity = piece.opacity
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 3.2, width: piece.size, height: piece.size / 1.6)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(piece.color))
                }

                let cardSize = CGSize(width: min(56, size.width * 0.115), height: min(80, size.width * 0.165))
                for card in sim.cards {
                    var ctx = context
                    ctx.translateBy(x: card.x, y: card.y)
                    ctx.rotate(by: .radians(card.angle))
                    let rect = CGRect(
                        x: -cardSize.width / 2, y: -cardSize.height / 2,
                        width: cardSize.width, height: cardSize.height
                    )
                    let path = Path(roundedRect: rect, cornerRadius: cardSize.width * 0.11)
                    ctx.fill(path, with: .color(.white))
                    ctx.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 0.8)
                    ctx.draw(
                        Text(card.suit.symbol)
                            .font(.system(size: cardSize.width * 0.5))
                            .foregroundStyle(card.suit.isRed ? Color(red: 0.78, green: 0.12, blue: 0.16) : Color(red: 0.1, green: 0.1, blue: 0.14)),
                        at: CGPoint(x: 0, y: cardSize.height * 0.08)
                    )
                    ctx.draw(
                        Text(card.rank.label)
                            .font(.system(size: cardSize.width * 0.3, weight: .bold, design: .rounded))
                            .foregroundStyle(card.suit.isRed ? Color(red: 0.78, green: 0.12, blue: 0.16) : Color(red: 0.1, green: 0.1, blue: 0.14)),
                        at: CGPoint(x: -cardSize.width * 0.26, y: -cardSize.height * 0.32)
                    )
                }
            }
        }
        .task {
            // The show spawns cards for ~7 s and everything has fallen away a
            // few seconds later.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if sim.isFinished { settled = true; return }
            }
        }
    }
}

/// Simple physics playground driven by TimelineView. A reference type so the
/// per-frame mutation doesn't invalidate the view hierarchy.
final class CelebrationSim {
    struct FlyingCard {
        var suit: Suit
        var rank: Rank
        var x: CGFloat, y: CGFloat
        var vx: CGFloat, vy: CGFloat
        var angle: CGFloat
        var spin: CGFloat
        var bounces = 0
    }

    struct Confetto {
        var x: CGFloat, y: CGFloat
        var vx: CGFloat, vy: CGFloat
        var angle: CGFloat
        var spin: CGFloat
        var size: CGFloat
        var color: Color
        var opacity: Double
        var born: TimeInterval
    }

    private(set) var cards: [FlyingCard] = []
    private(set) var confetti: [Confetto] = []

    /// Every piece has been spawned and has since left the screen.
    var isFinished: Bool { spawnedCards >= Self.totalCards && cards.isEmpty && confetti.isEmpty }

    private var lastTime: TimeInterval?
    private var startTime: TimeInterval?
    private var spawnedCards = 0
    private var deck = Card.orderedDeck.shuffled()

    private static let totalCards = 44

    private static let confettiColors: [Color] = [
        Color(red: 1.0, green: 0.80, blue: 0.25), Color(red: 0.95, green: 0.35, blue: 0.35),
        Color(red: 0.35, green: 0.75, blue: 1.0), Color(red: 0.45, green: 0.90, blue: 0.55),
        Color(red: 0.85, green: 0.55, blue: 1.0), .white,
    ]

    func advance(to time: TimeInterval, in size: CGSize) {
        if startTime == nil {
            startTime = time
            spawnConfettiBurst(at: time, in: size)
        }
        let dt = CGFloat(min(max(time - (lastTime ?? time), 0), 1.0 / 30.0))
        lastTime = time
        let elapsed = time - (startTime ?? time)

        // Launch a new card every 0.16 s for the first ~7 s.
        while spawnedCards < Self.totalCards,
              elapsed > Double(spawnedCards) * 0.16 {
            let template = deck[spawnedCards % deck.count]
            let fromLeft = spawnedCards.isMultiple(of: 2)
            cards.append(FlyingCard(
                suit: template.suit,
                rank: template.rank,
                x: fromLeft ? size.width * 0.18 : size.width * 0.82,
                y: -50,
                vx: (fromLeft ? 1 : -1) * CGFloat.random(in: 40...240),
                vy: CGFloat.random(in: 0...120),
                angle: CGFloat.random(in: -0.4...0.4),
                spin: CGFloat.random(in: -2.2...2.2)
            ))
            spawnedCards += 1
        }

        // Physics for cards.
        let floor = size.height - 12
        for i in cards.indices {
            cards[i].vy += 1250 * dt
            cards[i].x += cards[i].vx * dt
            cards[i].y += cards[i].vy * dt
            cards[i].angle += cards[i].spin * dt
            if cards[i].y > floor, cards[i].vy > 0 {
                cards[i].y = floor
                cards[i].vy = -cards[i].vy * 0.62
                cards[i].vx *= 0.98
                cards[i].spin *= 0.85
                cards[i].bounces += 1
            }
        }
        cards.removeAll { $0.x < -80 || $0.x > size.width + 80 || $0.bounces > 7 }

        // Physics for confetti.
        for i in confetti.indices {
            confetti[i].vy += 220 * dt
            confetti[i].vx *= 0.995
            confetti[i].x += confetti[i].vx * dt + sin((time - confetti[i].born) * 5 + Double(i)) * 0.6
            confetti[i].y += confetti[i].vy * dt
            confetti[i].angle += confetti[i].spin * dt
            let age = time - confetti[i].born
            confetti[i].opacity = age > 4.5 ? max(0, 1 - (age - 4.5) / 1.2) : 1
        }
        confetti.removeAll { $0.y > size.height + 40 || $0.opacity <= 0 }
    }

    private func spawnConfettiBurst(at time: TimeInterval, in size: CGSize) {
        for _ in 0..<110 {
            let fromX = CGFloat.random(in: 0...size.width)
            confetti.append(Confetto(
                x: fromX,
                y: CGFloat.random(in: -60 ... -10),
                vx: CGFloat.random(in: -60...60),
                vy: CGFloat.random(in: 60...260),
                angle: CGFloat.random(in: 0...(2 * .pi)),
                spin: CGFloat.random(in: -6...6),
                size: CGFloat.random(in: 6...12),
                color: Self.confettiColors.randomElement() ?? .white,
                opacity: 1,
                born: time
            ))
        }
    }
}
