import Foundation
import ServiceManagement

@MainActor
final class LoginItemController: ObservableObject {
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled
    }

    var helpText: String {
        switch status {
        case .enabled:
            return "Disable launch at login"
        case .notRegistered:
            return "Enable launch at login"
        case .requiresApproval:
            return "Open System Settings to approve launch at login"
        case .notFound:
            return "Launch at login is unavailable for this app bundle"
        @unknown default:
            return "Update launch at login"
        }
    }

    init() {
        refresh()
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }

            errorMessage = nil
        } catch {
            errorMessage = "Unable to update Launch at Login: \(error.localizedDescription)"
        }

        refresh()
    }
}
