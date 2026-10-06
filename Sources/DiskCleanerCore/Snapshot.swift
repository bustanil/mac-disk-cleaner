import Foundation

package enum ScanStatus: String, Equatable, Sendable {
    case complete
    case partial
}

package enum NodeKind: Equatable, Sendable {
    case directory
    case file
    case symlink
    case otherVolume
}

package struct FileNode: Identifiable, Equatable, Sendable {
    package var id: String
    package var name: String
    package var apparentBytes: Int64
    package var contribution: Int64
    package var kind: NodeKind
    package var alreadyCounted: Bool
    package var unreadable: Bool
    package var children: [FileNode]?

    package init(
        id: String,
        name: String,
        apparentBytes: Int64,
        contribution: Int64,
        kind: NodeKind,
        alreadyCounted: Bool,
        unreadable: Bool,
        children: [FileNode]?
    ) {
        self.id = id
        self.name = name
        self.apparentBytes = apparentBytes
        self.contribution = contribution
        self.kind = kind
        self.alreadyCounted = alreadyCounted
        self.unreadable = unreadable
        self.children = children
    }

    /// Size shown on the row. Folders show the rolled-up total.
    package var displayBytes: Int64 {
        switch kind {
        case .directory:
            return contribution
        case .file, .symlink:
            return apparentBytes
        case .otherVolume:
            return 0
        }
    }

    package var sizeIsKnown: Bool {
        !unreadable && kind != .otherVolume
    }
}

package struct ScanProgress: Equatable, Sendable {
    package var currentPath: String
    package var itemsScanned: Int
}

package struct ScanSnapshot: Equatable, Sendable {
    package var rootPath: String
    package var status: ScanStatus
    package var itemsScanned: Int
    package var skipped: Int
    package var tree: FileNode?
    package var failure: String?
    package var volume: VolumeSummary?
    package var buckets: [SizeBucket] = []
    package var listedFiles: [ListedFile] = []
    package var apps: [AppRecord] = []
    package var junk: [JunkItem] = []
    package var partialDownloads = 0
}
