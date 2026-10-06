import Darwin
import DiskCleanerCore
import Foundation

func nestedSizesRollUpAndSortLargestFirst() throws {
    let root = try makeTemp()
    defer { remove(root) }
    try write(bytes: 5_000, named: "top.bin", in: root)
    let folder = root.appendingPathComponent("folder", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try write(bytes: 2_000, named: "nested.bin", in: folder)
    try write(bytes: 100, named: "small.bin", in: root)

    let snapshot = TreeWalker().walk(root: root)
    let tree = try Expect.unwrap(snapshot.tree)

    Expect.equal(snapshot.status, .complete)
    Expect.isNil(snapshot.failure)
    Expect.equal(tree.contribution, 7_100)
    Expect.equal(tree.children?.map(\.name), ["top.bin", "folder", "small.bin"])
    Expect.equal(tree.children?[1].children?.first?.name, "nested.bin")
    Expect.equal(tree.children?[1].contribution, 2_000)
}

func hardLinksCountBytesOnce() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let original = try write(bytes: 4_096, named: "original.bin", in: root)
    try FileManager.default.linkItem(
        at: original,
        to: root.appendingPathComponent("alias.bin")
    )

    let snapshot = TreeWalker().walk(root: root)
    let tree = try Expect.unwrap(snapshot.tree)
    let files = try Expect.unwrap(tree.children)

    Expect.equal(tree.contribution, 4_096)
    Expect.equal(files.count, 2)
    Expect.equal(files.filter(\.alreadyCounted).count, 1)
    Expect.equal(files.filter { !$0.alreadyCounted }.first?.contribution, 4_096)
}

func symlinkIsNotFollowed() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { remove(outside) }
    try write(bytes: 200_000, named: "big.bin", in: outside)
    try write(bytes: 100, named: "real.bin", in: root)
    let link = root.appendingPathComponent("link-to-big")
    try FileManager.default.createSymbolicLink(
        at: link,
        withDestinationURL: outside.appendingPathComponent("big.bin")
    )
    let loop = root.appendingPathComponent("loop")
    try FileManager.default.createSymbolicLink(at: loop, withDestinationURL: root)

    let snapshot = TreeWalker().walk(root: root)
    let tree = try Expect.unwrap(snapshot.tree)
    let linkStatus = try Expect.unwrap(FileStatusReader.read(path: link.path, followSymlink: false))
    let loopStatus = try Expect.unwrap(FileStatusReader.read(path: loop.path, followSymlink: false))

    Expect.equal(snapshot.status, .complete)
    Expect.equal(tree.contribution, 100 + linkStatus.apparentBytes + loopStatus.apparentBytes)
    Expect.equal(tree.children?.first { $0.name == "link-to-big" }?.kind, .symlink)
    Expect.equal(tree.children?.first { $0.name == "loop" }?.kind, .symlink)
    Expect.isNil(tree.children?.first { $0.name == "link-to-big" }?.children)
}

func cancelKeepsPartialSnapshot() throws {
    let root = try makeTemp()
    defer { remove(root) }
    for index in 0..<40 {
        try write(bytes: 10, named: String(format: "file-%02d.bin", index), in: root)
    }
    let counter = CancelCounter()

    let snapshot = TreeWalker().walk(root: root, isCancelled: {
        counter.checks += 1
        return counter.checks >= 4
    })

    Expect.equal(snapshot.status, .partial)
    Expect.isTrue((snapshot.tree?.children?.count ?? 0) < 40, "cancel should stop before every file")
    Expect.isTrue(snapshot.itemsScanned > 0, "partial scan should keep a count")
}

func unreadableDirectoryIsSkipped() throws {
    if geteuid() == 0 {
        print("SKIP unreadableDirectoryIsSkipped (running as root)")
        return
    }
    let root = try makeTemp()
    defer { remove(root) }
    let secret = root.appendingPathComponent("secret", isDirectory: true)
    try FileManager.default.createDirectory(at: secret, withIntermediateDirectories: true)
    try write(bytes: 1_234, named: "hidden.bin", in: secret)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: secret.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: secret.path)
    }

    let snapshot = TreeWalker().walk(root: root)
    let tree = try Expect.unwrap(snapshot.tree)

    Expect.equal(snapshot.status, .complete)
    Expect.equal(tree.contribution, 0)
    Expect.equal(snapshot.skipped, 1)
    Expect.equal(tree.children?.first?.unreadable, true)
}

func scanDoesNotChangeFileContents() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let file = try write(bytes: 32, named: "keep.txt", in: root)
    let before = try Data(contentsOf: file)
    _ = TreeWalker().walk(root: root)
    Expect.equal(try Data(contentsOf: file), before)
}

func missingRootFailsWithoutATree() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let missing = root.appendingPathComponent("missing")
    let snapshot = TreeWalker().walk(root: missing)
    Expect.isNil(snapshot.tree)
    Expect.isTrue(snapshot.failure != nil, "missing root should explain the failure")
    Expect.equal(snapshot.status, .complete)
}

func otherVolumeAndVisitedDirectoryAreNotEntered() {
    Expect.equal(
        TreeWalker.directoryDescent(device: 2, inode: 1, rootDevice: 1, visited: []),
        .otherVolume
    )
    Expect.equal(
        TreeWalker.directoryDescent(device: 1, inode: 9, rootDevice: 1, visited: ["1:9"]),
        .alreadyVisited
    )
    Expect.equal(
        TreeWalker.directoryDescent(device: 1, inode: 3, rootDevice: 1, visited: []),
        .enter
    )
}

func makeTemp() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("disk-cleaner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@discardableResult
func write(bytes: Int, named name: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data(count: bytes).write(to: url)
    return url
}

func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private final class CancelCounter: @unchecked Sendable {
    var checks = 0
}
