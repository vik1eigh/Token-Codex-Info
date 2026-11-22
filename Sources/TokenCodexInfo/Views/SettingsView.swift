import AppKit
import SwiftUI
import TokenCodexInfoCore

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var viewModel: UsageViewModel
    @State private var folderPath: String
    @State private var folderValidationMessage: String?
    var onDone: (() -> Void)?

    init(settings: SettingsStore, viewModel: UsageViewModel, onDone: (() -> Void)? = nil) {
        self.settings = settings
        self.viewModel = viewModel
        self.onDone = onDone
        _folderPath = State(initialValue: settings.codexHomePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(settings.hasCompletedSetup ? "Codex Data & Settings" : "Connect your Codex data")
                    .font(.title2.weight(.semibold))
                Text("Read usage from Codex on this Mac. No API key or sign-in is needed.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    if viewModel.isRefreshing {
                        ProgressView().controlSize(.small).padding(.top, 3)
                    } else {
                        Image(systemName: statusSymbol)
                            .font(.title3)
                            .foregroundStyle(statusColor)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text(viewModel.isRefreshing ? "Checking Codex data…" : viewModel.snapshot.statusTitle)
                            .font(.headline)
                        Text(viewModel.isRefreshing ? CodexDataIssue.checking.message : viewModel.snapshot.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if viewModel.snapshot.hasData && !viewModel.isRefreshing {
                            Text(viewModel.snapshot.menuBarTitleParts(now: viewModel.now).stringValue)
                                .font(.system(.title3, design: .monospaced).weight(.medium))
                        }
                        if let lastCheckedAt = viewModel.lastCheckedAt, !viewModel.isRefreshing {
                            Text("Last checked \(lastCheckedAt.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 9) {
                Text("Codex data folder").font(.headline)
                TextField("Folder path", text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(checkAgain)
                    .accessibilityLabel("Codex data folder path")
                if let folderValidationMessage {
                    Text(folderValidationMessage).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Choose Folder…", action: chooseFolder)
                    Button("Use Default") {
                        folderPath = SettingsStore.defaultCodexHomePath
                        checkAgain()
                    }
                    Spacer()
                    Button("Check Again", action: checkAgain)
                        .disabled(viewModel.isRefreshing)
                }
                Text("Usually ~/.codex. The app needs read access to this folder and its usage files; Full Disk Access is not normally required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Token estimates & refresh") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These token limits are used only for approximate usage when Codex does not report its limits. Estimates are marked ≈ in the menu bar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("5-hour token limit")
                        Spacer()
                        TextField("5-hour token limit", value: $settings.fiveHourTokenLimit, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                    HStack {
                        Text("Weekly token limit")
                        Spacer()
                        TextField("Weekly token limit", value: $settings.weeklyTokenLimit, format: .number)
                            .textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                    Stepper("Refresh every \(settings.refreshIntervalSeconds) seconds", value: $settings.refreshIntervalSeconds, in: 15...600, step: 15)
                }
                .padding(.top, 10)
            }

            Divider()
            HStack(alignment: .center, spacing: 16) {
                Text("Your data stays on this Mac. You can reopen this window from Data & Settings in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let onDone {
                    Button(viewModel.snapshot.hasData ? "Done" : "Continue in Menu Bar") {
                        guard applyFolderSelection() else { return }
                        settings.completeSetup()
                        onDone()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
    }

    private var statusSymbol: String {
        if viewModel.snapshot.hasData {
            return viewModel.snapshot.source.isEstimate ? "exclamationmark.triangle" : "checkmark.circle.fill"
        }
        return viewModel.snapshot.issue == .accessDenied ? "lock.fill" : "info.circle"
    }

    private var statusColor: Color {
        guard viewModel.snapshot.hasData else { return .secondary }
        return viewModel.snapshot.source.isEstimate ? .orange : .green
    }

    private func checkAgain() {
        let previousPath = settings.codexHomePath
        guard applyFolderSelection() else { return }
        if previousPath == settings.codexHomePath {
            viewModel.refreshNow()
        }
    }

    @discardableResult
    private func applyFolderSelection() -> Bool {
        // Keep drafts local until the user explicitly checks or selects a folder.
        let path = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            folderValidationMessage = "Enter a folder path or choose a folder."
            return false
        }
        folderValidationMessage = nil
        folderPath = path
        if settings.codexHomePath != path {
            settings.codexHomePath = path
        }
        return true
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your Codex data folder"
        panel.message = "Select the folder containing Codex sessions and usage databases. Usually this is ~/.codex."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose Folder"
        panel.directoryURL = settings.usageSettings.expandedCodexHomeURL
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            checkAgain()
        }
    }
}

@MainActor
final class DataSettingsWindowController: NSWindowController {
    init(settings: SettingsStore, viewModel: UsageViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 550),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Token Codex Info"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, viewModel: viewModel) { [weak self] in
            self?.close()
        })
        window.center()
    }

    required init?(coder: NSCoder) { return nil }

    func show() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
