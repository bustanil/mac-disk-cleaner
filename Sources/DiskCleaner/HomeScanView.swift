import AppKit
import DiskCleanerCore
import SwiftUI

struct HomeScanView: View {
    @ObservedObject var model: ScanModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controlBar
                if !model.fullDiskAccessGranted {
                    accessBanner
                    Divider()
                }
                if showsSummary {
                    summary
                    Divider()
                }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Disk Cleaner")
            .toolbar { toolbar }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { model.refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshAccess()
        }
        .sheet(isPresented: Binding(
            get: { model.trashPreview != nil },
            set: { if !$0 { model.cancelTrashPreview() } }
        )) {
            TrashConfirmationSheet(model: model)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if model.isScanning {
                Button("Cancel", role: .cancel) {
                    model.cancel()
                }
            } else {
                Button("Scan") {
                    model.startScan()
                }
                .keyboardShortcut("r")
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var controlBar: some View {
        HStack {
            Picker("Scan", selection: Binding(
                get: { model.target },
                set: { model.selectTarget($0) }
            )) {
                Text("Home folder").tag(ScanTarget.home)
                Text(model.startupDiskName).tag(ScanTarget.startup)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .disabled(model.isScanning)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var accessBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.orange)
            Text(accessMessage)
                .font(.subheadline)
            Spacer(minLength: 12)
            Button("Open Full Disk Access") {
                model.openFullDiskAccessSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var accessMessage: String {
        if let skipped = model.snapshot?.skipped, skipped > 0 {
            return "Full Disk Access is off. \(skipped.formatted()) locations skipped."
        }
        return "Full Disk Access is off. Some locations will be skipped."
    }

    private var showsSummary: Bool {
        model.isScanning || model.snapshot != nil
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaryTitle)
                .font(.headline)
            HStack(spacing: 24) {
                metric("Used", model.liveVolume?.usedBytes ?? model.snapshot?.volume?.usedBytes)
                metric("Free", model.liveVolume?.freeBytes ?? model.snapshot?.volume?.freeBytes)
                metric("Purgeable", model.liveVolume?.purgeableBytes ?? model.snapshot?.volume?.purgeableBytes)
                metric("Scanned", model.isScanning ? nil : model.snapshot?.tree?.contribution)
                countMetric("Skipped", model.isScanning ? nil : model.snapshot?.skipped)
            }
            if model.isScanning {
                Text(shownPath(model.currentPath))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(model.itemsScanned.formatted()) items · a scan does not delete files")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.small)
            } else if model.snapshot?.status == .partial {
                Label("Partial scan", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryTitle: String {
        if model.target == .startup {
            return model.startupDiskName
        }
        return "Home folder"
    }

    @ViewBuilder
    private var content: some View {
        if let failure = model.snapshot?.failure {
            ContentUnavailableView {
                Label("Couldn’t scan", systemImage: "folder.badge.questionmark")
            } description: {
                Text(failure)
            } actions: {
                Button("Scan") { model.startScan() }
            }
        } else if model.isScanning {
            Color.clear
        } else if model.snapshot?.tree != nil {
            VStack(spacing: 0) {
                sectionPicker
                if model.resultSection == .largeFiles {
                    LargeFilesPane(model: model)
                } else if model.resultSection == .junk {
                    JunkPane(model: model)
                } else {
                    spacePicker
                    Divider()
                    spaceBody
                }
            }
        } else {
            ContentUnavailableView {
                Label(model.target == .startup ? model.startupDiskName : "Home folder", systemImage: "folder")
            } description: {
                Text("Scan to see which folders use space. A scan does not delete files.")
            } actions: {
                Button("Scan") { model.startScan() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $model.resultSection) {
            Text("Space").tag(ResultSection.space)
            Text("Large files").tag(ResultSection.largeFiles)
            Text("Junk").tag(ResultSection.junk)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
                .frame(maxWidth: 420)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spacePicker: some View {
        Picker("Breakdown", selection: $model.spacePage) {
            Text("Folder").tag(SpacePage.folders)
            Text("App").tag(SpacePage.apps)
            Text("File size").tag(SpacePage.sizes)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var spaceBody: some View {
        switch model.spacePage {
        case .folders:
            folderList
        case .apps:
            appList
        case .sizes:
            if let kind = model.openSizeClass {
                sizeFileList(kind)
            } else {
                bucketList
            }
        }
    }

    @ViewBuilder
    private var folderList: some View {
        if let tree = model.snapshot?.tree, let children = tree.children {
            List {
                OutlineGroup(children, children: \.children) { node in
                    row(node, total: tree.contribution)
                }
            }
            .listStyle(.inset)
        }
    }

    private var appList: some View {
        let apps = model.snapshot?.apps ?? []
        return VStack(alignment: .leading, spacing: 0) {
            Text("Bundle size only. Support files stay in the folder list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            if apps.isEmpty {
                Text("No application bundles in /Applications, /System/Applications, or your Applications folder.")
                    .foregroundStyle(.secondary)
                    .padding(16)
                Spacer()
            } else {
                List(apps) { app in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.location)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(ByteFormat.string(from: app.bytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Reveal") { reveal(app.path) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var bucketList: some View {
        let buckets = model.snapshot?.buckets ?? []
        let total = model.snapshot?.tree?.contribution ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("Small files stay as a total. Medium, Large, and Huge open a file list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            List(buckets) { bucket in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bucket.kind.title)
                        Text(bucket.kind.range)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(bucket.count.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(ByteFormat.string(from: bucket.bytes))
                        .monospacedDigit()
                        .frame(width: 72, alignment: .trailing)
                    Text("\(ByteFormat.percent(part: bucket.bytes, total: total))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                    if bucket.kind.listsFiles {
                        Button("Show files") { model.showSizeClass(bucket.kind) }
                            .disabled(bucket.count == 0)
                    } else {
                        Text("Total only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func sizeFileList(_ kind: SizeClass) -> some View {
        let files = (model.snapshot?.listedFiles ?? []).filter { $0.kind == kind }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("All sizes") { model.closeSizeList() }
                Text("\(kind.title) · \(kind.range)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            List(files) { file in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.name)
                            .lineLimit(1)
                        Text(file.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text(ByteFormat.string(from: file.bytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Reveal") { reveal(file.path) }
                }
            }
            .listStyle(.inset)
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func metric(_ title: String, _ bytes: Int64?) -> some View {
        labeled(title, bytes.map { ByteFormat.string(from: $0) } ?? "…")
    }

    private func countMetric(_ title: String, _ count: Int?) -> some View {
        labeled(title, count?.formatted() ?? "…")
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }

    private func row(_ node: FileNode, total: Int64) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: node))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(node.name)
                    .lineLimit(1)
                if let note = note(for: node) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if node.sizeIsKnown {
                Text(ByteFormat.string(from: node.displayBytes))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                Text("\(ByteFormat.percent(part: node.contribution, total: total))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func icon(for node: FileNode) -> String {
        switch node.kind {
        case .directory, .otherVolume:
            return "folder"
        case .symlink:
            return "link"
        case .file:
            return "doc"
        }
    }

    private func note(for node: FileNode) -> String? {
        if node.alreadyCounted { return "Already counted" }
        if node.unreadable { return "Not readable" }
        if node.kind == .otherVolume { return "Other volume" }
        return nil
    }

    private func shownPath(_ path: String) -> String {
        guard !path.isEmpty else { return summaryTitle }
        if path == "/" { return model.startupDiskName }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path == home { return home }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
