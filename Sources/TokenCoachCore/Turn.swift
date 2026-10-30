import Foundation

/// One reply from Claude, with the tokens it used.
public struct Turn: Sendable {
    public let key: String          // message id + request id, used to skip duplicate lines
    public let sessionId: String
    public let project: String      // folder the chat runs in
    public let time: Date
    public let model: String
    public let entrypoint: String   // "cli" or "claude-desktop"
    public let input: Int
    public let cacheRead: Int
    public let cacheWrite: Int
    public let output: Int
    public var tools: [String]

    /// How big the chat was when this reply was made (everything Claude had to re-read).
    public var chatSize: Int { input + cacheRead + cacheWrite }

    /// Rough "cost weight" relative to one fresh input token.
    /// Re-reading cached chat is cheap (0.1), writing the cache costs a bit more (1.25), output is pricey (5).
    /// Only used to rank what eats the most usage, not as a real bill.
    public var weight: Double {
        Double(input) + Double(cacheRead) * 0.1 + Double(cacheWrite) * 1.25 + Double(output) * 5
    }
}

enum TurnParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let assistantTag = Data(#""type":"assistant""#.utf8)
    private static let usageTag = Data(#""usage":"#.utf8)

    /// Returns a Turn for assistant lines that carry token counts, nil for everything else.
    static func parse(_ line: Data) -> Turn? {
        // Cheap byte search first: most lines are not assistant replies, and full JSON parsing is slow.
        guard line.range(of: assistantTag) != nil, line.range(of: usageTag) != nil else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let time = iso.date(from: stamp)
        else { return nil }

        let model = msg["model"] as? String ?? "?"
        if model == "<synthetic>" { return nil }
        let id = (msg["id"] as? String ?? UUID().uuidString) + ":" + (obj["requestId"] as? String ?? "")
        let tools = (msg["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "tool_use" }
            .compactMap { $0["name"] as? String }

        return Turn(
            key: id,
            sessionId: obj["sessionId"] as? String ?? "?",
            project: obj["cwd"] as? String ?? "?",
            time: time,
            model: model,
            entrypoint: obj["entrypoint"] as? String ?? "?",
            input: usage["input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            tools: tools
        )
    }
}
