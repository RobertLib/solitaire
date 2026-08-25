//
//  ContentView.swift
//  solitaire
//

import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    /// The one game this process plays.
    ///
    /// Not a convenience: `@State private var model = AppModel()` would build a
    /// fresh one on *every* `ContentView` initialiser, and SwiftUI re-runs the
    /// `WindowGroup` closure whenever the scene updates — a dozen-plus times on
    /// an ordinary launch. SwiftUI keeps the first and throws the rest away, but
    /// not before each has dealt itself a game, played the shuffle sound, and
    /// raced the real one for the saved-game key. Handing every caller the same
    /// instance makes those repeat initialisers free.
    static let shared = AppModel()

    let settings: GameSettings
    let statistics: Statistics
    let game: GameViewModel

    private init() {
        let settings = GameSettings()
        // Kicked off here so the synthesiser is ready by the time the deal
        // animation asks for its first sound, rather than being built on the
        // main actor at the moment one is wanted.
        SoundManager.prepare(enabled: settings.soundsEnabled)
        let statistics = Statistics()
        self.settings = settings
        self.statistics = statistics
        self.game = GameViewModel(settings: settings, statistics: statistics)
        #if DEBUG
        game.applyLaunchScenario()
        // After the QA scenarios, so a `-shot` pose has the last word on the
        // board it photographs.
        Shots.apply(settings: settings, statistics: statistics, game: game)
        #endif
    }
}

private enum ActiveSheet: String, Identifiable {
    case menu, settings, statistics, help
    var id: String { rawValue }
}

struct ContentView: View {
    private let model = AppModel.shared
    @State private var activeSheet: ActiveSheet?
    @State private var pendingSheet: ActiveSheet?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How the wand, the dead-end banner and the results screen arrive.
    /// Reduce Motion keeps the fade and drops the spring behind it — a panel
    /// that grows into place is movement, a panel that appears is not.
    private var appearAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.4)
    }

    var body: some View {
        ZStack {
            TableBackground(theme: model.settings.tableTheme)

            VStack(spacing: 0) {
                TopHUD(vm: model.game)
                BoardView(vm: model.game)
                    .overlay(alignment: .bottom) { boardBottomOverlay }
                BottomBar(vm: model.game) { activeSheet = .menu }
                    // The results panel dims the board, but the control bar
                    // went on showing through it — three buttons that look
                    // available while the panel quietly swallows their taps.
                    .opacity(model.game.isWon ? 0 : 1)
            }

            if model.game.isWon {
                WinView(vm: model.game, theme: model.settings.tableTheme)
            }
        }
        .animation(appearAnimation, value: model.game.canAutoFinish)
        .animation(appearAnimation, value: model.game.isStuck)
        .animation(.easeInOut(duration: 0.5), value: model.game.isWon)
        .sheet(item: $activeSheet, onDismiss: presentPendingSheet) { sheet in
            switch sheet {
            case .menu:
                MenuSheet(
                    vm: model.game,
                    onSettings: { switchSheet(to: .settings) },
                    onStatistics: { switchSheet(to: .statistics) },
                    onHelp: { switchSheet(to: .help) }
                )
            case .settings:
                SettingsView(settings: model.settings)
            case .statistics:
                StatisticsView(statistics: model.statistics)
            case .help:
                HelpView()
            }
        }
        .onChange(of: activeSheet) { _, newValue in
            model.game.isPaused = newValue != nil
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.game.isPaused = activeSheet != nil
            case .inactive, .background:
                model.game.isPaused = true
                model.game.saveGame()
            @unknown default:
                break
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-landscape") {
                (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
                    .requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
            }
            if args.contains("-open-settings") { activeSheet = .settings }
            if args.contains("-open-menu") { activeSheet = .menu }
            if args.contains("-open-stats") { activeSheet = .statistics }
            if args.contains("-open-help") { activeSheet = .help }
        }
        #endif
    }

    /// The wand and the dead-end banner hang off the bottom of the board, not
    /// the bottom of the screen: anchored to the screen they sat on top of the
    /// control bar, clipping Undo and Hint and swallowing taps meant for them.
    @ViewBuilder
    private var boardBottomOverlay: some View {
        if model.game.canAutoFinish {
            AutoFinishButton(theme: model.settings.tableTheme) {
                model.game.autoFinish()
            }
            .padding(.bottom, 16)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
        } else if model.game.isStuck {
            NoMovesBanner(
                theme: model.settings.tableTheme,
                canUndo: model.game.canUndo,
                onUndo: { model.game.undo() },
                onNewGame: { model.game.newGame() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
        }
    }

    /// Replacing one sheet with another: dismiss the first, then present the
    /// next from its dismissal handler so the two never overlap.
    private func switchSheet(to sheet: ActiveSheet) {
        pendingSheet = sheet
        activeSheet = nil
    }

    private func presentPendingSheet() {
        guard let next = pendingSheet else { return }
        pendingSheet = nil
        activeSheet = next
    }
}

#Preview {
    ContentView()
}
