import Foundation

package enum SizeClass: String, CaseIterable, Equatable, Hashable, Sendable {
    case small
    case medium
    case large
    case huge

    package static let mediumMinimum: Int64 = 10_000_000
    package static let largeMinimum: Int64 = 100_000_000
    package static let hugeMinimum: Int64 = 1_000_000_000

    package static func classify(_ bytes: Int64) -> SizeClass {
        if bytes >= hugeMinimum { return .huge }
        if bytes >= largeMinimum { return .large }
        if bytes >= mediumMinimum { return .medium }
        return .small
    }

    package var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .huge: return "Huge"
        }
    }

    package var range: String {
        switch self {
        case .small: return "Under 10 MB"
        case .medium: return "10 MB – 100 MB"
        case .large: return "100 MB – 1 GB"
        case .huge: return "1 GB and up"
        }
    }

    /// Small files stay as a total. The other buckets open a file list.
    package var listsFiles: Bool {
        self != .small
    }
}

package struct SizeBucket: Equatable, Sendable, Identifiable {
    package var kind: SizeClass
    package var count: Int
    package var bytes: Int64
    package var id: SizeClass { kind }
}

package struct ListedFile: Equatable, Sendable, Identifiable {
    package var id: String
    package var name: String
    package var path: String
    package var bytes: Int64
    package var kind: SizeClass
    package var fileKind: String
    package var modified: Date

    package init(
        id: String,
        name: String,
        path: String,
        bytes: Int64,
        kind: SizeClass,
        fileKind: String,
        modified: Date
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bytes = bytes
        self.kind = kind
        self.fileKind = fileKind
        self.modified = modified
    }
}

package struct AppRecord: Equatable, Sendable, Identifiable {
    package var id: String
    package var name: String
    package var path: String
    package var location: String
    package var bytes: Int64
}
