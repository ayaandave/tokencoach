import Foundation

/// Reads Claude Code chat files (~/.claude/projects/**/*.jsonl) and keeps every reply's token counts.
/// Each call to `refresh()` reads only the bytes added since last time, so it's cheap to call often.
/// Not thread-safe: use it from one queue at a time (the app keeps it on a single background queue).
public final class UsageStore: @unchecked Sendable {
    public let root: URL
    public let lookback: TimeInterval
    public private(set) var turns: [String: Turn] = [:]
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
            guard let t = TurnParser.parse(line), t.time >= cutoff else { continue }
            // One reply can be split across several lines with the same id; keep one, merge tool names.
            if var existing = turns[t.key] {
                existing.tools += t.tools
                turns[t.key] = existing
            } else {
                turns[t.key] = t
            }
            changed = true
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
}
