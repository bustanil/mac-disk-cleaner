import Foundation

package enum DirectoryDescent: Equatable, Sendable {
    case enter
    case otherVolume
    case alreadyVisited
}

/// Read-only walk. Logical sizes. Each file's bytes are added to the total once.
package struct TreeWalker: Sendable {
    package init() {}

    package func walk(
        root: URL,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in },
        excludedDirectories: Set<String>? = nil
    ) -> ScanSnapshot {
        let root = root.standardizedFileURL
        let state = WalkState(
            isCancelled: isCancelled,
            onProgress: onProgress,
            excludedDirectories: excludedDirectories
                ?? Self.excludedDirectories(forScanRoot: root.path)
        )
        guard let info = FileStatusReader.read(path: root.path, followSymlink: true), info.isDirectory else {
            return ScanSnapshot(
                rootPath: root.path,
                status: .complete,
                itemsScanned: 0,
                skipped: 0,
                tree: nil,
                failure: "Couldn’t read \(root.path)."
            )
        }
        state.rootDevice = info.device
        state.visitedDirectories.insert(Self.identity(device: info.device, inode: info.inode))
        state.noteItem()
        state.enter(root.path)
        let tree = state.readDirectory(url: root, name: root.lastPathComponent)
        state.finish()
        return ScanSnapshot(
            rootPath: root.path,
            status: state.partial ? .partial : .complete,
            itemsScanned: state.itemsScanned,
            skipped: state.skipped,
            tree: tree,
            failure: nil,
            buckets: state.bucketSummaries(),
            listedFiles: state.listedFilesSorted()
        )
    }

    package static func directoryDescent(
        device: UInt64,
        inode: UInt64,
        rootDevice: UInt64,
        visited: Set<String>
    ) -> DirectoryDescent {
        if device != rootDevice {
            return .otherVolume
        }
        if visited.contains(identity(device: device, inode: inode)) {
            return .alreadyVisited
        }
        return .enter
    }

    package static func identity(device: UInt64, inode: UInt64) -> String {
        "\(device):\(inode)"
    }

    /// `/System/Volumes/Data` is the same files the startup disk already reaches through firmlinks such as `/Users`.
    package static func excludedDirectories(forScanRoot path: String) -> Set<String> {
        let root = URL(fileURLWithPath: path).standardizedFileURL.path
        guard root == "/" else { return [] }
        return ["/System/Volumes/Data"]
    }
}

private final class WalkState {
    let isCancelled: @Sendable () -> Bool
    let onProgress: @Sendable (ScanProgress) -> Void
    var rootDevice: UInt64 = 0
    var itemsScanned = 0
    var skipped = 0
    var partial = false
    var currentPath = ""
    var visitedDirectories = Set<String>()
    var countedFiles = Set<String>()
    let excludedDirectories: Set<String>
    var bucketCounts: [SizeClass: Int] = [:]
    var bucketBytes: [SizeClass: Int64] = [:]
    var listedFiles: [ListedFile] = []
    private var lastReportItems = 0
    private var lastReport = ContinuousClock().now
    private let clock = ContinuousClock()

    init(
        isCancelled: @escaping @Sendable () -> Bool,
        onProgress: @escaping @Sendable (ScanProgress) -> Void,
        excludedDirectories: Set<String>
    ) {
        self.isCancelled = isCancelled
        self.onProgress = onProgress
        self.excludedDirectories = excludedDirectories
    }

    func noteItem() {
        itemsScanned += 1
        let elapsed = lastReport.duration(to: clock.now)
        if itemsScanned - lastReportItems >= 200 || elapsed > .milliseconds(250) {
            publish()
        }
    }

    func enter(_ path: String) {
        currentPath = path
        publish()
    }

    func finish() {
        publish()
    }

    func readDirectory(url: URL, name: String) -> FileNode {
        if isCancelled() {
            partial = true
            return directoryNode(url: url, name: name, children: [], unreadable: false)
        }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            skipped += 1
            return directoryNode(url: url, name: name, children: [], unreadable: true)
        }

