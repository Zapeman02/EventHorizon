import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController(shelf: Shelf())
        registerLoginItem()
    }

    private func registerLoginItem() {
        guard SMAppService.mainApp.status != .enabled else { return }
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("EventHorizon: login item registration failed: \(error)")
        }
    }
}
