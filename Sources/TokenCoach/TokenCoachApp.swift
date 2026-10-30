import SwiftUI

@main
struct TokenCoachApp: App {
    @StateObject private var model = AppModel()

    init() {
        // Menu bar only: no Dock icon, no main window.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuPopover(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(model.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
