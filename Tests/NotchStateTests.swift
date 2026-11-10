import Foundation
import Testing
@testable import EventHorizon

/// Serialized: some tests share the saved drag mode in UserDefaults.
@MainActor
@Suite(.serialized)
struct NotchStateTests {
    private let notch = CGSize(width: 200, height: 32)
    private let file = URL(fileURLWithPath: "/tmp/a.pdf")

    @Test func closedNotchGrowsWingsWhenShelfHasItems() {
        let state = NotchState(shelf: Shelf(), notchSize: notch)
        #expect(state.closedSize.width == 200 + NotchState.ear * 2)
        state.shelf.add([file])
        #expect(state.closedSize.width == 200 + NotchState.ear * 2 + NotchState.wing * 2)
    }

    @Test func sizeFollowsOpenState() {
        let state = NotchState(shelf: Shelf(), notchSize: notch)
        #expect(state.size == state.closedSize)
        state.isOpen = true
        #expect(state.size == NotchState.openSize)
    }

    @Test func heldModeOverridesChosenMode() {
        UserDefaults.standard.removeObject(forKey: NotchState.dragModeKey)
        let state = NotchState(shelf: Shelf(), notchSize: notch)
        #expect(state.activeMode == .standard)
        state.dragMode = .move
        state.heldMode = .copy
        #expect(state.activeMode == .copy)
        state.heldMode = nil
        #expect(state.activeMode == .move)
    }

    @Test func dragModeIsRemembered() {
        NotchState(shelf: Shelf(), notchSize: notch).dragMode = .copy
        #expect(NotchState(shelf: Shelf(), notchSize: notch).dragMode == .copy)
        UserDefaults.standard.removeObject(forKey: NotchState.dragModeKey)
    }

    @Test func vortexHiddenWhileDraggingOut() {
        let state = NotchState(shelf: Shelf(), notchSize: notch)
        state.isTargeted = true
        #expect(state.showsVortex)
        state.isDraggingOut = true
        #expect(!state.showsVortex)
    }

    @Test func absorbAddsFilesToShelfAfterAnimation() async throws {
        let state = NotchState(shelf: Shelf(), notchSize: notch)
        state.absorb([file], from: .zero)
        #expect(state.isAbsorbing)
        #expect(state.shelf.items.isEmpty)
        try await Task.sleep(for: .seconds(NotchState.absorbDuration + 0.3))
        #expect(!state.isAbsorbing)
        #expect(state.shelf.items.map(\.urls) == [[file]])
    }
}
