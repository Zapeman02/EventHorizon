import Testing
@testable import EventHorizon

struct UpdateCheckerTests {
    @Test func newerTagIsNewer() {
        #expect(UpdateChecker.isNewer("v1.1", than: "1.0"))
        #expect(UpdateChecker.isNewer("v2.0", than: "1.9"))
        #expect(UpdateChecker.isNewer("v1.0.1", than: "1.0"))
    }

    @Test func comparesNumbersNotText() {
        #expect(UpdateChecker.isNewer("v1.10", than: "1.9"))
    }

    @Test func sameOrOlderIsNotNewer() {
        #expect(!UpdateChecker.isNewer("v1.0", than: "1.0"))
        #expect(!UpdateChecker.isNewer("1.0.0", than: "1.0"))
        #expect(!UpdateChecker.isNewer("v0.9", than: "1.0"))
    }
}
