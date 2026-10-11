import AppKit
import SwiftUI

/// Click-through glow that follows the cursor while a file is being dragged.
@MainActor
final class CursorGlow {
    private static let size: CGFloat = 180
    private let panel = NotchPanel()
    private let hostingView = NSHostingView(rootView: CursorGlowView(intensity: 0))

    init() {
        panel.ignoresMouseEvents = true
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setContentSize(NSSize(width: Self.size, height: Self.size))
    }

    func show(at point: NSPoint, intensity: Double) {
        hostingView.rootView = CursorGlowView(intensity: intensity)
        panel.setFrameOrigin(NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2))
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct CursorGlowView: View {
    var intensity: Double

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Palette.flare.opacity(0.35 + 0.45 * intensity),
                                          Palette.ember.opacity(0.2 + 0.3 * intensity), .clear],
                                 center: .center, startRadius: 4, endRadius: 45 + 40 * intensity))
            .blur(radius: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
