import Foundation

package struct VolumeSummary: Equatable, Sendable {
    package var name: String
    package var usedBytes: Int64
    package var freeBytes: Int64
    package var purgeableBytes: Int64
    package var totalBytes: Int64
}

package enum VolumeSummaryReader {
    /// Free includes purgeable space. Used is what remains after that free space.
    package static func summarize(
        name: String,
        totalBytes: Int64,
        availableBytes: Int64,
        importantBytes: Int64
    ) -> VolumeSummary {
        let free = max(importantBytes, availableBytes, 0)
        let purgeable = max(0, free - max(availableBytes, 0))
        let used = max(0, totalBytes - free)
        return VolumeSummary(
            name: name,
            usedBytes: used,
            freeBytes: free,
            purgeableBytes: purgeable,
            totalBytes: max(totalBytes, 0)
        )
    }

    package static func read(at root: URL) -> VolumeSummary? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? root.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else {
            return nil
        }
        let available = values.volumeAvailableCapacity.map(Self.bytes) ?? 0
        let important = values.volumeAvailableCapacityForImportantUsage.map(Self.bytes) ?? available
        let name = values.volumeName?.isEmpty == false ? values.volumeName! : "Macintosh HD"
        return summarize(
            name: name,
            totalBytes: Self.bytes(total),
            availableBytes: available,
            importantBytes: important
        )
    }

    private static func bytes<T: BinaryInteger>(_ value: T) -> Int64 {
        Int64(truncatingIfNeeded: value)
    }
}
