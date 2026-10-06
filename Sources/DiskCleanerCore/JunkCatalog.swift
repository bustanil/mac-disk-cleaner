import Foundation

package enum JunkCategory: String, CaseIterable, Equatable, Sendable {
    case userCaches
    case systemCaches
    case logs
    case browser
    case trash
    case downloads

    package var title: String {
        switch self {
        case .userCaches: return "User caches"
        case .systemCaches: return "System caches"
        case .logs: return "Logs"
        case .browser: return "Browser cache"
        case .trash: return "Trash"
        case .downloads: return "Old downloads"
        }
    }

    package var detail: String {
        switch self {
        case .userCaches: return "Files inside ~/Library/Caches"
        case .systemCaches: return "Files inside /Library/Caches that you can delete"
        case .logs: return "Last modified at least 24 hours ago"
        case .browser: return "Cache files for installed browsers. History, cookies, and passwords stay."
        case .trash: return "Contents of ~/.Trash. Emptying the Trash is permanent."
        case .downloads: return "Files in ~/Downloads. Partial downloads stay."
        }
    }
}

package struct JunkItem: Equatable, Sendable, Identifiable {
    package var id: String
    package var category: JunkCategory
    package var name: String
    package var path: String
    package var bytes: Int64
    package var modified: Date
    package var selectedByDefault: Bool
    package var blockedReason: String?
}

package struct JunkRoots: Equatable, Sendable {
    package var userCaches: URL
    package var systemCaches: URL
    package var userLogs: URL
    package var systemLogs: URL
    package var trash: URL
    package var downloads: URL

    package init(
        userCaches: URL,
        systemCaches: URL,
        userLogs: URL,
        systemLogs: URL,
        trash: URL,
        downloads: URL
    ) {
        self.userCaches = userCaches
        self.systemCaches = systemCaches
        self.userLogs = userLogs
        self.systemLogs = systemLogs
        self.trash = trash
        self.downloads = downloads
    }

    package static func standard(home: URL) -> JunkRoots {
        JunkRoots(
            userCaches: home.appendingPathComponent("Library/Caches"),
            systemCaches: URL(fileURLWithPath: "/Library/Caches"),
            userLogs: home.appendingPathComponent("Library/Logs"),
            systemLogs: URL(fileURLWithPath: "/Library/Logs"),
            trash: home.appendingPathComponent(".Trash"),
            downloads: home.appendingPathComponent("Downloads")
        )
    }
}

package struct JunkCatalogResult: Equatable, Sendable {
    package var items: [JunkItem]
    package var partialDownloads: Int
}

