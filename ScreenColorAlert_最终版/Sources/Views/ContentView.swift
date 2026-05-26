import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ColorMonitorViewModel
    @State private var flashOn = false

    private let flashTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            // 任务列表
            taskListSection

            Divider()

            // 全局警报设置
            globalSettingsSection

            Divider()

            // 操作区
            actionBarSection

            Divider()

            // 预览区
            if viewModel.state == .monitoring {
                previewSection
                Divider()
            }

            // 状态区
            statusSection
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 400)
    }

    // MARK: - Task List

    @ViewBuilder
    private var taskListSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("监测任务")
                    .font(.headline)
                Spacer()
                Button(action: viewModel.addTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .disabled(viewModel.state == .monitoring)
            }

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(viewModel.config.tasks.enumerated()), id: \.element.id) { index, task in
                        taskRow(index: index, task: task)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private func taskRow(index: Int, task: MonitorTask) -> some View {
        return VStack(spacing: 6) {
            HStack {
                Toggle("", isOn: Binding<Bool>(
                    get: { viewModel.config.tasks[safe: index]?.isEnabled ?? true },
                    set: { viewModel.config.tasks[safe: index]?.isEnabled = $0 }
                ))
                .labelsHidden()
                .disabled(viewModel.state == .monitoring)

                TextField("任务名", text: Binding<String>(
                    get: { viewModel.config.tasks[safe: index]?.name ?? "" },
                    set: { viewModel.config.tasks[safe: index]?.name = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .disabled(viewModel.state == .monitoring)

                Spacer()

                Text(task.regionDescription)
                    .font(.caption)
                    .foregroundColor(task.selectedRect != nil ? .secondary : .red)
                    .lineLimit(1)

                Button("选区") {
                    viewModel.showRegionSelector(for: task)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.state == .monitoring)

                if viewModel.config.tasks.count > 1 {
                    Button(action: { viewModel.removeTask(task) }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(viewModel.state == .monitoring)
                }
            }

            if viewModel.state == .monitoring, let ts = viewModel.taskStates[task.id] {
                HStack(spacing: 8) {
                    Circle()
                        .fill(ts.isDetected ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(ts.isDetected ? "检测中" : "正常")
                        .font(.caption2)
                        .foregroundColor(ts.isDetected ? .red : .green)
                    if ts.consecutiveMatchCount > 0 {
                        Text("连续: \(ts.consecutiveMatchCount)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.leading, 24)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(index == viewModel.selectedTaskIndex ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            viewModel.selectedTaskIndex = index
        }
    }

    // MARK: - Global Settings

    @ViewBuilder
    private var globalSettingsSection: some View {
        VStack(spacing: 10) {
            // 目标颜色
            HStack {
                Text("目标颜色")
                    .frame(width: 60, alignment: .leading)
                ColorPicker("", selection: Binding<Color>(
                    get: {
                        if let task = viewModel.config.tasks[safe: viewModel.selectedTaskIndex] {
                            return task.targetColor
                        }
                        return .red
                    },
                    set: { newColor in
                        viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.targetColor = newColor
                    }
                ))
                .labelsHidden()
                Spacer()
            }

            // 颜色容差
            HStack {
                Text("颜色容差")
                    .frame(width: 60, alignment: .leading)
                Slider(value: Binding<Double>(
                    get: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.colorTolerance ?? 0.08 },
                    set: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.colorTolerance = $0 }
                ), in: 0.01...0.50)
                Text(String(format: "%.2f", viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.colorTolerance ?? 0))
                    .frame(width: 36, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }

            // 匹配占比 & 采样
            HStack {
                Text("匹配占比")
                    .frame(width: 60, alignment: .leading)
                Slider(value: Binding<Double>(
                    get: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.minMatchRatio ?? 0.05 },
                    set: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.minMatchRatio = $0 }
                ), in: 0.01...0.30)
                Text("\(Int((viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.minMatchRatio ?? 0.05) * 100))%")
                    .frame(width: 36, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("采样密度")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: Binding<Int>(
                    get: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.sampleStep ?? 4 },
                    set: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.sampleStep = $0 }
                )) {
                    Text("高").tag(1)
                    Text("中").tag(4)
                    Text("低").tag(8)
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Spacer()
            }

            HStack {
                Text("匹配策略")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: Binding<ColorMatchStrategy>(
                    get: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.matchStrategy ?? .perChannel },
                    set: { viewModel.config.tasks[safe: viewModel.selectedTaskIndex]?.matchStrategy = $0 }
                )) {
                    ForEach(ColorMatchStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.rawValue).tag(strategy)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Spacer()
            }

            Divider()

            // 通知 & 警报策略
            HStack {
                Text("系统通知")
                    .frame(width: 60, alignment: .leading)
                Toggle("", isOn: $viewModel.config.notificationsEnabled)
                    .labelsHidden()
                Spacer()
            }

            HStack {
                Text("连续匹配")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: $viewModel.config.minConsecutiveMatches) {
                    Text("1次").tag(1)
                    Text("2次").tag(2)
                    Text("3次").tag(3)
                    Text("5次").tag(5)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Spacer()
            }

            HStack {
                Text("警报冷却")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: Binding<Double>(
                    get: { viewModel.config.alertCooldownSeconds },
                    set: { viewModel.config.alertCooldownSeconds = $0 }
                )) {
                    Text("0.5s").tag(0.5)
                    Text("1.5s").tag(1.5)
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                Spacer()
            }

            Divider()

            // 音量 & 音频
            HStack {
                Text("警报音量")
                    .frame(width: 60, alignment: .leading)
                Slider(value: $viewModel.config.alertVolume, in: 0.0...1.0)
                Text("\(Int(viewModel.config.alertVolume * 100))%")
                    .frame(width: 36, alignment: .trailing)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                Text("音频文件")
                    .frame(width: 60, alignment: .leading)
                Text(viewModel.config.customAudioName ?? "默认嘟声")
                    .foregroundColor(viewModel.config.customAudioURL == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("选择...") {
                    viewModel.pickAudioFile()
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.state == .monitoring)
                if viewModel.config.customAudioURL != nil {
                    Button(action: viewModel.clearCustomAudio) {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(viewModel.state == .monitoring)
                }
            }
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBarSection: some View {
        HStack(spacing: 12) {
            if viewModel.state == .monitoring {
                Button(action: viewModel.stopMonitoring) {
                    Label("停止监测", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: viewModel.startMonitoring) {
                    Label("开始监测", systemImage: "play.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasAnyValidRegion)
            }

            Button(action: viewModel.testAlert) {
                Label("测试警报", systemImage: "speaker.wave.2")
            }
            .disabled(viewModel.state == .monitoring)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        VStack(spacing: 4) {
            Text("实时截图")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(viewModel.config.activeTasks, id: \.id) { task in
                        if let preview = viewModel.taskStates[task.id]?.previewImage {
                            VStack(spacing: 2) {
                                Image(nsImage: preview)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                                Text(task.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if viewModel.taskStates.values.allSatisfy({ $0.previewImage == nil }) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 100, height: 70)
                            .overlay(
                                Text("等待截图...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 28, height: 28)
                    .blur(radius: 6)
                    .opacity(flashOn ? 0.6 : 0)
            }
            .opacity(indicatorOpacity)
            .onReceive(flashTimer) { _ in
                let anyDetected = viewModel.taskStates.values.contains(where: { $0.isDetected })
                if viewModel.state == .monitoring, anyDetected {
                    flashOn.toggle()
                } else {
                    flashOn = false
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Computed

    private var indicatorColor: Color {
        switch viewModel.state {
        case .monitoring:
            let anyDetected = viewModel.taskStates.values.contains(where: { $0.isDetected })
            return anyDetected ? .red : .green
        case .idle:
            return .gray
        case .selecting:
            return .blue
        }
    }

    private var indicatorOpacity: Double {
        if viewModel.state == .monitoring,
           viewModel.taskStates.values.contains(where: { $0.isDetected }) {
            return flashOn ? 1.0 : 0.2
        }
        return 1.0
    }

    private var statusTitle: String {
        switch viewModel.state {
        case .idle: return "就绪"
        case .selecting: return "框选中..."
        case .monitoring:
            let anyDetected = viewModel.taskStates.values.contains(where: { $0.isDetected })
            return anyDetected ? "警报" : "监测中"
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        get {
            indices.contains(index) ? self[index] : nil
        }
        set {
            guard let newValue, indices.contains(index) else { return }
            self[index] = newValue
        }
    }
}
