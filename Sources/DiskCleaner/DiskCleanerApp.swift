import AppKit
import SwiftUI

@main
struct DiskCleanerApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let image = appIcon() {
            NSApplication.shared.applicationIconImage = image
        }
        NSApplication.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            HomeScanView(model: ScanModel.shared)
        }
        .defaultSize(width: 760, height: 560)
    }
}

private func appIcon() -> NSImage? {
    let bundled = Bundle.module.url(forResource: "app-icon", withExtension: "png")
        ?? Bundle.module.url(forResource: "app-icon", withExtension: "png", subdirectory: "Resources")
    let candidates = [
        bundled,
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
        URL(fileURLWithPath: "app-icon.png"),
    ]
    for url in candidates.compactMap({ $0 }) {
        if let image = NSImage(contentsOf: url) {
            return image
        }
    }
    return nil
}