package enum JunkCatalog {
    package static let browserBlockedReason = "Quit the browser to clean this"

    package static func isAtLeast(days: Int, modified: Date, now: Date) -> Bool {
        modified.timeIntervalSince(now) <= -Double(days) * 86_400
    }

    package static func isAtLeast(hours: Int, modified: Date, now: Date) -> Bool {
        modified.timeIntervalSince(now) <= -Double(hours) * 3_600
    }

    package static func isPartialDownload(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".download") || lower.hasSuffix(".crdownload") || lower.hasSuffix(".part")
    }

    /// Downloads are stored with their newest modification date. The window filters them by age.
    package static func visible(
        _ items: [JunkItem],
        downloadAgeDays: Int,
        now: Date
    ) -> [JunkItem] {
        items.filter { item in
            guard item.category == .downloads else { return true }
            return isAtLeast(days: downloadAgeDays, modified: item.modified, now: now)
        }
    }

    package static func collect(
        roots: JunkRoots,
        now: Date = Date(),
        runningBundleIDs: Set<String> = []
    ) -> JunkCatalogResult {
        var items: [JunkItem] = []
        var partialDownloads = 0
        let browsers = browserCaches(in: roots.userCaches)
        let skippedCacheNames = Set(browsers.map { $0.cache.deletingLastPathComponent().lastPathComponent.lowercased() }
            + browsers.map { $0.cache.lastPathComponent.lowercased() })

        items += contents(of: roots.userCaches, category: .userCaches, selected: true) { url in
            !skippedCacheNames.contains(url.lastPathComponent.lowercased())
        }
        items += contents(of: roots.systemCaches, category: .systemCaches, selected: true)
        items += logs(at: roots.userLogs, now: now)
        items += logs(at: roots.systemLogs, now: now)
        for browser in browsers {
            guard FileManager.default.fileExists(atPath: browser.cache.path),
                  let measured = measure(browser.cache), measured.bytes > 0 else { continue }
            let blocked = runningBundleIDs.contains(browser.bundleID)
            items.append(JunkItem(
                id: browser.cache.path,
                category: .browser,
                name: browser.name,
                path: browser.cache.path,
                bytes: measured.bytes,
                modified: measured.newest,
                selectedByDefault: !blocked,
                blockedReason: blocked ? browserBlockedReason : nil
            ))
        }
        items += contents(of: roots.trash, category: .trash, selected: false)
        let downloads = downloadItems(at: roots.downloads)
        partialDownloads = downloads.partials
        items += downloads.items
        return JunkCatalogResult(items: items, partialDownloads: partialDownloads)
    }

    private static func browserCaches(in caches: URL) -> [(name: String, bundleID: String, cache: URL)] {
        [
            ("Safari", "com.apple.Safari", caches.appendingPathComponent("com.apple.Safari")),
            ("Chrome", "com.google.Chrome", caches.appendingPathComponent("Google/Chrome")),
            ("Firefox", "org.mozilla.firefox", caches.appendingPathComponent("Firefox")),
            ("Edge", "com.microsoft.edgemac", caches.appendingPathComponent("Microsoft Edge")),
            ("Brave", "com.brave.Browser", caches.appendingPathComponent("BraveSoftware/Brave-Browser")),
            ("Arc", "company.thebrowser.Browser", caches.appendingPathComponent("company.thebrowser.Browser")),
        ]
    }

    private static func contents(
        of directory: URL,
        category: JunkCategory,
        selected: Bool,
        include: (URL) -> Bool = { _ in true }
    ) -> [JunkItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return [] }
        return entries.compactMap { url in
            guard include(url), let measured = measure(url), measured.bytes > 0 else { return nil }
            return JunkItem(
                id: url.path,
                category: category,
                name: url.lastPathComponent,
                path: url.path,
                bytes: measured.bytes,
                modified: measured.newest,
                selectedByDefault: selected,
                blockedReason: nil
            )
        }
    }

    private static func logs(at directory: URL, now: Date) -> [JunkItem] {
        contents(of: directory, category: .logs, selected: true).filter {
            isAtLeast(hours: 24, modified: $0.modified, now: now)
        }
    }

    private static func downloadItems(at directory: URL) -> (items: [JunkItem], partials: Int) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return ([], 0) }
        var items: [JunkItem] = []
        var partials = 0
        for url in entries {
            if isPartialDownload(url.lastPathComponent) {
                partials += 1
                continue
            }
            guard let measured = measure(url), measured.bytes > 0 else { continue }
            items.append(JunkItem(
                id: url.path,
                category: .downloads,
                name: url.lastPathComponent,
                path: url.path,
                bytes: measured.bytes,
                modified: measured.newest,
                selectedByDefault: false,
                blockedReason: nil
            ))
        }
        return (items, partials)
    }

    /// Size and newest file date. A partial download anywhere inside excludes the whole item.
    private static func measure(_ url: URL) -> (bytes: Int64, newest: Date)? {
        guard let info = FileStatusReader.read(path: url.path, followSymlink: false), !info.isSymlink else {
            return nil
        }
        if isPartialDownload(url.lastPathComponent) { return nil }
        if !info.isDirectory {
            return (info.apparentBytes, info.modified)
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return nil }
        var bytes: Int64 = 0
        var newest = Date.distantPast
        for child in children {
            if isPartialDownload(child.lastPathComponent) { return nil }
            guard let measured = measure(child) else { continue }
            bytes += measured.bytes
            if measured.newest > newest { newest = measured.newest }
        }
        if bytes == 0 { return nil }
        return (bytes, newest)
    }
}
