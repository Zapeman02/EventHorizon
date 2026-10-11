import AppKit
import SwiftUI

/// AppKit drag source: SwiftUI's onDrag has no end callback and doesn't start reliably in a non-key panel.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    let onHover: (Bool) -> Void
    let onDragChanged: (Bool) -> Void
    let onRemove: () -> Void

    func makeNSView(context: Context) -> FileDragView { FileDragView() }

    func updateNSView(_ view: FileDragView, context: Context) {
        view.urls = urls
        view.onHover = onHover
        view.onDragChanged = onDragChanged
        view.onRemove = onRemove
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onHover: (Bool) -> Void = { _ in }
    var onDragChanged: (Bool) -> Void = { _ in }
    var onRemove: () -> Void = {}
    private var isPressed = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }

    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) { isPressed = false }

    override func mouseDragged(with event: NSEvent) {
        guard isPressed, !urls.isEmpty else { return }
        isPressed = false
        let iconSize: CGFloat = 44
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 4)) * 4
            let frame = NSRect(x: bounds.midX - iconSize / 2 + offset, y: bounds.maxY - iconSize - offset,
                               width: iconSize, height: iconSize)
            item.setDraggingFrame(frame, contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        onDragChanged(true)
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragChanged(false)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show in Finder", action: #selector(showInFinder), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Remove", action: #selector(remove), keyEquivalent: "").target = self
        return menu
    }

    @objc private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc private func remove() { onRemove() }
}
