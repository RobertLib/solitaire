//
//  Motion.swift
//  solitaire
//
//  One answer to "may this move?", shared by the view model and the views.
//

import SwiftUI

/// Whether the reader has asked the system for less movement.
///
/// The board's motion is driven from two places — `GameViewModel`, which is not
/// a view and so cannot read the environment, and the views themselves — so the
/// question is answered here rather than twice over. Views that have to *lay
/// out differently* when the setting changes still read
/// `\.accessibilityReduceMotion`, because only the environment re-runs `body`
/// when the reader changes their mind mid-game; this is for the moment an
/// animation is about to start, which is always current by definition.
@MainActor
enum Motion {
    static var isReduced: Bool { UIAccessibility.isReduceMotionEnabled }

    /// The given animation, or nil — which `withAnimation` reads as "apply the
    /// change now".
    ///
    /// A card sliding across the table is exactly the movement the setting asks
    /// to be spared, and unlike a panel appearing there is no gentler version
    /// to offer instead: the card has to end up on the other pile. So it simply
    /// arrives. Flips come along for free — the face-up state changes inside
    /// the same block, so the card turns over without the 3-D sweep.
    static func animation(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }
}
