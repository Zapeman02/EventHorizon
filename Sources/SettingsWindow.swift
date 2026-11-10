import AppKit
import ServiceManagement
import SwiftUI

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("EventHorizon: login item change failed: \(error)")
        }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(state: NotchState) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(state: state)))
            window.title = "EventHorizon Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var state: NotchState
    @AppStorage(UpdateChecker.enabledKey) private var checksForUpdates = false
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Picker("Drag mode", selection: $state.dragMode) {
                ForEach(DragMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Text(state.dragMode.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Check for updates at startup", isOn: $checksForUpdates)
            Toggle("Start at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LoginItem.set(enabled)
                    launchAtLogin = LoginItem.isEnabled
                }
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .fixedSize()
    }
}
