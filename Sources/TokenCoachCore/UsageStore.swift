import Foundation

/// Reads Claude Code chat files (~/.claude/projects/**/*.jsonl) and keeps every reply's token counts.
/// Each call to `refresh()` reads only the bytes added since last time, so it's cheap to call often.
/// Not thread-safe: use it from one queue at a time (the app keeps it on a single background queue).
public final class UsageStore: @unchecked Sendable {
    public let root: URL
    public let lookback: TimeInterval
    public private(set) var turns: [String: Turn] = [:]
    public private(set) var results: [String: ToolResult] = [:]   // by tool call id
    private var toolNames: [String: String] = [:]                  // tool call id -> tool name
    private var offsets: [URL: UInt64] = [:]

    public init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects"),
                lookback: TimeInterval = 8 * 24 * 3600) {
        self.root = root
        self.lookback = lookback
    }

    /// Reads new lines from every chat file touched within the lookback window. Returns true if anything changed.
    @discardableResult
    public func refresh() -> Bool {
        let cutoff = Date().addingTimeInterval(-lookback)
        var changed = false
        for url in chatFiles(modifiedAfter: cutoff) {
            changed = readNewLines(url, cutoff: cutoff) || changed
        }
        turns = turns.filter { $0.value.time >= cutoff }
        results = results.filter { $0.value.time >= cutoff }
        toolNames = toolNames.filter { results[$0.key] == nil }   // matched ids aren't needed again
        return changed
    }

    private func chatFiles(modifiedAfter cutoff: Date) -> [URL] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var out: [URL] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mod >= cutoff { out.append(url) }
        }
        return out
    }

    private func readNewLines(_ url: URL, cutoff: Date) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        let start = offsets[url] ?? 0
        let end = (try? h.seekToEnd()) ?? 0
        if end < start { offsets[url] = 0; return readNewLines(url, cutoff: cutoff) } // file was rewritten
        guard end > start else { return false }
        try? h.seek(toOffset: start)
        guard let data = try? h.readToEnd() else { return false }

        // Only consume up to the last full line; a half-written line is read next time.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return false }
        offsets[url] = start + UInt64(lastNewline - data.startIndex + 1)
        var changed = false
        for line in data[data.startIndex...lastNewline].split(separator: UInt8(ascii: "\n")) {
            switch TurnParser.parse(line) {
            case let .turn(t, toolIds)?:
                for (id, name) in toolIds { toolNames[id] = name }
                guard t.time >= cutoff else { continue }
                // One reply can be split across several lines with the same id; keep one, merge tool names.
                if var existing = turns[t.key] {
                    existing.tools += t.tools
                    turns[t.key] = existing
                } else {
                    turns[t.key] = t
                }
                changed = true
            case let .results(sessionId, time, items)?:
                guard time >= cutoff else { continue }
                for (id, tokens) in items {
                    results[id] = ToolResult(sessionId: sessionId, time: time, tool: toolNames[id] ?? "?", tokens: tokens)
                }
                changed = true
            case nil:
                continue
            }
        }
        return changed
    }
}

// MARK: - Questions the app asks

public struct ChatSummary: Sendable {
    public let sessionId: String
    public let project: String
    public let lastTime: Date
    public let replies: Int
    public let size: Int          // tokens re-read by the latest reply
    public let weight: Double     // total cost weight in the window
    public let output: Int

    public init(sessionId: String, project: String, lastTime: Date, replies: Int, size: Int, weight: Double, output: Int) {
        self.sessionId = sessionId; self.project = project; self.lastTime = lastTime
        self.replies = replies; self.size = size; self.weight = weight; self.output = output
    }
}

/// A kind of tool (file reads, web, browser...) and how much it cost.
public struct ToolEater: Sendable {
    public let category: String
    public let calls: Int
    public let tokens: Int        // tokens added to chats
    public let weight: Double     // cost weight: written once, then re-read by every later reply in that chat
    public let biggest: Int       // largest single result

    public init(category: String, calls: Int, tokens: Int, weight: Double, biggest: Int) {
        self.category = category; self.calls = calls; self.tokens = tokens; self.weight = weight; self.biggest = biggest
    }
}

