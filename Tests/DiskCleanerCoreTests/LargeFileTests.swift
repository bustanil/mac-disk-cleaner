import DiskCleanerCore
import Foundation

func minimumFilterHidesFilesBelowTheThreshold() {
    let small = listed(name: "notes.pdf", bytes: 40_000_000)
    let mid = listed(name: "clip.bin", bytes: 60_000_000)
    let huge = listed(name: "lecture.mov", bytes: 2_000_000_000)
    let files = [huge, mid, small]

    Expect.equal(LargeFileQuery.files(files, minimumBytes: 100_000_000, nameQuery: "").map(\.name), ["lecture.mov"])
    Expect.equal(LargeFileQuery.files(files, minimumBytes: 50_000_000, nameQuery: "").map(\.name), ["lecture.mov", "clip.bin"])
    Expect.equal(LargeFileQuery.files(files, minimumBytes: 50_000_000, nameQuery: "clip").map(\.name), ["clip.bin"])
}

func largestFoldersStopAtFiftyAndSkipTheRoot() {
    let children = (0..<60).map { index in
        directory(name: String(format: "folder-%02d", index), bytes: Int64((60 - index) * 10_000_000), children: [])
    }
    let tree = directory(name: "root", bytes: 0, children: children)
    let ranked = LargeFileQuery.folders(in: tree, minimumBytes: 100_000_000, nameQuery: "")
    Expect.equal(ranked.count, 50)
    Expect.equal(ranked.first?.name, "folder-00")
    Expect.equal(ranked.contains { $0.name == "root" }, false)
    Expect.equal(ranked.contains { $0.name == "folder-59" }, false)
}

func protectedSystemPathIsRefusedAndHomeFileIsAllowed() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    Expect.equal(
        PathPolicy.denialReason(path: "/usr/bin", homePath: home, appBundlePath: nil),
        "This is a protected system location."
    )
    Expect.equal(
        PathPolicy.denialReason(path: "/var/db", homePath: home, appBundlePath: nil),
        "This is a protected system location."
    )
    Expect.isNil(PathPolicy.denialReason(path: "/var/log", homePath: home, appBundlePath: nil))
    Expect.equal(
        PathPolicy.denialReason(path: home, homePath: home, appBundlePath: nil),
        "The home folder itself stays."
    )
    Expect.isNil(PathPolicy.denialReason(path: home + "/Library", homePath: home, appBundlePath: nil))
}

func symlinkIntoAProtectedDirectoryIsRefused() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let link = root.appendingPathComponent("to-bin")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/bin"))
    let reason = PathPolicy.denialReason(path: link.path, homePath: root.path, appBundlePath: nil)
    Expect.equal(reason, "This is a protected system location.")
}

func trashMovesATempFileAndTheSnapshotTotalDrops() throws {
    let root = try makeTemp()
    defer { remove(root) }
    try write(bytes: 100, named: "gone.bin", in: root)
    try write(bytes: 40, named: "keep.bin", in: root)
    var snapshot = TreeWalker().walk(root: root)
    let gonePath = try Expect.unwrap(snapshot.tree?.children?.first { $0.name == "gone.bin" }?.id)
    let trashDir = root.appendingPathComponent("trash-bin", isDirectory: true)
    try FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)

    let results = TrashDeletion.moveToTrash(
        paths: [gonePath],
        homePath: root.path,
        appBundlePath: nil
    ) { url in
        let destination = trashDir.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
    }

    Expect.equal(results.first?.succeeded, true)
    snapshot = SnapshotEditing.removing(paths: [gonePath], from: snapshot)
    Expect.equal(snapshot.tree?.contribution, 40)
    Expect.equal(FileManager.default.fileExists(atPath: gonePath), false)
}

func protectedPathIsNotTrashed() throws {
    let counter = CallCounter()
    let results = TrashDeletion.moveToTrash(
        paths: ["/usr/bin"],
        homePath: "/Users/bustanil.arifin",
        appBundlePath: nil
    ) { _ in
        counter.calls += 1
    }
    Expect.equal(counter.calls, 0)
    Expect.equal(results.first?.succeeded, false)
    Expect.equal(results.first?.reason, "This is a protected system location.")
}

private func listed(name: String, bytes: Int64) -> ListedFile {
    ListedFile(
        id: "/tmp/\(name)",
        name: name,
        path: "/tmp/\(name)",
        bytes: bytes,
        kind: SizeClass.classify(bytes),
        fileKind: "File",
        modified: Date(timeIntervalSince1970: 0)
    )
}

private func directory(name: String, bytes: Int64, children: [FileNode]) -> FileNode {
    FileNode(
        id: "/\(name)",
        name: name,
        apparentBytes: bytes,
        contribution: bytes,
        kind: .directory,
        alreadyCounted: false,
        unreadable: false,
        children: children
    )
}

final class CallCounter: @unchecked Sendable {
    var calls = 0
}
