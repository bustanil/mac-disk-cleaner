import AppKit
import DiskCleanerCore
import SwiftUI

struct LargeFilesPane: View {
    @ObservedObject var model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            controls
            if model.largeFilePage == .files {
                fileList
            } else {
                folderList
            }
            footer
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("List", selection: $model.largeFilePage) {
                    Text("Files").tag(LargeFilePage.files)
                    Text("Folders").tag(LargeFilePage.folders)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Picker("Minimum", selection: $model.minimumChoice) {
                    ForEach(MinimumChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .frame(maxWidth: 180)
                if model.minimumChoice == .custom {
                    TextField("MB", text: $model.customMinimumText)
                        .frame(width: 64)
                }
                TextField("Search by name", text: $model.largeFileQuery)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Files under 10 MB stay in the size buckets as a total. Move to Trash waits for a preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var fileList: some View {
        let files = LargeFileQuery.files(
            model.snapshot?.listedFiles ?? [],
            minimumBytes: model.minimumBytes,
            nameQuery: model.largeFileQuery
        )
        return List(files) { file in
            row(
                path: file.path,
                name: file.name,
                detail: "\(file.fileKind) · \(file.modified.formatted(date: .abbreviated, time: .omitted))",
                pathLine: file.path,
                bytes: file.bytes
            )
        }
        .listStyle(.inset)
    }

    private var folderList: some View {
        var folders: [FileNode] = []
        if let tree = model.snapshot?.tree {
            folders = LargeFileQuery.folders(
                in: tree,
                minimumBytes: model.minimumBytes,
                nameQuery: model.largeFileQuery
            )
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(folders.count) of the 50 largest folders at or above the size minimum.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            List(folders) { folder in
                DisclosureGroup {
                    if let children = folder.children {
                        ForEach(children) { child in
                            HStack {
                                Text(child.name)
                                    .lineLimit(1)
                                Spacer()
                                Text(ByteFormat.string(from: child.displayBytes))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } label: {
                    row(
                        path: folder.id,
                        name: folder.name,
                        detail: nil,
                        pathLine: folder.id,
                        bytes: folder.contribution
                    )
                }
            }
            .listStyle(.inset)
        }
    }

    private func row(
        path: String,
        name: String,
        detail: String?,
        pathLine: String,
        bytes: Int64
    ) -> some View {
        let denial = model.denial(for: path)
        return HStack(spacing: 12) {
            if denial == nil {
                Toggle("", isOn: Binding(
                    get: { model.selectedTrashPaths.contains(path) },
                    set: { model.setTrashSelected(path, $0) }
                ))
                .labelsHidden()
                .disabled(model.isDeleting)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text(pathLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let denial {
                    Text(denial)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let error = model.trashErrors[path] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(ByteFormat.string(from: bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Reveal") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
            .disabled(model.isDeleting)
        }
    }

    private var footer: some View {
        let selected = model.selectedTrashPaths
        let bytes = selectedBytes(selected)
        return HStack {
            Text("\(selected.count) selected · \(ByteFormat.string(from: bytes))")
                .font(.headline)
            Spacer()
            Button("Move to Trash") {
                model.beginTrashPreview()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty || model.isDeleting || model.trashPreview != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func selectedBytes(_ paths: Set<String>) -> Int64 {
        guard let tree = model.snapshot?.tree else { return 0 }
        var byPath: [String: Int64] = [:]
        func walk(_ node: FileNode) {
            let bytes = node.kind == .directory ? node.contribution : node.apparentBytes
            byPath[node.id] = bytes
            node.children?.forEach(walk)
        }
        walk(tree)
        return paths.reduce(0) { $0 + (byPath[$1] ?? 0) }
    }
}
