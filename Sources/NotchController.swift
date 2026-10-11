import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchController {
    private static let glowMargin: CGFloat = 50
    private static let proximityRange: CGFloat = 700
    private static let hoverPadding: CGFloat = 12
    private static let openAnimation = Animation.spring(response: 0.38, dampingFraction: 0.78)

    private let screen: NSScreen
    private let state: NotchState
    private let panel = NotchPanel()
    private let cursorGlow = CursorGlow()
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var dragTimer: Timer?
    private var hoverTimer: Timer?
    private var dragChangeCount = 0

    init(shelf: Shelf) {
        screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main!
        state = NotchState(shelf: shelf, notchSize: Self.notchSize(on: screen))
        let hostingView = NotchHostingView(rootView: NotchView(state: state, shelf: shelf))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        resizePanel(open: false, glowing: false)
        panel.orderFrontRegardless()
        observeState()
        installMouseMonitors()
    }

    private static func notchSize(on screen: NSScreen) -> CGSize {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return CGSize(width: 185, height: 32)
        }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }

    private func observeState() {
        state.shelf.$items.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateHoverPolling() }
        }.store(in: &cancellables)

        state.$isOpen.dropFirst().sink { [weak self] open in
            guard let self else { return }
            if open {
                resizePanel(open: true, glowing: state.dragProximity != nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !self.state.isOpen { self.resizePanel(open: false, glowing: self.state.dragProximity != nil) }
                }
            }
        }.store(in: &cancellables)

        state.$isTargeted.dropFirst().sink { [weak self] targeted in
            guard let self else { return }
            if targeted { setOpen(true) } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.trackMouse() } }
        }.store(in: &cancellables)

        state.$isDraggingOut.dropFirst().sink { [weak self] dragging in
            guard let self, !dragging else { return }
            DispatchQueue.main.async { self.trackMouse() }
        }.store(in: &cancellables)

        state.$incoming.dropFirst().sink { [weak self] incoming in
            guard let self, incoming.isEmpty else { return }
            DispatchQueue.main.async { self.trackMouse() }
        }.store(in: &cancellables)
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .leftMouseDown { watchForFileDrag() }
        trackMouse()
    }

    private func trackMouse() {
        let mouse = NSEvent.mouseLocation
        if state.isOpen {
            let busy = state.isTargeted || state.isAbsorbing || state.isDraggingOut
            if !busy && !shapeRect(open: true).insetBy(dx: -8, dy: -8).contains(mouse) { setOpen(false) }
        } else if !state.shelf.items.isEmpty && NSEvent.pressedMouseButtons == 0 && hoverRect.contains(mouse) {
            setOpen(true)
        }
    }

    /// Global monitors miss events aimed at our own panel, so poll the cursor while there is something to show.
    private func updateHoverPolling() {
        let needed = !state.shelf.items.isEmpty || state.isOpen
        if needed, hoverTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackMouse() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        } else if !needed {
            hoverTimer?.invalidate()
            hoverTimer = nil
        }
    }

    private func setOpen(_ open: Bool) {
        guard state.isOpen != open else { return }
        withAnimation(Self.openAnimation) { state.isOpen = open }
        updateHoverPolling()
    }

    /// The closed notch plus a margin beside and below it, reaching up past the screen edge.
    private var hoverRect: NSRect {
        let shape = shapeRect(open: false)
        return NSRect(x: shape.minX - Self.hoverPadding, y: shape.minY - Self.hoverPadding,
                      width: shape.width + Self.hoverPadding * 2, height: shape.height + Self.hoverPadding + 4)
    }

    // MARK: - File drag glow

    /// Polls while the button is held: drags from other apps only reveal themselves via the drag pasteboard.
    private func watchForFileDrag() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        dragTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFileDrag() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dragTimer = timer
    }

    private func updateFileDrag() {
        guard NSEvent.pressedMouseButtons & 1 != 0 else { endFileDrag(); return }

        if state.dragProximity == nil {
            let pasteboard = NSPasteboard(name: .drag)
            guard !state.isDraggingOut, pasteboard.changeCount != dragChangeCount,
                  pasteboard.types?.contains(.fileURL) == true else { return }
            resizePanel(open: state.isOpen, glowing: true)
        }

        let mouse = NSEvent.mouseLocation
        let notch = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - state.notchSize.height / 2)
        let proximity = Double(max(0, 1 - hypot(mouse.x - notch.x, mouse.y - notch.y) / Self.proximityRange))
        state.dragProximity = proximity
        cursorGlow.show(at: mouse, intensity: proximity)
    }

    private func endFileDrag() {
        dragTimer?.invalidate()
        dragTimer = nil
        guard state.dragProximity != nil else { return }
        cursorGlow.hide()
        withAnimation(.easeOut(duration: 0.3)) { state.dragProximity = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if self.state.dragProximity == nil { self.resizePanel(open: self.state.isOpen, glowing: false) }
        }
    }

    // MARK: - Geometry

    private func shapeRect(open: Bool) -> NSRect {
        let size = open ? NotchState.openSize : state.closedSize
        let frame = screen.frame
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
    }

    private func resizePanel(open: Bool, glowing: Bool) {
        let shape = shapeRect(open: open)
        let margin = open || glowing ? Self.glowMargin : 0
        panel.setFrame(shape.insetBy(dx: -margin, dy: 0).offsetBy(dx: 0, dy: -margin).union(shape), display: true)
    }
}
