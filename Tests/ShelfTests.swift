import Foundation
import Testing
@testable import EventHorizon

@MainActor
struct ShelfTests {
    private let a = URL(fileURLWithPath: "/tmp/a.pdf")
    private let b = URL(fileURLWithPath: "/tmp/b.pdf")

    @Test func filesDroppedTogetherBecomeOneItem() {
        let shelf = Shelf()
        shelf.add([a, b])
        #expect(shelf.items.count == 1)
        #expect(shelf.items[0].urls == [a, b])
    }

    @Test func ignoresFilesAlreadyOnShelf() {
        let shelf = Shelf()
        shelf.add([a])
        shelf.add([a, b])
        #expect(shelf.items.map(\.urls) == [[a], [b]])
    }

    @Test func ignoresDropWithOnlyDuplicates() {
        let shelf = Shelf()
        shelf.add([a])
        shelf.add([a])
        #expect(shelf.items.count == 1)
    }

    @Test func ignoresEmptyDrop() {
        let shelf = Shelf()
        shelf.add([])
        #expect(shelf.items.isEmpty)
    }

    @Test func removesOnlyGivenItem() {
        let shelf = Shelf()
        shelf.add([a])
        shelf.add([b])
        shelf.remove(shelf.items[0])
        #expect(shelf.items.map(\.urls) == [[b]])
    }

    @Test func clearEmptiesShelf() {
        let shelf = Shelf()
        shelf.add([a])
        shelf.add([b])
        shelf.clear()
        #expect(shelf.items.isEmpty)
    }

    @Test func titleIsFileNameOrCount() {
        #expect(ShelfItem(urls: [a]).title == "a.pdf")
        #expect(ShelfItem(urls: [a, b]).title == "2 files")
    }
}
