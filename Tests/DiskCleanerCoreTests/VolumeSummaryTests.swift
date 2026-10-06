import DiskCleanerCore
import Foundation

func volumeSummaryKeepsPurgeableOutOfUsed() {
    let summary = VolumeSummaryReader.summarize(
        name: "Macintosh HD",
        totalBytes: 1_000,
        availableBytes: 200,
        importantBytes: 350
    )
    Expect.equal(summary.freeBytes, 350)
    Expect.equal(summary.purgeableBytes, 150)
    Expect.equal(summary.usedBytes, 650)
    Expect.equal(summary.usedBytes + summary.freeBytes, summary.totalBytes)
    Expect.isTrue(summary.purgeableBytes <= summary.freeBytes, "purgeable space is part of free space")
}

func volumeSummaryWithoutPurgeable() {
    let summary = VolumeSummaryReader.summarize(
        name: "Macintosh HD",
        totalBytes: 500,
        availableBytes: 120,
        importantBytes: 120
    )
    Expect.equal(summary.purgeableBytes, 0)
    Expect.equal(summary.freeBytes, 120)
    Expect.equal(summary.usedBytes, 380)
}

func startupScanSkipsTheDataVolumeMirror() {
    Expect.equal(
        TreeWalker.excludedDirectories(forScanRoot: "/"),
        ["/System/Volumes/Data"]
    )
    Expect.equal(
        TreeWalker.excludedDirectories(forScanRoot: "/Users/bustanil.arifin"),
        []
    )
}

func excludedDirectoryIsLeftOutOfTheTree() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let hidden = root.appendingPathComponent("mirror", isDirectory: true)
    try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
    try write(bytes: 5_000, named: "big.bin", in: hidden)
    try write(bytes: 100, named: "keep.bin", in: root)

    let snapshot = TreeWalker().walk(
        root: root,
        excludedDirectories: [hidden.standardizedFileURL.path]
    )
    let tree = try Expect.unwrap(snapshot.tree)

    Expect.equal(tree.contribution, 100)
    Expect.equal(tree.children?.contains { $0.name == "mirror" } ?? false, false)
}

func fullDiskAccessSettingsURLOpensThePrivacyPane() {
    let url = FullDiskAccess.settingsURL
    Expect.equal(url.scheme, "x-apple.systempreferences")
    Expect.isTrue(
        url.absoluteString.contains("Privacy_AllFiles"),
        "settings URL should open Full Disk Access"
    )
    _ = FullDiskAccess.isGranted()
}
