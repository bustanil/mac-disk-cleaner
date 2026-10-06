import AppKit
import Combine
import DiskCleanerCore
import Foundation

enum ScanTarget: Hashable {
    case home
    case startup
}

enum SpacePage: Hashable {
    case folders
    case apps
    case sizes
}

enum ResultSection: Hashable {
    case space
    case largeFiles
    case junk
}

enum LargeFilePage: Hashable {
    case files
    case folders
}

enum DownloadAge: String, Hashable, CaseIterable {
    case days7 = "7"
    case days30 = "30"
    case days90 = "90"
    case custom = "custom"

    var label: String {
        switch self {
        case .days7: return "7 days"
        case .days30: return "30 days"
        case .days90: return "90 days"
        case .custom: return "Custom"
        }
    }
}

enum MinimumChoice: String, Hashable, CaseIterable {
    case mb50 = "50"
    case mb100 = "100"
    case mb500 = "500"
    case gb1 = "1000"
    case custom = "custom"

    var label: String {
        switch self {
        case .mb50: return "At least 50 MB"
        case .mb100: return "At least 100 MB"
        case .mb500: return "At least 500 MB"
        case .gb1: return "At least 1 GB"
        case .custom: return "Custom"
        }
    }
}

struct TrashCandidate: Identifiable, Equatable {
    var path: String
    var name: String
    var bytes: Int64
    var id: String { path }
}

/// Holds the latest progress sample. The walker writes it. The window reads it.
final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ScanProgress?

    func record(_ progress: ScanProgress) {
        lock.lock()
        value = progress
        lock.unlock()
    }

    func latest() -> ScanProgress? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@MainActor
final class ScanModel: ObservableObject {
    @Published private(set) var snapshot: ScanSnapshot?
    @Published private(set) var isScanning = false
    @Published private(set) var currentPath = ""
    @Published private(set) var itemsScanned = 0
    @Published private(set) var target: ScanTarget = .home
    @Published private(set) var liveVolume: VolumeSummary?
    @Published private(set) var startupDiskName: String
    @Published private(set) var fullDiskAccessGranted: Bool
    @Published var spacePage: SpacePage = .folders
    @Published var resultSection: ResultSection = .space
    @Published var largeFilePage: LargeFilePage = .files
    @Published var downloadAge: DownloadAge = .days30
    @Published var customDownloadAge = "30"
    @Published var junkSelection: Set<String> = []
    @Published var expandedJunk: Set<String> = [JunkCategory.userCaches.rawValue, JunkCategory.browser.rawValue]
    @Published var minimumChoice: MinimumChoice = .mb100
    @Published var customMinimumText = "100"
    @Published var largeFileQuery = ""
    @Published var selectedTrashPaths: Set<String> = []
    @Published private(set) var trashPreview: [TrashCandidate]?
    @Published private(set) var trashPreviewIsPermanent = false
    @Published private(set) var trashErrors: [String: String] = [:]
    @Published private(set) var isDeleting = false
    @Published private(set) var openSizeClass: SizeClass?

    private var generation = 0
    private var cancelFlag: CancelFlag?

    init() {
        let startup = VolumeSummaryReader.read(at: URL(fileURLWithPath: "/"))
        startupDiskName = startup?.name ?? "Macintosh HD"
        fullDiskAccessGranted = FullDiskAccess.isGranted()
    }

    func selectTarget(_ target: ScanTarget) {
        guard target != self.target else { return }
        cancelFlag?.cancel()
        generation += 1
        self.target = target
        isScanning = false
        snapshot = nil
        liveVolume = nil
        currentPath = ""
        itemsScanned = 0
        openSizeClass = nil
        clearTrashState()
    }

