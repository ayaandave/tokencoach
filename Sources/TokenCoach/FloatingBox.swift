import AppKit
import Combine
import SwiftUI
import TokenCoachCore

/// The small always-on-top box in the screen corner. Owns its NSPanel; AppModel shows or hides it.
@MainActor
final class FloatingBox {
    private let panel: NSPanel
    private let host: NSHostingView<FloatingBoxView>
    private var watch: AnyCancellable?
    private static let originKey = "floatingBoxTopLeft"

    init(model: AppModel) {
        host = NSHostingView(rootView: FloatingBoxView(model: model))
        host.sizingOptions = [.intrinsicContentSize]   // report a size, but we move the panel ourselves so its top edge stays put
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.contentView = host
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveOrigin() }
        }
        // After each refresh, grow or shrink to fit the content (the tip can change length).
        watch = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.fit() }
    }

    func show() {
        fit()
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }

    private func fit() {
        let size = host.fittingSize
        guard size != panel.frame.size else { return }
        let top = panel.isVisible ? NSPoint(x: panel.frame.minX, y: panel.frame.maxY) : startTopLeft(size: size)
        var frame = NSRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height)
        // Growing to a bigger size near a screen edge: slide back so it stays fully on screen.
        if let v = (NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, v.minY), v.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
    }

    /// Saved spot if it is still on a screen, else the top-right corner just below the menu bar.
    private func startTopLeft(size: NSSize) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: Self.originKey) {
            let p = NSPointFromString(s)
            let probe = NSRect(x: p.x, y: p.y - size.height, width: size.width, height: size.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(probe) }) { return p }
        }
        let v = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return NSPoint(x: v.maxX - size.width - 12, y: v.maxY - 8)
    }

    private func saveOrigin() {
        guard panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: panel.frame.minX, y: panel.frame.maxY)), forKey: Self.originKey)
    }
}

/// Mini version of the popup. Three sizes: Small (5-hour + this chat), Medium (+ weekly, live use, tip),
/// Large (bigger text, full tip, busiest chats today). Drag anywhere to move it.
struct FloatingBoxView: View {
    @ObservedObject var model: AppModel

    private var size: BoxSize { model.boxSize }
    private var big: Bool { size == .large }
    private var body1: Font { .system(size: big ? 15 : size == .small ? 12 : 13) }
    private var small1: Font { .system(size: big ? 13 : 11) }

    var body: some View {
        VStack(alignment: .leading, spacing: big ? 12 : 10) {
            header
            if let l = model.limits, l.fiveHour != nil || l.sevenDay != nil {
                if let w = l.fiveHour { limitRow("5-hour limit", w) }
                // Small shows one bar: the 5-hour one, or weekly when there's no 5-hour reading.
                if let w = l.sevenDay, size != .small || l.fiveHour == nil { limitRow("Weekly limit", w) }
            } else if size != .small {
                Text("No limit reading yet (turn on the status line).").font(small1).foregroundStyle(.secondary)
            }
            chatRow
            if size != .small {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Using now").font(small1).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Format.tokens(Int(model.burnPerMin))) tokens/min").font(small1.weight(.medium)).monospacedDigit()
                    }
                    Sparkline(values: model.sparkline).frame(height: big ? 36 : 24)
                }
                if let t = model.tip { TipCard(tip: t, compact: !big) }
            }
            if big, !model.topChats.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Busiest chats today").font(small1).foregroundStyle(.secondary)
                    ForEach(model.topChats.prefix(3), id: \.sessionId) { c in
                        HStack {
                            Text("\(Int((c.weight / max(model.todayWeight, 1) * 100).rounded()))%")
                                .monospacedDigit().frame(width: 40, alignment: .trailing)
                            Text(Format.project(c.project)).lineLimit(1)
                            Spacer()
                            Text(Format.ago(c.lastTime)).foregroundStyle(.secondary)
                        }.font(small1)
                    }
                }
            }
        }
        .padding(big ? 16 : 12)
        .frame(width: size.width)
        .background(WindowDragArea())
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.12)))
        .contextMenu { sizeButtons; Divider(); Button("Hide box") { model.showBox = false } }
    }

    // MARK: Pieces

    /// Title bar: grip + name (drag to move), size menu, hide button. Always visible so it's clear what the box is.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Text("TokenCoach").font(small1.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Menu { sizeButtons } label: {
                Text(size.label).font(small1)
            }
            .menuStyle(.borderlessButton).fixedSize().help("Box size")
            Button { model.showBox = false } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Hide (turn back on from the menu bar)")
        }
        .help("Drag to move")
    }

    @ViewBuilder private var sizeButtons: some View {
        ForEach(BoxSize.allCases) { s in
            Button { model.boxSize = s } label: {
                if s == size { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
            }
        }
    }

    private func limitRow(_ title: String, _ w: Limits.Window) -> some View {
        let color: Color = w.usedPercent >= 80 ? .red : w.usedPercent >= 50 ? .orange : .green
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(body1)
                Spacer()
                Text("\(Int(w.usedPercent.rounded()))% used").font(body1.weight(.semibold)).foregroundStyle(color).monospacedDigit()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.12))
                    Capsule().fill(color).frame(width: g.size.width * min(max(w.usedPercent, 0), 100) / 100)
                }
            }
            .frame(height: big ? 8 : 6)
            if size != .small {
                Text("Resets in \(Format.until(w.resetsAt))").font(small1).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var chatRow: some View {
        HStack(spacing: 6) {
            if let c = model.currentChat {
                Circle().fill(Level(chatSize: c.size).color).frame(width: 8, height: 8)
                Text("This chat: \(Format.tokens(c.size)) tokens").font(body1).monospacedDigit().lineLimit(1).fixedSize()
                Spacer(minLength: 6)
                Text(Format.project(c.project)).font(small1).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            } else {
                Text(model.loaded ? "No recent chat" : "Reading your chats…").font(body1).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .help("How much of this chat Claude re-reads with every message. Smaller is cheaper.")
    }
}

/// Lets you drag the borderless panel from anywhere that isn't a button.
private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
