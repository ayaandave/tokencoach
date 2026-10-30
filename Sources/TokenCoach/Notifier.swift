import Foundation
import UserNotifications
import TokenCoachCore

/// Sends a Mac notification for warning tips, once per warning (per chat, per 5-hour window).
/// Fired keys are kept for a day in UserDefaults, so restarting the app doesn't repeat them.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let defaults = UserDefaults.standard
    private let firedKey = "firedNotifications"
    private var center: UNUserNotificationCenter?

    override init() {
        super.init()
        // Notifications need a real .app bundle (scripts/make-app.sh). `swift run` has none, so skip them there.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center = c
    }

    func consider(_ tips: [Tip]) {
        guard let center else { return }
        var fired = (defaults.dictionary(forKey: firedKey) as? [String: Double]) ?? [:]
        let dayAgo = Date().addingTimeInterval(-24 * 3600).timeIntervalSince1970
        fired = fired.filter { $0.value > dayAgo }
        // Send only the most urgent new warning; mark the rest as seen too, so two rules crossing at once don't double-ping.
        let fresh = tips.filter { $0.notifyKey != nil && fired[$0.notifyKey!] == nil }
        for tip in fresh { fired[tip.notifyKey!] = Date().timeIntervalSince1970 }
        if let tip = fresh.first {
            let content = UNMutableNotificationContent()
            content.title = tip.title
            content.body = tip.text
            if tip.level == .alert { content.sound = .default }
            center.add(UNNotificationRequest(identifier: tip.notifyKey!, content: content, trigger: nil))
        }
        defaults.set(fired, forKey: firedKey)
    }

    // Show banners even if the popup is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
