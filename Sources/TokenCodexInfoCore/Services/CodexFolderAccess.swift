import Foundation

public enum CodexFolderAccess: Equatable, Sendable {
    case readable
    case missing
    case notDirectory
    case denied
    case failed
}

public protocol CodexFolderChecking: Sendable {
    func check(_ url: URL) -> CodexFolderAccess
}

public struct CodexFolderChecker: CodexFolderChecking {
    public init() {}

    public func check(_ url: URL) -> CodexFolderAccess {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return .notDirectory }
            // Actually attempt the read: existence alone does not prove access.
            _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            return .readable
        } catch {
            if isCodexPermissionError(error) { return .denied }
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                return .missing
            }
            return .failed
        }
    }
}

func isCodexPermissionError(_ error: Error) -> Bool {
    let error = error as NSError
    if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
    if error.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(error.code) { return true }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
        return isCodexPermissionError(underlying)
    }
    return false
}
