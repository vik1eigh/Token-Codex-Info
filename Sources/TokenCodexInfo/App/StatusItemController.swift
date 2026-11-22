import AppKit
import Combine
import TokenCodexInfoCore

@MainActor
final class StatusItemController: NSObject {
    private static let menuAppearance = NSAppearance(named: .aqua)
    private static let minimumStatusItemWidth: CGFloat = 82
    private static let statusItemHorizontalPadding: CGFloat = 12
    private static let menuVerticalOffset: CGFloat = 8

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let viewModel: UsageViewModel
    private let loginItems: LoginItemController
    private let showSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: UsageViewModel, loginItems: LoginItemController, showSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.loginItems = loginItems
        self.showSettings = showSettings

        super.init()

        configureStatusItem()
        bindViewModel()
        updateStatusTitle()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateStatusTitle()
        }
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        statusItem.isVisible = true
        statusItem.length = Self.minimumStatusItemWidth

        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        button.alignment = .left
        button.imagePosition = .noImage
        button.imageScaling = .scaleNone
    }

    private func bindViewModel() {
        viewModel.$snapshot
            .combineLatest(viewModel.$now)
            .sink { [weak self] snapshot, now in
                self?.updateStatusTitle(snapshot: snapshot, now: now)
            }
            .store(in: &cancellables)
    }

    private func updateStatusTitle() {
        updateStatusTitle(snapshot: viewModel.snapshot, now: viewModel.now)
    }

    private func updateStatusTitle(snapshot: UsageSnapshot, now: Date) {
        let title = menuBarAttributedTitle(snapshot: snapshot, now: now)
        let accessibilityTitle = snapshot.menuBarAccessibilityTitle(now: now)
        let width = max(
            Self.minimumStatusItemWidth,
            ceil(title.size().width) + Self.statusItemHorizontalPadding
        )

        statusItem.isVisible = true
        statusItem.length = width

        guard let button = statusItem.button else {
            return
        }

        button.image = nil
        button.imagePosition = .noImage
        button.title = title.string
        button.toolTip = accessibilityTitle
        button.setAccessibilityLabel(accessibilityTitle)
    }

    private func menuBarAttributedTitle(snapshot: UsageSnapshot, now: Date) -> NSAttributedString {
        let parts = snapshot.menuBarTitleParts(now: now)
        return Self.makeStatusTitleString(parts.stringValue)
    }

    private static func makeStatusTitleString(_ value: String) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        return NSAttributedString(string: value, attributes: [.font: font])
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        handleStatusItemClick(event: NSApp.currentEvent, from: sender)
    }

    private func handleStatusItemClick(event: NSEvent?, from view: NSView) {
        showControlsMenu(from: view)
    }

    private func showControlsMenu(from view: NSView) {
        loginItems.refresh()

        let menu = NSMenu()
        configureMenuAppearance(menu)
        menu.autoenablesItems = false

        let statusItem = NSMenuItem(title: viewModel.snapshot.statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        let settingsItem = NSMenuItem(title: "Data & Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = loginItems.isEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: viewModel.isRefreshing ? "Refreshing..." : "Refresh", action: #selector(refreshUsage(_:)), keyEquivalent: "")
        refreshItem.target = self
        refreshItem.isEnabled = !viewModel.isRefreshing
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp(_:)), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        popUp(menu, from: view)
    }

    private func configureMenuAppearance(_ menu: NSMenu) {
        menu.appearance = Self.menuAppearance
    }

    private func popUp(_ menu: NSMenu, from view: NSView) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + Self.menuVerticalOffset), in: view)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        loginItems.toggle()
        sender.state = loginItems.isEnabled ? .on : .off
    }

    @objc private func refreshUsage(_ sender: NSMenuItem) {
        viewModel.refreshNow()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        showSettings()
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApplication.shared.terminate(nil)
    }
}