    func startScan() {
        cancelFlag?.cancel()
        let flag = CancelFlag()
        cancelFlag = flag
        generation += 1
        let generation = generation
        let root = rootURL
        isScanning = true
        snapshot = nil
        currentPath = ""
        itemsScanned = 0
        liveVolume = VolumeSummaryReader.read(at: root)
        openSizeClass = nil
        clearTrashState()
        refreshAccess()

        let runningBrowsers = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let home = FileManager.default.homeDirectoryForCurrentUser
        let box = ProgressBox()
        Task { @MainActor in
            while self.generation == generation && self.isScanning {
                if let progress = box.latest() {
                    self.currentPath = progress.currentPath
                    self.itemsScanned = progress.itemsScanned
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        Task.detached(priority: .userInitiated) {
            var snapshot = TreeWalker().walk(
                root: root,
                isCancelled: { flag.isCancelled },
                onProgress: { box.record($0) }
            )
            snapshot.volume = VolumeSummaryReader.read(at: root)
            if snapshot.failure == nil, !flag.isCancelled {
                let indexed = AppIndexer().index(
                    directories: AppIndexer.defaultDirectories(),
                    isCancelled: { flag.isCancelled },
                    onProgress: { box.record($0) }
                )
                snapshot.apps = indexed.apps
                if indexed.cancelled {
                    snapshot.status = .partial
                }
            }
            if !flag.isCancelled {
                let junk = JunkCatalog.collect(
                    roots: .standard(home: home),
                    runningBundleIDs: runningBrowsers
                )
                snapshot.junk = junk.items
                snapshot.partialDownloads = junk.partialDownloads
            }
            await self.finish(snapshot, generation: generation)
        }
    }

    func showSizeClass(_ kind: SizeClass) {
        guard kind.listsFiles else { return }
        openSizeClass = kind
        spacePage = .sizes
    }

    func closeSizeList() {
        openSizeClass = nil
    }

    func setTrashSelected(_ path: String, _ selected: Bool) {
        if selected {
            selectedTrashPaths.insert(path)
        } else {
            selectedTrashPaths.remove(path)
        }
    }

    var minimumBytes: Int64 {
        if minimumChoice == .custom {
            let mb = Int64(customMinimumText.trimmingCharacters(in: .whitespaces)) ?? 100
            return max(mb, 1) * 1_000_000
        }
        return (Int64(minimumChoice.rawValue) ?? 100) * 1_000_000
    }

    var downloadAgeDays: Int {
        if downloadAge == .custom {
            return max(1, Int(customDownloadAge.trimmingCharacters(in: .whitespaces)) ?? 30)
        }
        return Int(downloadAge.rawValue) ?? 30
    }

    func visibleJunk() -> [JunkItem] {
        JunkCatalog.visible(snapshot?.junk ?? [], downloadAgeDays: downloadAgeDays, now: Date())
    }

    func setDownloadAge(_ age: DownloadAge) {
        downloadAge = age
        pruneJunkSelection()
    }

    func setCustomDownloadAge(_ text: String) {
        customDownloadAge = text
        pruneJunkSelection()
    }

    func pruneJunkSelection() {
        let visible = Set(visibleJunk().map(\.id))
        junkSelection = junkSelection.intersection(visible)
    }

    func setJunkSelected(_ id: String, _ selected: Bool) {
        if selected {
            junkSelection.insert(id)
        } else {
            junkSelection.remove(id)
        }
    }

    func setJunkCategory(_ category: JunkCategory, selected: Bool) {
        for item in visibleJunk() where item.category == category && item.blockedReason == nil {
            setJunkSelected(item.id, selected)
        }
    }

    func toggleJunkCategory(_ category: JunkCategory) {
        expandedJunk.formSymmetricDifference([category.rawValue])
    }

    var movableJunk: [JunkItem] {
        visibleJunk().filter {
            junkSelection.contains($0.id) && $0.blockedReason == nil && $0.category != .trash
        }
    }

    var onlyTrashSelected: Bool {
        let selected = visibleJunk().filter { junkSelection.contains($0.id) && $0.blockedReason == nil }
        return !selected.isEmpty && selected.allSatisfy { $0.category == .trash }
    }

    var selectedTrashItems: [JunkItem] {
        visibleJunk().filter { junkSelection.contains($0.id) && $0.category == .trash }
    }

    func beginJunkTrash() {
        let items = movableJunk
        guard !items.isEmpty else { return }
        trashPreviewIsPermanent = false
        trashPreview = items.map { TrashCandidate(path: $0.path, name: $0.name, bytes: $0.bytes) }
    }

    func beginEmptyTrash() {
        let items = selectedTrashItems
        guard !items.isEmpty else { return }
        trashPreviewIsPermanent = true
        trashPreview = items.map { TrashCandidate(path: $0.path, name: $0.name, bytes: $0.bytes) }
    }

    func beginTrashPreview() {
        guard let tree = snapshot?.tree else { return }
        var byPath: [String: (name: String, bytes: Int64)] = [:]
        func walk(_ node: FileNode) {
            let bytes = node.kind == .directory ? node.contribution : node.apparentBytes
            byPath[node.id] = (node.name, bytes)
            node.children?.forEach(walk)
        }
        walk(tree)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundle = Bundle.main.bundleURL.path
        let items = selectedTrashPaths.sorted().compactMap { path -> TrashCandidate? in
            guard let info = byPath[path] else { return nil }
            if PathPolicy.denialReason(path: path, homePath: home, appBundlePath: bundle) != nil {
                return nil
            }
            return TrashCandidate(path: path, name: info.name, bytes: info.bytes)
        }
        guard !items.isEmpty else { return }
        trashPreviewIsPermanent = false
        trashPreview = items
    }

    func cancelTrashPreview() {
        trashPreview = nil
        trashPreviewIsPermanent = false
    }

    func confirmTrash() {
        guard let preview = trashPreview, !isDeleting else { return }
        let paths = preview.map(\.path)
        let permanent = trashPreviewIsPermanent
        trashPreview = nil
        trashPreviewIsPermanent = false
        isDeleting = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundle = Bundle.main.bundleURL.path
        let trashDirectory = home.appendingPathComponent(".Trash").path
        Task.detached(priority: .userInitiated) {
            let results: [TrashItemResult]
            if permanent {
                results = TrashDeletion.emptyTrash(paths: paths, trashDirectory: trashDirectory) { url in
                    try FileManager.default.removeItem(at: url)
                }
            } else {
                results = TrashDeletion.moveToTrash(
                    paths: paths,
                    homePath: home.path,
                    appBundlePath: bundle
                ) { url in
                    var resulting: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                }
            }
            await self.applyTrash(results)
        }
    }

    func denial(for path: String) -> String? {
        PathPolicy.denialReason(
            path: path,
            homePath: FileManager.default.homeDirectoryForCurrentUser.path,
            appBundlePath: Bundle.main.bundleURL.path
        )
    }

    func cancel() {
        cancelFlag?.cancel()
    }

    func refreshAccess() {
        fullDiskAccessGranted = FullDiskAccess.isGranted()
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }

    private var rootURL: URL {
        switch target {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .startup:
            return URL(fileURLWithPath: "/")
        }
    }

    private func finish(_ snapshot: ScanSnapshot, generation: Int) {
        guard generation == self.generation else { return }
        self.snapshot = snapshot
        self.liveVolume = snapshot.volume
        self.itemsScanned = snapshot.itemsScanned
        self.junkSelection = Set(snapshot.junk.filter(\.selectedByDefault).map(\.id))
        self.isScanning = false
    }

    private func applyTrash(_ results: [TrashItemResult]) {
        let succeeded = Set(results.filter(\.succeeded).map(\.path))
        var errors: [String: String] = [:]
        for result in results where !result.succeeded {
            errors[result.path] = result.reason ?? "Couldn't move this item to the Trash."
        }
        if let snapshot {
            self.snapshot = SnapshotEditing.removing(paths: succeeded, from: snapshot)
        }
        selectedTrashPaths.subtract(succeeded)
        junkSelection.subtract(succeeded)
        for path in succeeded {
            errors.removeValue(forKey: path)
        }
        trashErrors = errors
        isDeleting = false
    }

    private func clearTrashState() {
        selectedTrashPaths = []
        trashPreview = nil
        trashPreviewIsPermanent = false
        trashErrors = [:]
        junkSelection = []
        isDeleting = false
    }

    static let shared = ScanModel()
}
