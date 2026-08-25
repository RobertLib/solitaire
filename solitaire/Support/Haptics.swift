//
//  Haptics.swift
//  solitaire
//

import UIKit

/// Every entry point is static and answers `enabled` before it reaches
/// `shared`: switching haptics off should not warm up the Taptic Engine.
@MainActor
final class Haptics {
    private static let shared = Haptics()

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    private init() {
        light.prepare()
        medium.prepare()
        notification.prepare()
    }

    /// Fires one tap and asks for the next.
    ///
    /// A generator prepared once in `init` is only warm for the first tap of
    /// the session: the system lets it idle again after a few seconds, and
    /// every tap from then on pays the wake-up as a late thud a beat behind
    /// the card. Preparing on the way out keeps it warm for as long as the
    /// player keeps playing, and lets it idle once they stop — which is the
    /// behaviour the setting is for, rather than a Taptic Engine held awake
    /// for a game sitting untouched on the table.
    private func fire(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    private func fire(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
        notification.prepare()
    }

    /// Picking up / drawing a card.
    static func tap(enabled: Bool) {
        guard enabled else { return }
        shared.fire(shared.light, intensity: 0.7)
    }

    /// Dropping a card on a valid pile.
    static func drop(enabled: Bool) {
        guard enabled else { return }
        shared.fire(shared.medium, intensity: 0.85)
    }

    /// Card reached a foundation.
    static func success(enabled: Bool) {
        guard enabled else { return }
        shared.fire(shared.light, intensity: 1.0)
    }

    /// Illegal move.
    static func error(enabled: Bool) {
        guard enabled else { return }
        shared.fire(.error)
    }

    /// Game won.
    static func celebrate(enabled: Bool) {
        guard enabled else { return }
        shared.fire(.success)
    }
}
