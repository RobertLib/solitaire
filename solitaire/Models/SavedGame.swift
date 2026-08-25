//
//  SavedGame.swift
//  solitaire
//
//  The snapshot of a game in progress that survives closing the app. Kept UI-free
//  so the decode path — the one place a shipped build meets bytes it did not
//  write itself — can be exercised from the command-line tests.
//

import Foundation

struct SavedGame: Codable, Equatable {
    var state: GameState
    var seed: UInt64
    var drawCount: Int
    var scoring: ScoreKeeper
    var moves: Int
    var elapsedSeconds: Int
    var recyclesUsed: Int
    var hasStarted: Bool
    // Added after the first release. A default value is not enough: the
    // synthesised decoder throws on a missing key, which would throw away
    // the game saved by an older version. Optional keeps those loadable.
    var vegasSettled: Bool?
    /// The undo history in `UndoHistory`'s packed form — opaque here, and
    /// checked over by that type when it is read back. Optional for the same
    /// reason `vegasSettled` is, and nil is also what a save whose history did
    /// not survive validation is left with.
    var history: Data?

    /// Whether this snapshot is worth resuming.
    ///
    /// Decoding only proves the shape of the blob, not that it describes a board
    /// the rules could have produced, and every routine downstream — dragging,
    /// hinting, auto-finish — assumes the invariants hold. A game that was
    /// already won is dropped for a different reason: there is nothing left to
    /// play, and restoring it would put the victory screen back up.
    var isResumable: Bool {
        guard !state.isWon, state.isConsistent else { return false }
        guard drawCount == 1 || drawCount == 3 else { return false }
        return moves >= 0 && elapsedSeconds >= 0 && recyclesUsed >= 0
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Reads back a snapshot, or nil if the bytes are not a game that can be
    /// resumed. A nil is the caller's cue to throw the stored blob away rather
    /// than fail on it again at every launch.
    static func decode(_ data: Data) -> SavedGame? {
        guard var saved = try? JSONDecoder().decode(SavedGame.self, from: data),
              saved.isResumable else { return nil }
        // A history that does not check out is not worth losing the game over:
        // the board itself is sound, so keep playing it and drop the history.
        if let history = saved.history, UndoHistory(packed: history) == nil {
            saved.history = nil
        }
        return saved
    }
}
