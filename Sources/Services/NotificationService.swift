import UserNotifications

final class NotificationService {
    static let shared = NotificationService()
    private var granted = false
    private var available = false

    private init() {
        available = Bundle.main.bundleIdentifier != nil
    }

    func requestPermission() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.granted = granted
            }
        }
    }

    func sendColorDetectedAlert() {
        guard available, granted else { return }
        let content = UNMutableNotificationContent()
        content.title = "ScreenColorAlert"
        content.body = "检测到目标颜色"
        content.sound = .default
        content.categoryIdentifier = "COLOR_DETECTED"

        let request = UNNotificationRequest(
            identifier: "color-detected-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
