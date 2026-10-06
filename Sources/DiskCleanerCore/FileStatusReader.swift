import Darwin
import Foundation

package struct FileStatus: Equatable, Sendable {
    package var isDirectory: Bool
    package var isSymlink: Bool
    package var apparentBytes: Int64
    package var modified: Date
    package var device: UInt64
    package var inode: UInt64
}

package enum FileStatusReader {
    /// `followSymlink` uses `stat`. The walker uses `lstat` for children so a link is not walked.
    package static func read(path: String, followSymlink: Bool) -> FileStatus? {
        var info = stat()
        let result = followSymlink ? stat(path, &info) : lstat(path, &info)
        guard result == 0 else { return nil }
        let type = info.st_mode & S_IFMT
        return FileStatus(
            isDirectory: type == S_IFDIR,
            isSymlink: type == S_IFLNK,
            apparentBytes: Int64(info.st_size),
            modified: Date(
                timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                    + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
            ),
            device: UInt64(info.st_dev),
            inode: info.st_ino
        )
    }
}
