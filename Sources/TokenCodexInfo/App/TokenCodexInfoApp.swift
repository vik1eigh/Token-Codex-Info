import AppKit
import SwiftUI
import TokenCodexInfoCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let usageModel = UsageViewModel(provider: ReportedCodexUsageProvider())
    let loginItems = LoginItemController()
    private var statusItemController: StatusItemController?
    private var settingsWindowController: DataSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        usageModel.start(settings: settings)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusItemController = StatusItemController(viewModel: self.usageModel, loginItems: self.loginItems) { [weak delegate = self] in
                delegate?.showDataSettings()
            }
            if !self.settings.hasCompletedSetup {
                self.showDataSettings()
            }
        }
    }

    private func showDataSettings() {
        if settingsWindowController == nil {
            settingsWindowController = DataSettingsWindowController(settings: settings, viewModel: usageModel)
        }
        settingsWindowController?.show()
    }
}

@main
struct TokenCodexInfoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(settings: appDelegate.settings, viewModel: appDelegate.usageModel)
        }
    }
}
