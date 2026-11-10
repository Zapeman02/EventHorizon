import SwiftUI

enum DragMode: String, CaseIterable {
    case standard, move, copy

    var title: String {
        switch self {
        case .standard: "Default"
        case .move: "Move"
        case .copy: "Copy"
        }
    }

    var hint: String {
        switch self {
        case .standard: "Finder moves on the same disk and copies to other disks and apps"
        case .move: "Moves in Finder, still copies into apps like browsers"
        case .copy: "Always copies, the original stays put"
        }
    }

    var icon: String {
        switch self {
        case .standard: "cursorarrow.motionlines"
        case .move: "arrow.right.doc.on.clipboard"
        case .copy: "doc.on.doc"
        }
    }

    var operations: NSDragOperation {
        switch self {
        case .standard: [.copy, .move, .generic]
        case .move: [.move, .copy]
        case .copy: .copy
        }
    }

    static func movedFile(_ operation: NSDragOperation) -> Bool {
        operation.contains(.move) || operation.contains(.generic)
    }

    /// ⌥ and ⌘ override the chosen mode while held, matching Finder's own shortcuts.
    static func held(_ flags: NSEvent.ModifierFlags) -> DragMode? {
        if flags.contains(.option) { return .copy }
        if flags.contains(.command) { return .move }
        return nil
    }
}

@MainActor
final class NotchState: ObservableObject {
    struct Incoming: Identifiable {
        let id = UUID()
        let url: URL
        let offset: CGSize
    }

    nonisolated static let openSize = CGSize(width: 340, height: 124)
    nonisolated static let ear: CGFloat = 8
    nonisolated static let wing: CGFloat = 30
    nonisolated static let absorbDuration = 0.65
    nonisolated static let dragModeKey = "dragMode"

    @Published var isOpen = false
    @Published var isTargeted = false
    @Published var isDraggingOut = false
    @Published var dragMode = DragMode(rawValue: UserDefaults.standard.string(forKey: dragModeKey) ?? "") ?? .standard {
        didSet { UserDefaults.standard.set(dragMode.rawValue, forKey: Self.dragModeKey) }
    }
    @Published var heldMode: DragMode?
    var isMenuOpen = false
    @Published var dragProximity: Double?
    @Published private(set) var incoming: [Incoming] = []

    let shelf: Shelf
    let notchSize: CGSize

    init(shelf: Shelf, notchSize: CGSize) {
        self.shelf = shelf
        self.notchSize = notchSize
    }

    var activeMode: DragMode { heldMode ?? dragMode }

    var isAbsorbing: Bool { !incoming.isEmpty }

    var showsVortex: Bool { (isTargeted && !isDraggingOut) || isAbsorbing }

    var closedSize: CGSize {
        let wings = shelf.items.isEmpty ? 0 : Self.wing * 2
        return CGSize(width: notchSize.width + Self.ear * 2 + wings, height: notchSize.height)
    }

    var size: CGSize { isOpen ? Self.openSize : closedSize }

    var holeCenter: CGPoint {
        CGPoint(x: Self.openSize.width / 2, y: notchSize.height + (Self.openSize.height - notchSize.height) / 2)
    }

    func absorb(_ urls: [URL], from point: CGPoint) {
        guard !urls.isEmpty else { return }
        let offset = CGSize(width: point.x - holeCenter.x, height: point.y - holeCenter.y)
        let batch = urls.enumerated().map { index, url in
            Incoming(url: url, offset: CGSize(width: offset.width + CGFloat(index) * 14, height: offset.height))
        }
        incoming.append(contentsOf: batch)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.absorbDuration) { [weak self] in
            guard let self else { return }
            let ids = Set(batch.map(\.id))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                self.incoming.removeAll { ids.contains($0.id) }
                self.shelf.add(urls)
            }
        }
    }
}
