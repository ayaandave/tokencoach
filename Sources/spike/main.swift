import Foundation
import TokenCoachCore

// Step 1 spike: read real chat files and print what's using the most today.

func k(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : "\(n / 1000)k" }

let clock = ContinuousClock()
let store = UsageStore()
let took = clock.measure { store.refresh() }
print("Read \(store.turns.count) replies from the last 8 days in \(took)")

let today = Calendar.current.startOfDay(for: Date())
let todays = store.turns(since: today)
let total = todays.reduce(0) { $0 + $1.weight }
print("\nToday: \(todays.count) replies, \(k(Int(total))) weighted tokens")
print("By app: " + Dictionary(grouping: todays, by: \.entrypoint).map { "\($0.key)=\($0.value.count)" }.joined(separator: " "))

print("\nTop chats today (share of today's usage, chat size now):")
for c in store.chats(since: today).prefix(8) {
    let share = Int((c.weight / max(total, 1) * 100).rounded())
    print(String(format: "  %3d%%  size %6@  %3d replies  %@  %@", share, k(c.size), c.replies,
                 (c.project as NSString).lastPathComponent, String(c.sessionId.prefix(8))))
}

let eaters = store.toolEaters(since: today)
print("\nTop tool eaters today (share of today's usage, calls, tokens added, biggest single result):")
for e in eaters.prefix(10) {
    let share = Int((e.weight / max(total, 1) * 100).rounded())
    print(String(format: "  %3d%%  %@ %4d calls  %6@ added  biggest %@", share, e.category.padding(toLength: 18, withPad: " ", startingAt: 0), e.calls,
                 k(e.tokens), k(e.biggest)))
}
let unknown = store.results.values.filter { $0.tool == "?" }.count
print("  (\(store.results.count) tool results in 8 days, \(unknown) with unknown tool)")

let fiveHours = store.turns(since: Date().addingTimeInterval(-5 * 3600))
print("\nLast 5 hours: \(fiveHours.count) replies, \(k(Int(fiveHours.reduce(0) { $0 + $1.weight }))) weighted")
print("Burn rate (15 min): \(Int(store.burnRate())) weighted/min")
if let c = store.currentChat() { print("Current chat: \((c.project as NSString).lastPathComponent) \(c.sessionId.prefix(8)), size \(k(c.size))") }

let incr = clock.measure { store.refresh() }
print("\nSecond refresh (only new lines): \(incr)")
