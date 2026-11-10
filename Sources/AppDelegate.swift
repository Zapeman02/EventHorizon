import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var updateChecker: UpdateChecker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchController(shelf: Shelf())
        registerLoginItem()
        updateChecker = UpdateChecker()
        updateChecker?.run()
    }

    /// Only on first launch, so turning it off in Settings sticks.
    private func registerLoginItem() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if !LoginItem.isEnabled { LoginItem.set(true) }
    }
}
