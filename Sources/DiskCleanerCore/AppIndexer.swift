import Foundation

package struct AppIndexResult: Equatable, Sendable {
    package var apps: [AppRecord]
    package var cancelled: Bool
}

/// Top-level application bundles in the folders the spec names. Size is the bundle only.
package struct AppIndexer: Sendable {
    package init() {}

    package static func defaultDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    package func index(
        directories: [URL],
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) -> AppIndexResult {
        var apps: [AppRecord] = []
        var cancelled = false
        for directory in directories {
            if isCancelled() {
                cancelled = true
                break
            }
            let entries: [URL]
            do {
                entries = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
            } catch {
                continue
            }
            for appURL in entries where appURL.lastPathComponent.lowercased().hasSuffix(".app") {
                if isCancelled() {
                    cancelled = true
                    break
                }
                guard let info = FileStatusReader.read(path: appURL.path, followSymlink: false),
                      info.isDirectory, !info.isSymlink else {
                    continue
                }
                onProgress(ScanProgress(currentPath: appURL.path, itemsScanned: 0))
                let walked = TreeWalker().walk(root: appURL, isCancelled: isCancelled)
                if walked.status == .partial || isCancelled() {
                    cancelled = true
                    break
                }
                guard let bytes = walked.tree?.contribution else { continue }
                apps.append(AppRecord(
                    id: appURL.path,
                    name: appURL.deletingPathExtension().lastPathComponent,
                    path: appURL.path,
                    location: directory.standardizedFileURL.path,
                    bytes: bytes
                ))
            }
            if cancelled { break }
        }
        apps.sort { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return AppIndexResult(apps: apps, cancelled: cancelled)
    }
}
