import SwiftUI
import TokenCoachCore

struct MenuPopover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            limitsSection
            Divider()
            chatSection
            if let t = model.tip { TipCard(tip: t) }
            Divider()
            liveSection
            Divider()
            topSection
            Divider()
            toolSection
            Divider()
            HStack {
                Toggle("Floating box", isOn: $model.showBox)
                Spacer()
                Picker("Size", selection: $model.boxSize) {
                    ForEach(BoxSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                .disabled(!model.showBox)
            }
            Toggle("Open at login", isOn: $model.launchAtLogin)
            HStack {
                Text("TokenCoach").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: Sections

    @ViewBuilder private var limitsSection: some View {
        if let l = model.limits, l.fiveHour != nil || l.sevenDay != nil {
            if let w = l.fiveHour { LimitBar(title: "5-hour limit", window: w) }
            if let w = l.sevenDay { LimitBar(title: "Weekly limit", window: w) }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Limits").font(.headline)
                Text("No limit reading yet. Turn on the TokenCoach status line to see your official 5-hour and weekly %.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var chatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This chat").font(.headline)
            if let c = model.currentChat {
                HStack {
                    Circle().fill(Level(chatSize: c.size).color).frame(width: 8, height: 8)
                    Text("\(Format.tokens(c.size)) re-read every message").monospacedDigit()
                    Spacer()
                    Text(Format.project(c.project)).foregroundStyle(.secondary)
                }.font(.callout)
            } else {
                Text(model.loaded ? "No chats in the last week." : "Reading your chats…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Live").font(.headline)
                Spacer()
                Text("\(Format.tokens(Int(model.burnPerMin)))/min · last 15 min").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Sparkline(values: model.sparkline).frame(height: 32)
        }
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Using the most today").font(.headline)
            if model.topChats.isEmpty {
                Text("Nothing yet today.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.topChats, id: \.sessionId) { c in
                HStack {
                    Text("\(Int((c.weight / max(model.todayWeight, 1) * 100).rounded()))%")
                        .monospacedDigit().frame(width: 38, alignment: .trailing)
                    Text(Format.project(c.project)).lineLimit(1)
                    Spacer()
                    Text("\(c.replies) msgs · \(Format.ago(c.lastTime))").foregroundStyle(.secondary).monospacedDigit()
                }.font(.callout)
            }
        }
    }

    private var toolSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top tool eaters today").font(.headline)
            if model.toolEaters.isEmpty {
                Text("No tool use yet today.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.toolEaters, id: \.category) { e in
                HStack {
                    Text("\(Int((e.weight / max(model.todayWeight, 1) * 100).rounded()))%")
                        .monospacedDigit().frame(width: 38, alignment: .trailing)
                    Text(e.category).lineLimit(1)
                    Spacer()
                    Text("\(e.calls) calls · \(Format.tokens(e.tokens)) added").foregroundStyle(.secondary).monospacedDigit()
                }.font(.callout)
            }
            if !model.toolEaters.isEmpty {
                Text("Tool output stays in the chat and is re-read by every later message. The rest of your usage is chat history and Claude's writing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Pieces

struct LimitBar: View {
    let title: String
    let window: Limits.Window

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(Int(window.usedPercent.rounded()))% · resets in \(Format.until(window.resetsAt))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: min(window.usedPercent, 100), total: 100)
                .tint(window.usedPercent >= 80 ? .red : window.usedPercent >= 50 ? .orange : .green)
        }
    }
}

struct TipCard: View {
    let tip: Tip
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(tip.title).font(.callout.weight(.semibold))
                Text(tip.text).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(compact ? 3 : nil).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: String {
        switch tip.level {
        case .alert: "exclamationmark.triangle.fill"
        case .warn: "exclamationmark.circle.fill"
        case .info: "lightbulb.fill"
        }
    }

    private var color: Color {
        switch tip.level {
        case .alert: .red
        case .warn: .orange
        case .info: .accentColor
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let peak = max(values.max() ?? 0, 1)
            let w = geo.size.width / CGFloat(max(values.count, 1))
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor.opacity(values[i] > 0 ? 0.85 : 0.15))
                        .frame(width: max(w - 1, 1), height: max(2, geo.size.height * values[i] / peak))
                }
            }
        }
    }
}

extension Level {
    var color: Color {
        switch self {
        case .green: .green
        case .yellow: .orange
        case .red: .red
        }
    }
}
