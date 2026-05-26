import SwiftUI
import AppKit
import Combine

struct TaskState {
    var isDetected: Bool = false
    var consecutiveMatchCount: Int = 0
    var previewImage: NSImage?
}

@MainActor
final class ColorMonitorViewModel: ObservableObject {
    @Published var config: MonitorConfig = {
        ConfigPersistenceService.shared.load() ?? MonitorConfig()
    }()
    @Published var state: MonitorState = .idle
    @Published var statusMessage = "就绪"
    @Published var taskStates: [UUID: TaskState] = [:]
    @Published var selectedTaskIndex: Int = 0

    private let captureService = ScreenCaptureService()
    private let detectionService = ColorDetectionService()
    private let audioService = AudioAlertService()

    private var monitorTimer: AnyCancellable?
    private var selectionOverlay: NSWindow?
    private var taskOverlayWindows: [UUID: NSWindow] = [:]
    private var configSink: AnyCancellable?
    private var lastAlertTime: Date = .distantPast
    private var cancellables = Set<AnyCancellable>()

    init() {
        configSink = $config
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { ConfigPersistenceService.shared.save($0) }

        // 仅在用户主动切换通知开关时才请求权限
        $config
            .map(\.notificationsEnabled)
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { _ in NotificationService.shared.requestPermission() }
            .store(in: &cancellables)

        LogService.shared.log(.info, "ScreenColorAlert 启动")
        ensureDefaultTask()
    }

    private func ensureDefaultTask() {
        if config.tasks.isEmpty {
            config.tasks.append(MonitorTask())
        }
    }

    // MARK: - Task Management

    func addTask() {
        let task = MonitorTask(name: "任务 \(config.tasks.count + 1)")
        config.tasks.append(task)
        selectedTaskIndex = config.tasks.count - 1
        LogService.shared.log(.info, "新增监测任务: \(task.name)")
    }

    func removeTask(_ task: MonitorTask) {
        guard config.tasks.count > 1 else { return }
        config.tasks.removeAll { $0.id == task.id }
        taskOverlayWindows[task.id]?.orderOut(nil)
        taskOverlayWindows.removeValue(forKey: task.id)
        taskStates.removeValue(forKey: task.id)
        if selectedTaskIndex >= config.tasks.count {
            selectedTaskIndex = max(0, config.tasks.count - 1)
        }
        LogService.shared.log(.info, "删除监测任务: \(task.name)")
    }

    // MARK: - Region Selection

    func showRegionSelector(for task: MonitorTask) {
        guard let screen = NSScreen.main else { return }

        state = .selecting
        hideAllOverlays()

        let screenshot = captureService.captureFullScreen()

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false

        let taskId = task.id
        let selectionView = RegionSelectionView(frame: screen.frame)
        selectionView.backgroundImage = screenshot
        selectionView.onSelectionComplete = { [weak self] rect in
            guard let self else { return }
            if let idx = self.config.tasks.firstIndex(where: { $0.id == taskId }) {
                self.config.tasks[idx].selectedRect = rect
            }
            self.state = .idle
            self.statusMessage = "已选择区域: (\(Int(rect.origin.x)), \(Int(rect.origin.y))) \(Int(rect.width))×\(Int(rect.height))"
            self.selectionOverlay?.close()
            self.selectionOverlay = nil
            LogService.shared.log(.info, "任务 \(task.name) 区域已选择")
        }
        selectionView.onSelectionCancelled = { [weak self] in
            self?.state = .idle
            self?.statusMessage = "已取消选择"
            self?.selectionOverlay?.close()
            self?.selectionOverlay = nil
        }

        window.contentView = selectionView
        window.makeKeyAndOrderFront(nil)
        selectionOverlay = window
    }

    // MARK: - Monitor Overlays

    private func showTaskOverlay(for task: MonitorTask) {
        guard let rect = task.selectedRect, rect.width > 0, rect.height > 0 else { return }

        hideTaskOverlay(for: task.id)

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 30, height: 30)

        let overlayView = MonitorOverlayView(frame: NSRect(origin: .zero, size: rect.size))
        overlayView.autoresizingMask = [.width, .height]
        window.contentView = overlayView

