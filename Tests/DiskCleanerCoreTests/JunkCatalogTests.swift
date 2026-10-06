import Foundation
import DiskCleanerCore

func downloadAgeKeepsAFileFrom29DaysAgo() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let thirty = now.addingTimeInterval(-30 * 86_400)
    let twentyNine = now.addingTimeInterval(-29 * 86_400)
    Expect.equal(JunkCatalog.isAtLeast(days: 30, modified: thirty, now: now), true)
    Expect.equal(JunkCatalog.isAtLeast(days: 30, modified: twentyNine, now: now), false)
    Expect.equal(JunkCatalog.isAtLeast(hours: 24, modified: now.addingTimeInterval(-24 * 3_600), now: now), true)
    Expect.equal(JunkCatalog.isAtLeast(hours: 24, modified: now.addingTimeInterval(-23 * 3_600), now: now), false)
}

func junkCatalogAppliesTheCategoryRules() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let now = Date()
    let caches = root.appendingPathComponent("Library/Caches", isDirectory: true)
    let logs = root.appendingPathComponent("Library/Logs", isDirectory: true)
    let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
    let trash = root.appendingPathComponent(".Trash", isDirectory: true)
    let systemCaches = root.appendingPathComponent("SystemCaches", isDirectory: true)
    let systemLogs = root.appendingPathComponent("SystemLogs", isDirectory: true)
    for directory in [caches, logs, downloads, trash, systemCaches, systemLogs] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let brew = caches.appendingPathComponent("Homebrew", isDirectory: true)
    try FileManager.default.createDirectory(at: brew, withIntermediateDirectories: true)
    try write(bytes: 100, named: "bottle", in: brew)

    let safari = caches.appendingPathComponent("com.apple.Safari", isDirectory: true)
    try FileManager.default.createDirectory(at: safari, withIntermediateDirectories: true)
    try write(bytes: 50, named: "cache", in: safari)

    let oldLog = try write(bytes: 20, named: "old.log", in: logs)
    let newLog = try write(bytes: 20, named: "new.log", in: logs)
    try setModified(oldLog, now.addingTimeInterval(-48 * 3_600))
    try setModified(newLog, now.addingTimeInterval(-60))

    let oldDownload = try write(bytes: 80, named: "old.bin", in: downloads)
    let recentDownload = try write(bytes: 80, named: "recent.bin", in: downloads)
    try write(bytes: 80, named: "video.crdownload", in: downloads)
    try setModified(oldDownload, now.addingTimeInterval(-31 * 86_400))
    try setModified(recentDownload, now.addingTimeInterval(-29 * 86_400))

    let mixed = downloads.appendingPathComponent("Project", isDirectory: true)
    try FileManager.default.createDirectory(at: mixed, withIntermediateDirectories: true)
    let oldInside = try write(bytes: 10, named: "old.txt", in: mixed)
    let newInside = try write(bytes: 10, named: "new.txt", in: mixed)
    try setModified(oldInside, now.addingTimeInterval(-40 * 86_400))
    try setModified(newInside, now.addingTimeInterval(-10 * 86_400))

    try write(bytes: 5, named: "gone.txt", in: trash)
    try write(bytes: 30, named: "system.tmp", in: systemCaches)

    let result = JunkCatalog.collect(
        roots: JunkRoots(
            userCaches: caches,
            systemCaches: systemCaches,
            userLogs: logs,
            systemLogs: systemLogs,
            trash: trash,
            downloads: downloads
        ),
        now: now,
        runningBundleIDs: ["com.apple.Safari"]
    )

    let userNames = result.items.filter { $0.category == .userCaches }.map(\.name)
    Expect.equal(userNames, ["Homebrew"])
    let safariItem = try Expect.unwrap(result.items.first { $0.name == "Safari" })
    Expect.equal(safariItem.category, .browser)
    Expect.equal(safariItem.selectedByDefault, false)
    Expect.equal(safariItem.blockedReason, JunkCatalog.browserBlockedReason)

    let logNames = result.items.filter { $0.category == .logs }.map(\.name)
    Expect.equal(logNames.contains("old.log"), true)
    Expect.equal(logNames.contains("new.log"), false)

    let visible = JunkCatalog.visible(result.items, downloadAgeDays: 30, now: now)
    let downloadNames = visible.filter { $0.category == .downloads }.map(\.name)
    Expect.equal(downloadNames.contains("old.bin"), true)
    Expect.equal(downloadNames.contains("recent.bin"), false)
    Expect.equal(downloadNames.contains("Project"), false)
    Expect.equal(downloadNames.contains("video.crdownload"), false)
    Expect.equal(result.partialDownloads, 1)

    let trashItem = try Expect.unwrap(result.items.first { $0.category == .trash })
    Expect.equal(trashItem.selectedByDefault, false)
}

private func setModified(_ url: URL, _ date: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}
