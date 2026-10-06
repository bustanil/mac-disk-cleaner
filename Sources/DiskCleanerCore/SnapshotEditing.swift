import Foundation

package enum LargeFileQuery {
    package static func files(
        _ files: [ListedFile],
        minimumBytes: Int64,
        nameQuery: String
    ) -> [ListedFile] {
        let query = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return files.filter { file in
            file.bytes >= minimumBytes && (query.isEmpty || file.name.lowercased().contains(query))
        }
    }

    /// Largest folders in the tree, excluding the scan root. Parent and child can both appear.
    package static func folders(
        in tree: FileNode,
        minimumBytes: Int64,
        nameQuery: String,
        limit: Int = 50
    ) -> [FileNode] {
        var found: [FileNode] = []
        func collect(_ node: FileNode) {
            for child in node.children ?? [] where child.kind == .directory {
                found.append(child)
                collect(child)
            }
        }
        collect(tree)
        let query = nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return found
            .filter { folder in
                folder.contribution >= minimumBytes
                    && (query.isEmpty || folder.name.lowercased().contains(query))
            }
            .sorted { lhs, rhs in
                if lhs.contribution != rhs.contribution { return lhs.contribution > rhs.contribution }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }
}

package enum SnapshotEditing {
    package static func removing(paths: Set<String>, from snapshot: ScanSnapshot) -> ScanSnapshot {
        var updated = snapshot
        updated.junk = snapshot.junk.filter { !isCovered($0.path, by: paths) }
        guard let tree = snapshot.tree else { return updated }
        updated.tree = pruned(tree, removing: paths, isRoot: true)
        if let tree = updated.tree {
            let totals = bucketTotals(in: tree)
            updated.buckets = totals
            updated.listedFiles = snapshot.listedFiles.filter { !isCovered($0.path, by: paths) }
            updated.apps = snapshot.apps.filter { !isCovered($0.path, by: paths) }
        }
        return updated
    }

    private static func isCovered(_ path: String, by paths: Set<String>) -> Bool {
        if paths.contains(path) { return true }
        return paths.contains { path.hasPrefix($0 + "/") }
    }

    private static func pruned(_ node: FileNode, removing paths: Set<String>, isRoot: Bool) -> FileNode? {
        if !isRoot, paths.contains(node.id) { return nil }
        guard var children = node.children else { return node }
        children = children.compactMap { pruned($0, removing: paths, isRoot: false) }
        let contribution = children.reduce(Int64(0)) { $0 + $1.contribution }
        var copy = node
        copy.children = children
        copy.contribution = contribution
        if node.kind == .directory {
            copy.apparentBytes = contribution
        }
        return copy
    }

    private static func bucketTotals(in tree: FileNode) -> [SizeBucket] {
        var counts: [SizeClass: Int] = [:]
        var bytes: [SizeClass: Int64] = [:]
        func walk(_ node: FileNode) {
            if node.kind == .file, !node.alreadyCounted {
                let kind = SizeClass.classify(node.apparentBytes)
                counts[kind, default: 0] += 1
                bytes[kind, default: 0] += node.apparentBytes
            }
            node.children?.forEach(walk)
        }
        walk(tree)
        return SizeClass.allCases.map { kind in
            SizeBucket(kind: kind, count: counts[kind] ?? 0, bytes: bytes[kind] ?? 0)
        }
    }
}
