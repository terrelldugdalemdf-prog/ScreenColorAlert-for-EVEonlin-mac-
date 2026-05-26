import Foundation

final class ConfigPersistenceService {
    static let shared = ConfigPersistenceService()

    private var configURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ScreenColorAlert")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("config.json")
    }

    func save(_ config: MonitorConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    func load() -> MonitorConfig? {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(MonitorConfig.self, from: data) else { return nil }
        return config
    }
}
