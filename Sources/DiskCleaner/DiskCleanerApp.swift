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
    let bundled = [
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
        Bundle.main.url(forResource: "app-icon", withExtension: "png"),
        URL(fileURLWithPath: "app-icon.png"),
    ]
    for url in bundled.compactMap({ $0 }) {
        if let image = NSImage(contentsOf: url) {
            return image
        }
    }
    // Bundle.module traps when the Swift package resource bundle was not
    // copied into DiskCleaner.app. Only use it for a local swift build.
    guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
    let fromPackage = Bundle.module.url(forResource: "app-icon", withExtension: "png")
        ?? Bundle.module.url(forResource: "app-icon", withExtension: "png", subdirectory: "Resources")
    if let fromPackage, let image = NSImage(contentsOf: fromPackage) {
        return image
    }
    return nil
}
