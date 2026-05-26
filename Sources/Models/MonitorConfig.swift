import Foundation

struct MonitorConfig: Codable {
    var tasks: [MonitorTask] = [MonitorTask()]
    var alertVolume: Double = 0.8
    var customAudioURL: URL?
    var customAudioName: String?
    var notificationsEnabled: Bool = true
    var minConsecutiveMatches: Int = 2
    var alertCooldownSeconds: Double = 1.5

    var activeTasks: [MonitorTask] {
        tasks.filter { $0.isEnabled && $0.selectedRect != nil }
    }
}

enum MonitorState {
    case idle
    case selecting
    case monitoring
}