public enum ToolCategory {
    /// Groups raw tool names into plain-language buckets.
    public static func of(_ tool: String) -> String {
        switch tool {
        case "Read", "NotebookRead": return "File reads"
        case "Write", "Edit", "MultiEdit", "NotebookEdit": return "File edits"
        case "Bash", "BashOutput": return "Terminal commands"
        case "Grep", "Glob", "LS": return "Searches"
        case "WebFetch", "WebSearch": return "Web"
        case "Agent", "Task": return "Subagents"
        case "?": return "Other tools"
        default: break
        }
        if tool.hasPrefix("mcp__Claude_Browser__") || tool.hasPrefix("mcp__claude-in-chrome__") { return "Browser" }
        if tool.hasPrefix("mcp__computer-use__") { return "Screen control" }
        if tool.hasPrefix("mcp__Claude_Code_iOS_Simulator__") { return "iOS Simulator" }
        if tool.hasPrefix("mcp__ccd_") || tool.hasPrefix("mcp__visualize__") { return "Claude app tools" }
        if tool.hasPrefix("mcp__") { return "Connectors" }
        return "Other tools"
    }
}

public extension UsageStore {
    func turns(since date: Date) -> [Turn] {
        turns.values.filter { $0.time >= date }.sorted { $0.time < $1.time }
    }

    /// Per-chat totals for replies since `date`, biggest usage first.
    func chats(since date: Date) -> [ChatSummary] {
        Dictionary(grouping: turns(since: date), by: \.sessionId).map { id, ts in
            let last = ts.last!
            return ChatSummary(sessionId: id, project: last.project, lastTime: last.time, replies: ts.count,
                               size: last.chatSize, weight: ts.reduce(0) { $0 + $1.weight },
                               output: ts.reduce(0) { $0 + $1.output })
        }.sorted { $0.weight > $1.weight }
    }

    /// The chat that replied most recently — almost always the one you're working in.
    func currentChat() -> ChatSummary? {
        guard let last = turns.values.max(by: { $0.time < $1.time }) else { return nil }
        return chats(since: .distantPast).first { $0.sessionId == last.sessionId }
    }

    /// Cost weight per minute over the last `minutes`.
    func burnRate(minutes: Double = 15) -> Double {
        turns(since: Date().addingTimeInterval(-minutes * 60)).reduce(0) { $0 + $1.weight } / minutes
    }

    /// Tool kinds ranked by cost weight for results since `date`.
    /// A result's weight counts the cache write once, plus a cheap re-read for every later reply in the same chat,
    /// so a big file read early in a long chat ranks above the same read in a short one.
    func toolEaters(since date: Date) -> [ToolEater] {
        let replyTimes = Dictionary(grouping: turns.values, by: \.sessionId).mapValues { $0.map(\.time).sorted() }
        struct Acc { var calls = 0, tokens = 0, biggest = 0; var weight = 0.0 }
        var acc: [String: Acc] = [:]
        for r in results.values where r.time >= date {
            let later = replyTimes[r.sessionId].map { times in times.count - firstIndex(after: r.time, in: times) } ?? 0
            var a = acc[ToolCategory.of(r.tool), default: Acc()]
            a.calls += 1
            a.tokens += r.tokens
            a.biggest = max(a.biggest, r.tokens)
            a.weight += Double(r.tokens) * (1.25 + 0.1 * Double(max(later - 1, 0)))
            acc[ToolCategory.of(r.tool)] = a
        }
        return acc.map { ToolEater(category: $0.key, calls: $0.value.calls, tokens: $0.value.tokens,
                                   weight: $0.value.weight, biggest: $0.value.biggest) }
            .sorted { $0.weight > $1.weight }
    }
}

/// Index of the first time strictly after `t` (binary search over sorted times).
private func firstIndex(after t: Date, in times: [Date]) -> Int {
    var lo = 0, hi = times.count
    while lo < hi {
        let mid = (lo + hi) / 2
        if times[mid] <= t { lo = mid + 1 } else { hi = mid }
    }
    return lo
}
