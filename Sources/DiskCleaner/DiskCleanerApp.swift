import AppKit
import SwiftUI

@main
struct DiskCleanerApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HomeScanView(model: ScanModel.shared)
        }
        .defaultSize(width: 760, height: 560)
    }
}
