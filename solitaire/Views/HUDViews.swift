//
//  HUDViews.swift
//  solitaire
//
//  Top status bar, bottom control bar, and the auto-finish button.
//

import SwiftUI

/// How wide the status bar and the control bar are allowed to grow.
///
/// Both are capped so they stay a band across the middle of the screen rather
/// than three stats spread thinly over the width of an iPad. The cap is roomier
/// where there is room — on an iPad the phone-sized 420 pt left the HUD looking
/// marooned in the middle of a very large table.
private enum BarMetrics {
    static func maxWidth(_ sizeClass: UserInterfaceSizeClass?) -> CGFloat {
        sizeClass == .regular ? 620 : 420
    }
}

struct TopHUD: View {
    var vm: GameViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRoomy: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: isRoomy ? 12 : 8) {
            StatBlock(label: vm.scoreLabel, value: vm.displayScore, roomy: isRoomy)
            StatBlock(label: L10n.time, value: vm.formattedTime, roomy: isRoomy)
            StatBlock(label: L10n.moves, value: "\(vm.moves)", roomy: isRoomy)
        }
        .frame(maxWidth: BarMetrics.maxWidth(horizontalSizeClass))
        .padding(.horizontal, 12)
        .padding(.vertical, isRoomy ? 10 : 6)
        // Text scales with the reader's setting, but not far enough to crowd
        // the board out of the screen.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct StatBlock: View {
    var label: String
    var value: String
    var roomy: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: roomy ? 2 : 1) {
            Text(label.uppercased())
                .font(.system(roomy ? .caption : .caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(UIStyle.hudSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(roomy ? .title3 : .headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(UIStyle.hudText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // The rolling digits are small, but they are still movement,
                // and a score that ticks over on every move is the one that
                // never stops.
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, roomy ? 8 : 5)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct BottomBar: View {
    var vm: GameViewModel
    var onMenu: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRoomy: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 0) {
            BarButton(icon: "line.3.horizontal", label: L10n.menu, roomy: isRoomy, action: onMenu)
            BarButton(
                icon: "arrow.uturn.backward",
                label: L10n.undo,
                disabled: !vm.canUndo,
                roomy: isRoomy,
                action: { vm.undo() }
            )
            BarButton(
                icon: "lightbulb",
                label: L10n.hint,
                disabled: vm.interactionLocked,
                roomy: isRoomy,
                action: { vm.requestHint() }
            )
        }
        .frame(maxWidth: BarMetrics.maxWidth(horizontalSizeClass))
        .padding(.horizontal, 8)
        .padding(.vertical, isRoomy ? 6 : 2)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct BarButton: View {
    var icon: String
    var label: String
    var disabled: Bool = false
    var roomy: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(roomy ? .title2 : .title3, weight: .semibold))
                Text(label)
                    .font(.system(roomy ? .caption : .caption2, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(disabled ? UIStyle.hudSecondary.opacity(0.5) : UIStyle.hudText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, roomy ? 9 : 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

struct AutoFinishButton: View {
    var theme: TableTheme
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(.body, weight: .semibold))
                Text(L10n.autoFinish)
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [theme.accent, theme.accent.opacity(0.75)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .shadow(color: theme.accent.opacity(0.55), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Shown when the deal has run out of legal moves. Informational only — the
/// board stays fully interactive underneath.
struct NoMovesBanner: View {
    var theme: TableTheme
    var canUndo: Bool
    var onUndo: () -> Void
    var onNewGame: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 3) {
                Text(L10n.noMovesLeft)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(canUndo ? L10n.noMovesLeftDetail : L10n.noMovesLeftDetailNoUndo)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                if canUndo {
                    Button(action: onUndo) {
                        bannerLabel(L10n.undo, icon: "arrow.uturn.backward")
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onNewGame) {
                    bannerLabel(L10n.newGame, icon: "plus.rectangle.on.rectangle")
                        .foregroundStyle(.black.opacity(0.85))
                        .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func bannerLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}
