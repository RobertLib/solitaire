//
//  TimeFormat.swift
//  solitaire
//
//  One clock format, shared by the HUD, the results screen and the best-time
//  statistic so they can never disagree about how long a game took.
//

import Foundation

enum TimeFormat {
    /// A game clock the HUD can hold: `m:ss`, widening to `h:mm:ss` once a deal
    /// has been left running for an hour. Digits are monospaced wherever this
    /// is shown, so the extra field grows the label rather than jittering it.
    static func clock(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        let h = seconds / 3600
        let m = (seconds / 60) % 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Where the clock stops. A deal left open for days would otherwise widen
    /// the HUD without limit, and the time bonus is long dead by then anyway.
    static let maxSeconds = 99 * 3600 + 59 * 60 + 59
}