        window.makeKeyAndOrderFront(nil)
        taskOverlayWindows[task.id] = window
    }

    private func hideTaskOverlay(for taskId: UUID) {
        taskOverlayWindows[taskId]?.orderOut(nil)
        taskOverlayWindows.removeValue(forKey: taskId)
    }

    private func hideAllOverlays() {
        for (_, window) in taskOverlayWindows {
            window.orderOut(nil)
        }
        taskOverlayWindows.removeAll()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        let active = config.activeTasks
        guard !active.isEmpty else {
            statusMessage = "请先为至少一个任务选择监测区域"
            return
        }
        state = .monitoring
        statusMessage = "监测中（\(active.count) 个任务）..."
        taskStates.removeAll()

        for task in active {
            taskStates[task.id] = TaskState()
            showTaskOverlay(for: task)
        }

        lastAlertTime = .distantPast
        LogService.shared.log(.info, "开始监测，活跃任务: \(active.count)")

        // Combine 管道：定时截图 → 检测 → 警报
        monitorTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performCaptureCycle()
            }
        cancellables.insert(monitorTimer!)
    }

    func pickAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.config.customAudioURL = url
            self?.config.customAudioName = url.lastPathComponent
        }
    }

    func clearCustomAudio() {
        config.customAudioURL = nil
        config.customAudioName = nil
    }

    func testAlert() {
        syncAudioConfig()
        audioService.playAlert()
    }

    private func syncAudioConfig() {
        audioService.volume = Float(config.alertVolume)
        audioService.customAudioURL = config.customAudioURL
    }

    func stopMonitoring() {
        monitorTimer?.cancel()
        monitorTimer = nil
        hideAllOverlays()
        state = .idle
        statusMessage = "已停止监测"
        taskStates.removeAll()
        LogService.shared.log(.info, "停止监测")
    }

    // MARK: - Capture Cycle

    private func performCaptureCycle() {
        let activeTasks = config.activeTasks
        var anyDetected = false

        for i in 0..<activeTasks.count {
            let task = activeTasks[i]

            // 从浮窗读取实时位置
            if let overlay = taskOverlayWindows[task.id] {
                if let idx = config.tasks.firstIndex(where: { $0.id == task.id }) {
                    config.tasks[idx].selectedRect = overlay.frame
                }
            }

            guard let rect = task.selectedRect, rect.width > 0, rect.height > 0 else { continue }

            guard let image = captureService.capture(rect: rect) else {
                if i == 0 {
                    statusMessage = "截取屏幕失败，请检查屏幕录制权限"
                }
                continue
            }

            // 更新预览
            let preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            taskStates[task.id]?.previewImage = preview

            let found = detectionService.checkForColor(
                in: image,
                targetColor: NSColor(task.targetColor),
                tolerance: task.colorTolerance,
                sampleStep: task.sampleStep,
                minMatchRatio: task.minMatchRatio,
                strategy: task.matchStrategy
            )

            if found {
                var ts = taskStates[task.id] ?? TaskState()
                ts.consecutiveMatchCount += 1
                let required = max(config.minConsecutiveMatches, 1)
                if ts.consecutiveMatchCount >= required {
                    ts.isDetected = true
                    anyDetected = true
                }
                taskStates[task.id] = ts
            } else {
                var ts = taskStates[task.id] ?? TaskState()
                ts.consecutiveMatchCount = 0
                ts.isDetected = false
                taskStates[task.id] = ts
            }
        }

        if anyDetected {
            let now = Date()
            let cooldownPassed = now.timeIntervalSince(lastAlertTime) >= config.alertCooldownSeconds

            let detectedNames = activeTasks
                .filter { taskStates[$0.id]?.isDetected == true }
                .map(\.name)
                .joined(separator: ", ")

            statusMessage = "检测到目标颜色！(\(detectedNames))"

            if cooldownPassed {
                lastAlertTime = now
                syncAudioConfig()
                audioService.playAlert()
                if config.notificationsEnabled {
                    NotificationService.shared.sendColorDetectedAlert()
                }
                LogService.shared.log(.detection, "检测到颜色，触发警报 - 任务: \(detectedNames)")
            }
        } else {
            let matchingTasks = activeTasks.filter {
                (taskStates[$0.id]?.consecutiveMatchCount ?? 0) > 0
            }
            if matchingTasks.isEmpty {
                statusMessage = "监测中（\(activeTasks.count) 个任务）..."
            } else {
                let info = matchingTasks.map { t in
                    let count = taskStates[t.id]?.consecutiveMatchCount ?? 0
                    return "\(t.name): \(count)/\(max(config.minConsecutiveMatches, 1))"
                }.joined(separator: " ")
                statusMessage = "匹配中... \(info)"
            }
            audioService.stopAlert()
        }
    }

    // MARK: - View Helpers

    var hasAnyValidRegion: Bool {
        !config.activeTasks.isEmpty
    }
}
