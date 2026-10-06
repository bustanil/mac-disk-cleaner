import Darwin
import Foundation

package enum PathResolver {
    package static func resolve(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return nil }
        guard let terminator = buffer.firstIndex(of: 0) else { return nil }
        let bytes = buffer[..<terminator].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

package enum PathPolicy {
    package static func denialReason(
        path: String,
        homePath: String,
        appBundlePath: String?
    ) -> String? {
        guard let resolved = PathResolver.resolve(path) else {
            return "Couldn't find this item."
        }
        let home = PathResolver.resolve(homePath) ?? URL(fileURLWithPath: homePath).standardizedFileURL.path
        if resolved == home {
            return "The home folder itself stays."
        }
        if let appBundlePath {
            let app = PathResolver.resolve(appBundlePath) ?? URL(fileURLWithPath: appBundlePath).standardizedFileURL.path
            if resolved == app || resolved.hasPrefix(app + "/") {
                return "The app's own files stay."
            }
        }
        if isProtected(resolved) {
            return "This is a protected system location."
        }
        return nil
    }

    /// `/System/Volumes/Data` is the user data volume, so it is not treated as the sealed system.
    package static func isProtected(_ path: String) -> Bool {
        if path == "/System/Volumes/Data" || path.hasPrefix("/System/Volumes/Data/") {
            return false
        }
        if path == "/private/var" {
            return true
        }
        if path.hasPrefix("/private/var/") {
            let allowed = ["/private/var/log", "/private/var/folders"]
            return !allowed.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        let roots = ["/System", "/usr", "/bin", "/sbin"]
        return roots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

package struct TrashItemResult: Equatable, Sendable {
    package var path: String
    package var succeeded: Bool
    package var reason: String?
}

package enum TrashDeletion {
    package static func moveToTrash(
        paths: [String],
        homePath: String,
        appBundlePath: String?,
        trash: (URL) throws -> Void
    ) -> [TrashItemResult] {
        let ordered = paths.sorted { $0.count > $1.count }
        return ordered.map { path in
            if let reason = PathPolicy.denialReason(
                path: path,
                homePath: homePath,
                appBundlePath: appBundlePath
            ) {
                return TrashItemResult(path: path, succeeded: false, reason: reason)
            }
            do {
                try trash(URL(fileURLWithPath: path))
                return TrashItemResult(path: path, succeeded: true, reason: nil)
            } catch {
                return TrashItemResult(path: path, succeeded: false, reason: error.localizedDescription)
            }
        }
    }

    /// Permanently removes items that resolve to inside `trashDirectory`, and nowhere else.
    package static func emptyTrash(
        paths: [String],
        trashDirectory: String,
        remove: (URL) throws -> Void
    ) -> [TrashItemResult] {
        guard let trash = PathResolver.resolve(trashDirectory) else {
            return paths.map {
                TrashItemResult(path: $0, succeeded: false, reason: "Couldn't find the Trash.")
            }
        }
        let ordered = paths.sorted { $0.count > $1.count }
        return ordered.map { path in
            guard let resolved = PathResolver.resolve(path) else {
                return TrashItemResult(path: path, succeeded: false, reason: "Couldn't find this item.")
            }
            if resolved == trash {
                return TrashItemResult(path: path, succeeded: false, reason: "The Trash folder itself stays.")
            }
            if !resolved.hasPrefix(trash + "/") {
                return TrashItemResult(path: path, succeeded: false, reason: "This item is not inside the Trash.")
            }
            do {
                try remove(URL(fileURLWithPath: resolved))
                return TrashItemResult(path: path, succeeded: true, reason: nil)
            } catch {
                return TrashItemResult(path: path, succeeded: false, reason: error.localizedDescription)
            }
        }
    }
}
