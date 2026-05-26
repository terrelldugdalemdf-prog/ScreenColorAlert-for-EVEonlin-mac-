import SwiftUI
import AppKit

@main
struct ScreenColorAlertApp: App {
    @StateObject private var viewModel = ColorMonitorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .onAppear {
                    setAppIcon()
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }

    private func setAppIcon() {
        guard let resourcesURL = Bundle.main.resourceURL else { return }
        let iconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        guard let icon = NSImage(contentsOf: iconURL) else { return }
        NSApp.applicationIconImage = icon
        NSWorkspace.shared.setIcon(icon, forFile: Bundle.main.bundlePath, options: [])
    }
}
