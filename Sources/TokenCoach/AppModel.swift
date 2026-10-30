import Foundation
import TokenCoachCore

/// Everything the UI shows, refreshed every few seconds from the chat files.
@MainActor
final class AppModel: ObservableObject {
    @Published var loaded = false
    @Published var limits: Limits?
    @Published var currentChat: ChatSummary?
    @Published var topChats: [ChatSummary] = []
    @Published var toolEaters: [ToolEater] = []
    @Published var todayWeight: Double = 0
    @Published var burnPerMin: Double = 0
    @Published var sparkline: [Double] = []   // weight per minute, last 30 minutes
    @Published var tip: Tip?                   // the one tip for right now

    private let notifier = Notifier()

    private let store = UsageStore()
    private let queue = DispatchQueue(label: "tokencoach.store")
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let store = self.store
        queue.async {
            store.refresh()
            let today = Calendar.current.startOfDay(for: Date())
            let chats = store.chats(since: today)
            let eaters = store.toolEaters(since: today)
            let current = store.currentChat()
            let burn = store.burnRate()
            let now = Date()
            var buckets = [Double](repeating: 0, count: 30)
            for t in store.turns(since: now.addingTimeInterval(-30 * 60)) {
                let i = 29 - min(29, Int(now.timeIntervalSince(t.time) / 60))
                buckets[i] += t.weight
            }
            let limits = Limits.load()
            let tips = Coach.tips(store.coachInput(limits: limits, now: now))
            DispatchQueue.main.async {
                self.limits = limits
                self.currentChat = current
                self.topChats = Array(chats.prefix(5))
                self.toolEaters = Array(eaters.prefix(4))
                self.todayWeight = chats.reduce(0) { $0 + $1.weight }
                self.burnPerMin = burn
                self.sparkline = buckets
                self.tip = tips.first
                self.notifier.consider(tips)
                self.loaded = true
            }
        }
    }

    /// What the menu bar shows: the official 5-hour % when we have it, otherwise the current chat's size.
    var menuTitle: String {
        if !loaded { return "…" }
        if let five = limits?.fiveHour { return "\(Int(five.usedPercent.rounded()))%" }
        if let c = currentChat { return Format.tokens(c.size) }
        return "–"
    }

    var level: Level {
        if let five = limits?.fiveHour { return five.usedPercent >= 80 ? .red : five.usedPercent >= 50 ? .yellow : .green }
        guard let c = currentChat else { return .green }
        return Level(chatSize: c.size)
    }
}

enum Level {
    case green, yellow, red
    init(chatSize: Int) {
        let t = Thresholds.load()
        self = chatSize >= t.chatHard ? .red : chatSize >= t.chatSoft ? .yellow : .green
    }
}

enum Format {
    static func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)"
    }
    static func ago(_ d: Date) -> String {
        let m = Int(Date().timeIntervalSince(d) / 60)
        return m < 1 ? "now" : m < 60 ? "\(m)m ago" : "\(m / 60)h ago"
    }
    static func until(_ d: Date) -> String {
        let m = max(0, Int(d.timeIntervalSinceNow / 60))
        return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
    }
    static func project(_ path: String) -> String { (path as NSString).lastPathComponent }
}
