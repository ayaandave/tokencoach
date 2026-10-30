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

/// Something a tool sent back into the chat (file contents, command output, a screenshot...).
/// It stays in the chat, so every later reply re-reads it.
public struct ToolResult: Sendable {
    public let sessionId: String
    public let time: Date
    public let tool: String
    public let tokens: Int          // estimated: ~4 characters per token, ~1,600 per image
}

enum ParsedLine {
    case turn(Turn, toolIds: [(id: String, name: String)])
    case results(sessionId: String, time: Date, [(toolId: String, tokens: Int)])
}

enum TurnParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let assistantTag = Data(#""type":"assistant""#.utf8)
    private static let usageTag = Data(#""usage":"#.utf8)
    private static let resultTag = Data(#""tool_result""#.utf8)

    /// Returns a Turn for assistant lines that carry token counts, tool results for user lines that have them,
    /// nil for everything else.
    static func parse(_ line: Data) -> ParsedLine? {
        // Cheap byte search first: most lines are neither, and full JSON parsing is slow.
        let isTurn = line.range(of: assistantTag) != nil && line.range(of: usageTag) != nil
        guard isTurn || line.range(of: resultTag) != nil,
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let stamp = obj["timestamp"] as? String,
              let time = iso.date(from: stamp),
              let msg = obj["message"] as? [String: Any]
        else { return nil }
        let sessionId = obj["sessionId"] as? String ?? "?"
        let content = msg["content"] as? [[String: Any]] ?? []

        if obj["type"] as? String == "user" {
            let results = content.filter { $0["type"] as? String == "tool_result" }.compactMap { block -> (String, Int)? in
                guard let id = block["tool_use_id"] as? String else { return nil }
                return (id, estimateTokens(block["content"]))
            }
            return results.isEmpty ? nil : .results(sessionId: sessionId, time: time, results)
        }

        guard obj["type"] as? String == "assistant",
              let usage = msg["usage"] as? [String: Any]
        else { return nil }

        let model = msg["model"] as? String ?? "?"
        if model == "<synthetic>" { return nil }
        let id = (msg["id"] as? String ?? UUID().uuidString) + ":" + (obj["requestId"] as? String ?? "")
        let toolIds = content.filter { $0["type"] as? String == "tool_use" }.compactMap { block -> (id: String, name: String)? in
            guard let id = block["id"] as? String, let name = block["name"] as? String else { return nil }
            return (id, name)
        }

        let turn = Turn(
            key: id,
            sessionId: sessionId,
            project: obj["cwd"] as? String ?? "?",
            time: time,
            model: model,
            entrypoint: obj["entrypoint"] as? String ?? "?",
            input: usage["input_tokens"] as? Int ?? 0,
            cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
            cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0,
            output: usage["output_tokens"] as? Int ?? 0,
            tools: toolIds.map(\.name)
        )
        return .turn(turn, toolIds: toolIds)
    }

    /// Tool result content is either a string or a list of text / image blocks.
    private static func estimateTokens(_ content: Any?) -> Int {
        if let text = content as? String { return text.utf8.count / 4 }
        guard let blocks = content as? [[String: Any]] else { return 0 }
        return blocks.reduce(0) { sum, b in
            switch b["type"] as? String {
            case "text": sum + ((b["text"] as? String)?.utf8.count ?? 0) / 4
            case "image": sum + 1600
            default: sum
            }
        }
    }
}
