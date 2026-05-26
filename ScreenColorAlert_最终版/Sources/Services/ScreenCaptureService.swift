import CoreGraphics
import AppKit

final class ScreenCaptureService {
    func capture(rect: CGRect) -> CGImage? {
        let quartzRect = convertToQuartzCoordinates(rect)
        return CGWindowListCreateImage(
            quartzRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }

    func captureFullScreen() -> CGImage? {
        guard let screen = NSScreen.main else { return nil }
        return capture(rect: screen.frame)
    }

    private func convertToQuartzCoordinates(_ rect: CGRect) -> CGRect {
        guard let screen = NSScreen.main else { return rect }
        let screenHeight = screen.frame.height
        let quartzY = screenHeight - rect.origin.y - rect.height
        return CGRect(
            x: rect.origin.x,
            y: quartzY,
            width: rect.width,
            height: rect.height
        )
    }
}
