import Foundation

/// One piece of advice for right now.
public struct Tip: Sendable, Equatable {
    public enum Level: Int, Sendable, Comparable {
        case info, warn, alert
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }
    public let rule: String        // which rule made it, e.g. "chat.hard"
    public let level: Level
    public let title: String
    public let text: String
    /// Set for warnings worth a Mac notification. The same key only notifies once,
    /// so it names what the warning is about (this chat, this 5-hour window).
    public let notifyKey: String?
}

/// When the rules kick in. Lower them to test: `defaults write com.tokencoach.app chatSoft -int 10000`,
/// or set TOKENCOACH_CHAT_SOFT=10000 in the environment (handy for the spike CLI).
public struct Thresholds: Sendable {
    public var chatSoft = 150_000          // chat size (tokens re-read per message): getting long
    public var chatHard = 300_000          // very long, start fresh
    public var limitWarn = 80.0            // 5-hour limit %
    public var limitAlert = 90.0
    public var idleMinutes = 60.0          // cache goes cold after about an hour
    public var idleMinSize = 50_000        // only worth a tip if the chat is big enough to hurt
    public var toolShare = 0.10            // a tool kind using this share of today gets a tip

    public init() {}

    public static func load(defaults: UserDefaults = .standard,
                            env: [String: String] = ProcessInfo.processInfo.environment) -> Thresholds {
        var t = Thresholds()
        func read(_ key: String) -> Double? {
            let envKey = "TOKENCOACH_" + key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1_$2", options: .regularExpression).uppercased()
            if let s = env[envKey], let v = Double(s) { return v }
            return defaults.object(forKey: key) == nil ? nil : defaults.double(forKey: key)
        }
        if let v = read("chatSoft") { t.chatSoft = Int(v) }
        if let v = read("chatHard") { t.chatHard = Int(v) }
        if let v = read("limitWarn") { t.limitWarn = v }
        if let v = read("limitAlert") { t.limitAlert = v }
        if let v = read("idleMinutes") { t.idleMinutes = v }
        if let v = read("toolShare") { t.toolShare = v }
        return t
    }
}

/// What the coach looks at.
public struct CoachInput: Sendable {
    public var now = Date()
    public var currentChat: ChatSummary?
    public var burnPerMin: Double = 0          // cost weight per minute, last 15 min
    public var fiveHour: Limits.Window?
    public var fiveHourWeight: Double = 0      // cost weight used so far in this 5-hour window
    public var toolEaters: [ToolEater] = []    // today
    public var todayWeight: Double = 0

    public init() {}
}

/// Simple rules that turn usage numbers into advice. No AI, just thresholds.
/// Chat size comes first: tool output is only about a fifth of usage, re-reading chat history is most of the rest.
public enum Coach {
    /// Every tip that applies right now, most useful first. Never empty: falls back to a healthy-chat tip.
    public static func tips(_ input: CoachInput, thresholds t: Thresholds = .load()) -> [Tip] {
        var out: [Tip] = []
        let chat = input.currentChat
        let size = chat?.size ?? 0
        let chatId = chat?.sessionId ?? "-"

        // 1. Very big chat.
        if size >= t.chatHard {
            out.append(Tip(rule: "chat.hard", level: .alert, title: "Very big chat (\(short(size)))",
                           text: "Every message re-reads all of it. Say \"wrap up\" so Claude saves notes, then /clear and start fresh.",
                           notifyKey: "chat.hard|\(chatId)"))
        }

        // 2. 5-hour limit, and where this pace takes it.
        if let w = input.fiveHour {
            let windowId = Int(w.resetsAt.timeIntervalSince1970)
            let resets = clock(w.resetsAt)
            if w.usedPercent >= t.limitAlert {
                out.append(Tip(rule: "limit.alert", level: .alert, title: "\(Int(w.usedPercent))% of your 5-hour limit",
                               text: "Save your work now and keep messages small. It resets at \(resets).",
                               notifyKey: "limit.alert|\(windowId)"))
            } else if let hit = limitHitTime(input, window: w), hit < w.resetsAt {
                out.append(Tip(rule: "limit.pace", level: .warn, title: "On pace to hit the limit at \(clock(hit))",
                               text: "It resets at \(resets). Slow down: finish this task, /clear, and use smaller chats.",
                               notifyKey: "limit.pace|\(windowId)"))
            } else if w.usedPercent >= t.limitWarn {
                out.append(Tip(rule: "limit.warn", level: .warn, title: "\(Int(w.usedPercent))% of your 5-hour limit",
                               text: "Plenty of room is gone. Keep chats short until it resets at \(resets).",
                               notifyKey: "limit.warn|\(windowId)"))
            }
        }

        // 3. Getting long.
        if size >= t.chatSoft && size < t.chatHard {
            out.append(Tip(rule: "chat.soft", level: .warn, title: "Chat getting long (\(short(size)))",
                           text: "Finish this task, then say \"wrap up\" and start a new chat.",
                           notifyKey: "chat.soft|\(chatId)"))
        }

        // 4. Cold cache: after an hour away, the next message re-pays for the whole chat.
        if let c = chat, size >= t.idleMinSize, input.now.timeIntervalSince(c.lastTime) >= t.idleMinutes * 60 {
            out.append(Tip(rule: "chat.idle", level: .info, title: "This chat has gone cold",
                           text: "It's been idle over an hour, so the next message pays full price for all \(short(size)). Start a new chat instead.",
                           notifyKey: nil))
        }

        // 5. A tool kind eating a big share of today.
        for e in input.toolEaters {
            let share = e.weight / max(input.todayWeight, 1)
            guard share >= t.toolShare, let advice = toolAdvice[e.category] else { continue }
            out.append(Tip(rule: "tool.\(e.category)", level: .info, title: "\(e.category): \(Int((share * 100).rounded()))% of today",
                           text: advice, notifyKey: nil))
            break   // the biggest one is enough
        }

        if out.isEmpty {
            out.append(Tip(rule: "ok", level: .info, title: chat == nil ? "All quiet" : "Healthy chat size",
                           text: "One task per chat keeps it that way.", notifyKey: nil))
        }
        return out
    }

