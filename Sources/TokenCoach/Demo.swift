import AppKit
import SwiftUI
import TokenCoachCore

/// Demo mode for website screenshots: run with TOKENCOACH_DEMO=1 (and optionally TOKENCOACH_DEMO_SIZE=small|medium|large).
/// Fills the model with made-up numbers, opens the popup in its own window, and prints each window's number
/// so `screencapture -l <number>` can grab it.
extension AppModel {
    func loadDemo() {
        let now = Date()
        if let s = ProcessInfo.processInfo.environment["TOKENCOACH_DEMO_SIZE"], let size = BoxSize(rawValue: s) { boxSize = size }
        limits = Limits(fiveHour: .init(usedPercent: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60)),
                        sevenDay: .init(usedPercent: 18, resetsAt: now.addingTimeInterval(4 * 86400 + 3 * 3600)),
                        savedAt: now)
        let chat = { (id: String, project: String, ago: Double, replies: Int, size: Int, weight: Double) in
            ChatSummary(sessionId: id, project: "/Users/you/Projects/\(project)", lastTime: now.addingTimeInterval(-ago * 60),
                        replies: replies, size: size, weight: weight, output: 0)
        }
        currentChat = chat("a", "my-app", 0, 42, 86_000, 41)
        topChats = [chat("a", "my-app", 0, 42, 86_000, 41), chat("b", "website", 95, 63, 140_000, 27),
                    chat("c", "api-server", 210, 18, 52_000, 14), chat("d", "notes", 300, 9, 21_000, 6)]
        todayWeight = 100
        toolEaters = [ToolEater(category: "File reads", calls: 118, tokens: 310_000, weight: 22, biggest: 0),
                      ToolEater(category: "Shell commands", calls: 64, tokens: 140_000, weight: 11, biggest: 0),
                      ToolEater(category: "Web", calls: 9, tokens: 60_000, weight: 6, biggest: 0)]
        burnPerMin = 18_000
        sparkline = [0, 0, 0, 2, 3, 1, 0, 0, 4, 6, 5, 3, 0, 0, 0, 2, 5, 8, 7, 6, 3, 2, 0, 0, 3, 5, 9, 7, 4, 6]
        tip = Tip(rule: "demo", level: .info, title: "Healthy chat size", text: "One task per chat keeps it that way.", notifyKey: nil)
        loaded = true
    }

    func showDemoPopover() {
        let host = NSHostingView(rootView: MenuPopover(model: self)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.setFrameTopLeftPoint(NSPoint(x: 80, y: (NSScreen.main?.visibleFrame.maxY ?? 900) - 20))
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            for w in NSApp.windows where w.isVisible {
                print("window \(w.windowNumber) \(Int(w.frame.width))x\(Int(w.frame.height)) \(w === panel ? "popup" : "box")")
            }
            fflush(stdout)
        }
    }
}
