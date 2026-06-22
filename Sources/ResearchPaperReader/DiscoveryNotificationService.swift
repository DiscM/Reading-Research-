import Foundation
import UserNotifications

enum DiscoveryNotificationService {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func post(alertName: String, matches: [DiscoveryPaper]) async {
        guard !matches.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = matches.count == 1 ? "New research match" : "\(matches.count) new research matches"
        content.subtitle = alertName
        content.body = matches.prefix(3).map(\.title).joined(separator: " · ")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "research-alert-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
