import AppKit
import SwiftUI

/// AppKit drag source: SwiftUI's onDrag has no end callback and doesn't start reliably in a non-key panel.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    let mode: DragMode
    let onHover: (Bool) -> Void
    let onDragChanged: (Bool) -> Void
    let onRemove: () -> Void

    func makeNSView(context: Context) -> FileDragView { FileDragView() }

    func updateNSView(_ view: FileDragView, context: Context) {
        view.urls = urls
        view.mode = mode
        view.onHover = onHover
        view.onDragChanged = onDragChanged
        view.onRemove = onRemove
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var mode = DragMode.standard
    var onHover: (Bool) -> Void = { _ in }
    var onDragChanged: (Bool) -> Void = { _ in }
    var onRemove: () -> Void = {}
    private var isPressed = false
    private var shownMode = DragMode.standard

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
            item.setDraggingFrame(frame, contents: dragImage(for: url, mode: effectiveMode))
            return item
        }
        shownMode = effectiveMode
        onDragChanged(true)
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? effectiveMode.operations : []
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let current = effectiveMode
        guard current != shownMode else { return }
        shownMode = current
        session.enumerateDraggingItems(for: nil, classes: [NSURL.self], searchOptions: [:]) { item, _, _ in
            guard let url = item.item as? URL else { return }
            item.setDraggingFrame(item.draggingFrame, contents: self.dragImage(for: url, mode: current))
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragChanged(false)
        if DragMode.movedFile(operation) { onRemove() }
    }

    private var effectiveMode: DragMode { DragMode.held(NSEvent.modifierFlags) ?? mode }

    /// Badge sits bottom-left so it doesn't collide with the system's +/- badge in the bottom-right.
    private func dragImage(for url: URL, mode: DragMode) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        guard mode != .standard else { return icon }
        let size: CGFloat = 44
        let badge: CGFloat = 18
        let symbol = NSImage(systemSymbolName: mode.icon, accessibilityDescription: mode.title)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.white])))
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            icon.draw(in: rect)
            let circle = NSRect(x: 0, y: 0, width: badge, height: badge)
            NSColor(Palette.ember).setFill()
            NSBezierPath(ovalIn: circle).fill()
            if let symbol {
                let origin = NSPoint(x: circle.midX - symbol.size.width / 2, y: circle.midY - symbol.size.height / 2)
                symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
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
