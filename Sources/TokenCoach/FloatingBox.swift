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
        panel.setFrame(NSRect(x: top.x, y: top.y - size.height, width: size.width, height: size.height), display: true)
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

/// Mini version of the popup: 5-hour %, this chat's size, live sparkline, the one tip.
struct FloatingBoxView: View {
    @ObservedObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let w = model.limits?.fiveHour {
                LimitBar(title: "5-hour", window: w)
            }
            HStack(spacing: 6) {
                if let c = model.currentChat {
                    Circle().fill(Level(chatSize: c.size).color).frame(width: 8, height: 8)
                    Text("Chat \(Format.tokens(c.size))").monospacedDigit()
                    Spacer()
                    Text(Format.project(c.project)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(model.loaded ? "No recent chat" : "Reading your chats…").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .font(.callout)
            HStack(spacing: 6) {
                Sparkline(values: model.sparkline).frame(height: 20)
                Text("\(Format.tokens(Int(model.burnPerMin)))/min").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            if let t = model.tip { TipCard(tip: t, compact: true) }
        }
        .padding(12)
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { model.showBox = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Hide (turn back on from the menu bar)")
                .padding(4)
            }
        }
        .onHover { hovering = $0 }
    }
}
