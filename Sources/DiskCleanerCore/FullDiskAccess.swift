import Foundation

package enum FullDiskAccess {
    package static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
    )!

    /// The TCC database is readable only after the user grants Full Disk Access.
    package static func isGranted() -> Bool {
        FileManager.default.isReadableFile(
            atPath: "/Library/Application Support/com.apple.TCC/TCC.db"
        )
    }
}