        var children: [FileNode] = []
        for entry in entries {
            if isCancelled() {
                partial = true
                break
            }
            noteItem()
            if let child = scanEntry(entry) {
                children.append(child)
            }
        }
        children.sort { lhs, rhs in
            if lhs.displayBytes != rhs.displayBytes {
                return lhs.displayBytes > rhs.displayBytes
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return directoryNode(url: url, name: name, children: children, unreadable: false)
    }

    func scanEntry(_ url: URL) -> FileNode? {
        if excludedDirectories.contains(url.standardizedFileURL.path) {
            return nil
        }
        guard let info = FileStatusReader.read(path: url.path, followSymlink: false) else {
            skipped += 1
            return nil
        }
        if info.isSymlink {
            return FileNode(
                id: url.path,
                name: url.lastPathComponent,
                apparentBytes: info.apparentBytes,
                contribution: info.apparentBytes,
                kind: .symlink,
                alreadyCounted: false,
                unreadable: false,
                children: nil
            )
        }
        if info.isDirectory {
            let descent = TreeWalker.directoryDescent(
                device: info.device,
                inode: info.inode,
                rootDevice: rootDevice,
                visited: visitedDirectories
            )
            switch descent {
            case .otherVolume:
                return FileNode(
                    id: url.path,
                    name: url.lastPathComponent,
                    apparentBytes: 0,
                    contribution: 0,
                    kind: .otherVolume,
                    alreadyCounted: false,
                    unreadable: false,
                    children: nil
                )
            case .alreadyVisited:
                return FileNode(
                    id: url.path,
                    name: url.lastPathComponent,
                    apparentBytes: 0,
                    contribution: 0,
                    kind: .directory,
                    alreadyCounted: true,
                    unreadable: false,
                    children: nil
                )
            case .enter:
                visitedDirectories.insert(TreeWalker.identity(device: info.device, inode: info.inode))
                enter(url.path)
                return readDirectory(url: url, name: url.lastPathComponent)
            }
        }

        let key = TreeWalker.identity(device: info.device, inode: info.inode)
        let duplicate = countedFiles.contains(key)
        if !duplicate {
            countedFiles.insert(key)
            recordFile(url: url, bytes: info.apparentBytes, modified: info.modified)
        }
        return FileNode(
            id: url.path,
            name: url.lastPathComponent,
            apparentBytes: info.apparentBytes,
            contribution: duplicate ? 0 : info.apparentBytes,
            kind: .file,
            alreadyCounted: duplicate,
            unreadable: false,
            children: nil
        )
    }

    func recordFile(url: URL, bytes: Int64, modified: Date) {
        let kind = SizeClass.classify(bytes)
        bucketCounts[kind, default: 0] += 1
        bucketBytes[kind, default: 0] += bytes
        guard kind.listsFiles else { return }
        let fileKind = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?
            .localizedTypeDescription ?? "File"
        listedFiles.append(ListedFile(
            id: url.path,
            name: url.lastPathComponent,
            path: url.path,
            bytes: bytes,
            kind: kind,
            fileKind: fileKind,
            modified: modified
        ))
    }

    func bucketSummaries() -> [SizeBucket] {
        SizeClass.allCases.map { kind in
            SizeBucket(kind: kind, count: bucketCounts[kind] ?? 0, bytes: bucketBytes[kind] ?? 0)
        }
    }

    func listedFilesSorted() -> [ListedFile] {
        listedFiles.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func directoryNode(url: URL, name: String, children: [FileNode], unreadable: Bool) -> FileNode {
        let contribution = children.reduce(Int64(0)) { $0 + $1.contribution }
        return FileNode(
            id: url.path,
            name: name,
            apparentBytes: contribution,
            contribution: contribution,
            kind: .directory,
            alreadyCounted: false,
            unreadable: unreadable,
            children: children
        )
    }

    func publish() {
        lastReport = clock.now
        lastReportItems = itemsScanned
        onProgress(ScanProgress(currentPath: currentPath, itemsScanned: itemsScanned))
    }
}
