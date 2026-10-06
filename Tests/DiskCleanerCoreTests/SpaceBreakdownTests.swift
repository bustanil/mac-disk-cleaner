import DiskCleanerCore
import Foundation

func sizeClassBoundaries() {
    Expect.equal(SizeClass.classify(10_000_000 - 1), .small)
    Expect.equal(SizeClass.classify(10_000_000), .medium)
    Expect.equal(SizeClass.classify(100_000_000 - 1), .medium)
    Expect.equal(SizeClass.classify(100_000_000), .large)
    Expect.equal(SizeClass.classify(1_000_000_000 - 1), .large)
    Expect.equal(SizeClass.classify(1_000_000_000), .huge)
    Expect.equal(SizeClass.small.listsFiles, false)
    Expect.equal(SizeClass.huge.listsFiles, true)
}

func smallFilesStayATotalAndMediumFilesAreListed() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let note = try write(bytes: 100, named: "note.txt", in: root)
    try FileManager.default.linkItem(at: note, to: root.appendingPathComponent("note-link.txt"))
    try write(bytes: 10_000_000, named: "clip.bin", in: root)

    let snapshot = TreeWalker().walk(root: root)
    let buckets = Dictionary(uniqueKeysWithValues: snapshot.buckets.map { ($0.kind, $0) })
    let small = try Expect.unwrap(buckets[.small])
    let medium = try Expect.unwrap(buckets[.medium])
    let large = try Expect.unwrap(buckets[.large])
    let huge = try Expect.unwrap(buckets[.huge])

    Expect.equal(small.count, 1)
    Expect.equal(small.bytes, 100)
    Expect.equal(medium.count, 1)
    Expect.equal(medium.bytes, 10_000_000)
    Expect.equal(large.count, 0)
    Expect.equal(huge.count, 0)
    Expect.equal(snapshot.listedFiles.map(\.name), ["clip.bin"])
}

func appIndexMeasuresBundlesOnly() throws {
    let root = try makeTemp()
    defer { remove(root) }
    let apps = root.appendingPathComponent("Applications", isDirectory: true)
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    try write(bytes: 40, named: "readme.txt", in: apps)

    let demo = apps.appendingPathComponent("Demo.app/Contents/MacOS", isDirectory: true)
    try FileManager.default.createDirectory(at: demo, withIntermediateDirectories: true)
    try write(bytes: 80, named: "Demo", in: demo)

    let bigger = apps.appendingPathComponent("Bigger.app", isDirectory: true)
    try FileManager.default.createDirectory(at: bigger, withIntermediateDirectories: true)
    try write(bytes: 200, named: "Bigger", in: bigger)

    let outside = try write(bytes: 500, named: "real.bin", in: root)
    try FileManager.default.createSymbolicLink(
        at: apps.appendingPathComponent("Linked.app"),
        withDestinationURL: outside
    )

    let result = AppIndexer().index(directories: [apps])
    Expect.equal(result.cancelled, false)
    Expect.equal(result.apps.map(\.name), ["Bigger", "Demo"])
    Expect.equal(result.apps.map(\.bytes), [200, 80])
    Expect.equal(result.apps.first?.location, apps.standardizedFileURL.path)
    Expect.equal(result.apps.first?.path.hasSuffix("Bigger.app"), true)
}
