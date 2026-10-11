import SwiftUI

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

    @Published var isOpen = false
    @Published var isTargeted = false
    @Published var isDraggingOut = false
    @Published var dragProximity: Double?
    @Published private(set) var incoming: [Incoming] = []

    let shelf: Shelf
    let notchSize: CGSize

    init(shelf: Shelf, notchSize: CGSize) {
        self.shelf = shelf
        self.notchSize = notchSize
    }

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
