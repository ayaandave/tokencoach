import Foundation

/// Official 5-hour / 7-day limit numbers, saved by scripts/statusline.sh whenever a Claude Code chat updates.
public struct Limits: Sendable {
    public struct Window: Sendable {
        public let usedPercent: Double
        public let resetsAt: Date
    }
    public let fiveHour: Window?
    public let sevenDay: Window?
    public let savedAt: Date

    public static let file = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/TokenCoach/statusline.json")

    /// Reads the saved file. Windows whose reset time has passed are dropped, since they're stale.
    public static func load(from url: URL = file) -> Limits? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = obj["rate_limits"] as? [String: Any]
        else { return nil }
        let saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast

        func window(_ name: String) -> Window? {
            guard let w = rl[name] as? [String: Any],
                  let pct = (w["used_percentage"] as? NSNumber)?.doubleValue,
                  let reset = (w["resets_at"] as? NSNumber)?.doubleValue
            else { return nil }
            let date = Date(timeIntervalSince1970: reset)
            return date > Date() ? Window(usedPercent: pct, resetsAt: date) : nil
        }
        return Limits(fiveHour: window("five_hour"), sevenDay: window("seven_day"), savedAt: saved)
    }
}
