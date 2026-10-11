import Foundation

/// One drop: files dropped together stay together and are dragged out together.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let urls: [URL]

    var title: String { urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files" }
}

@MainActor
final class Shelf: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    func add(_ urls: [URL]) {
        let new = urls.filter { url in !items.contains { $0.urls.contains(url) } }
        guard !new.isEmpty else { return }
        items.append(ShelfItem(urls: new))
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0 == item }
    }

    func clear() {
        items.removeAll()
    }
}