    /// The single most useful tip right now.
    public static func best(_ input: CoachInput, thresholds: Thresholds = .load()) -> Tip {
        tips(input, thresholds: thresholds)[0]
    }

    /// When the 5-hour limit runs out at the last 15 minutes' pace, using this window's weight-per-% as the exchange rate.
    /// The % also counts claude.ai and other devices, so it's a rough guess.
    static func limitHitTime(_ input: CoachInput, window w: Limits.Window) -> Date? {
        guard w.usedPercent >= 10, input.fiveHourWeight > 0, input.burnPerMin > 0 else { return nil }
        let weightPerPercent = input.fiveHourWeight / w.usedPercent
        let minutesLeft = (100 - w.usedPercent) * weightPerPercent / input.burnPerMin
        return input.now.addingTimeInterval(minutesLeft * 60)
    }

    static let toolAdvice: [String: String] = [
        "Browser": "Screenshots are big and stay in the chat. Ask Claude to use read_page or get_page_text instead of screenshots.",
        "Screen control": "Every screenshot stays in the chat. Ask for fewer screenshots, or zoom into just the part that matters.",
        "iOS Simulator": "Simulator screenshots stay in the chat. Ask for fewer of them, only when checking something visual.",
        "File reads": "Whole files stay in the chat. Ask Claude to read only the lines it needs, or to search first.",
        "Searches": "Big search results stay in the chat. For wide searches, ask Claude to use a subagent; only its answer comes back.",
        "Terminal commands": "Long command output stays in the chat. Ask for quieter commands (for example, only the last lines of a log).",
        "Web": "Web pages stay in the chat. For research, ask Claude to use a subagent so only the summary comes back.",
        "Connectors": "Connector results stay in the chat. Ask for smaller results (filters, fewer rows), or use a subagent.",
    ]

    static func short(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : "\(n / 1000)k"
    }

    static func clock(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
}

public extension UsageStore {
    /// Gathers what the coach needs from the store.
    func coachInput(limits: Limits?, now: Date = Date()) -> CoachInput {
        let today = Calendar.current.startOfDay(for: now)
        var input = CoachInput()
        input.now = now
        input.currentChat = currentChat()
        input.burnPerMin = burnRate()
        input.toolEaters = toolEaters(since: today)
        input.todayWeight = turns(since: today).reduce(0) { $0 + $1.weight }
        if let w = limits?.fiveHour {
            input.fiveHour = w
            input.fiveHourWeight = turns(since: w.resetsAt.addingTimeInterval(-5 * 3600)).reduce(0) { $0 + $1.weight }
        }
        return input
    }
}
