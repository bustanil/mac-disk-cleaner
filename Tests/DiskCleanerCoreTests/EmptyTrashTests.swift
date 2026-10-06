import Foundation
import DiskCleanerCore

func emptyTrashRemovesOnlyTheListedItem() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let trash = root.appendingPathComponent("Trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    let listed = try write(bytes: 20, named: "listed.txt", in: trash)
    let kept = try write(bytes: 20, named: "kept.txt", in: trash)

    let results = TrashDeletion.emptyTrash(
        paths: [listed.path],
        trashDirectory: trash.path,
        remove: { url in try FileManager.default.removeItem(at: url) }
    )

    Expect.equal(results.first?.succeeded, true)
    Expect.equal(FileManager.default.fileExists(atPath: listed.path), false)
    Expect.equal(FileManager.default.fileExists(atPath: kept.path), true)
    Expect.equal(FileManager.default.fileExists(atPath: trash.path), true)
}

func emptyTrashRefusesAPathOutsideTheTrash() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let trash = root.appendingPathComponent("Trash", isDirectory: true)
    let outside = root.appendingPathComponent("Outside", isDirectory: true)
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let kept = try write(bytes: 10, named: "keep.txt", in: outside)
    let counter = CallCounter()

    let results = TrashDeletion.emptyTrash(
        paths: [kept.path, trash.path],
        trashDirectory: trash.path
    ) { _ in
        counter.calls += 1
    }

    Expect.equal(counter.calls, 0)
    Expect.equal(results.allSatisfy { !$0.succeeded }, true)
    Expect.equal(FileManager.default.fileExists(atPath: kept.path), true)
    Expect.equal(FileManager.default.fileExists(atPath: trash.path), true)
}

func emptyTrashRefusesASymlinkThatLeavesTheTrash() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let trash = root.appendingPathComponent("Trash", isDirectory: true)
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    let outside = try write(bytes: 15, named: "secret.txt", in: root)
    let link = trash.appendingPathComponent("secret-link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    let counter = CallCounter()

    let results = TrashDeletion.emptyTrash(
        paths: [link.path],
        trashDirectory: trash.path
    ) { _ in
        counter.calls += 1
    }

    Expect.equal(counter.calls, 0)
    Expect.equal(results.first?.reason, "This item is not inside the Trash.")
    Expect.equal(FileManager.default.fileExists(atPath: outside.path), true)
}
