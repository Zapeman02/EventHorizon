import AppKit
import Testing
@testable import EventHorizon

struct DragModeTests {
    @Test func defaultLetsDestinationDecide() {
        #expect(DragMode.standard.operations == [.copy, .move, .generic])
    }

    @Test func moveStillAllowsCopySoBrowsersAcceptIt() {
        #expect(DragMode.move.operations == [.move, .copy])
    }

    @Test func copyNeverMoves() {
        #expect(DragMode.copy.operations == .copy)
    }

    @Test func optionHeldMeansCopy() {
        #expect(DragMode.held(.option) == .copy)
    }

    @Test func commandHeldMeansMove() {
        #expect(DragMode.held(.command) == .move)
    }

    @Test func optionWinsOverCommand() {
        #expect(DragMode.held([.option, .command]) == .copy)
    }

    @Test func otherModifiersDoNotOverride() {
        #expect(DragMode.held([]) == nil)
        #expect(DragMode.held(.shift) == nil)
    }

    @Test func moveAndGenericCountAsMoved() {
        #expect(DragMode.movedFile(.move))
        #expect(DragMode.movedFile(.generic))
    }

    @Test func copyAndCancelledDragKeepItem() {
        #expect(!DragMode.movedFile(.copy))
        #expect(!DragMode.movedFile([]))
    }
}
