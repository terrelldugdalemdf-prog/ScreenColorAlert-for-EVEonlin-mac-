import Foundation

enum LogLevel: String, Codable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case detection = "DETECT"
}

struct LogEntry: Identifiable, Codable {
    var id: UUID = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

final class LogService {
    static let shared = LogService()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500

    private var logURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ScreenColorAlert/Logs")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return dir.appendingPathComponent("screencolor_\(formatter.string(from: Date())).log")
    }

    private init() {}

    func log(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        entries.append(entry)

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }

        // 写入文件
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: entry.timestamp))] [\(level.rawValue)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path),
               let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logURL, options: .atomic)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }
}
