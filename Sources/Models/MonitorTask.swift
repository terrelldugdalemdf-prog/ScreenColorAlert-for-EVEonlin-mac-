import SwiftUI
import CoreGraphics

enum ColorMatchStrategy: String, Codable, CaseIterable {
    case perChannel = "逐通道"
    case euclidean = "欧几里得"
}

struct MonitorTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "默认任务"
    var selectedRect: CGRect?
    var targetColorR: Double = 55.0 / 255.0
    var targetColorG: Double = 13.0 / 255.0
    var targetColorB: Double = 9.0 / 255.0
    var colorTolerance: Double = 0.08
    var sampleStep: Int = 4
    var minMatchRatio: Double = 0.05
    var isEnabled: Bool = true
    var matchStrategy: ColorMatchStrategy = .perChannel

    var targetColor: Color {
        get {
            Color(red: targetColorR, green: targetColorG, blue: targetColorB)
        }
        set {
            guard let nsColor = NSColor(newValue).usingColorSpace(.deviceRGB) else { return }
            targetColorR = Double(nsColor.redComponent)
            targetColorG = Double(nsColor.greenComponent)
            targetColorB = Double(nsColor.blueComponent)
        }
    }

    var regionDescription: String {
        guard let rect = selectedRect else { return "未选择" }
        return "x:\(Int(rect.origin.x)) y:\(Int(rect.origin.y)) \(Int(rect.width))×\(Int(rect.height))"
    }
}
