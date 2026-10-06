import DiskCleanerCore
import SwiftUI

struct JunkPane: View {
    @ObservedObject var model: ScanModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Junk for \(homeName)")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                    Text("Selected caches, logs, browser cache, and old downloads go to the Trash. Trash itself stays until you empty it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    ForEach(JunkCategory.allCases, id: \.rawValue) { category in
                        categoryBlock(category)
                        Divider()
                    }
                }
            }
            footer
        }
    }

    private var homeName: String {
        FileManager.default.homeDirectoryForCurrentUser.lastPathComponent
    }

    private func categoryBlock(_ category: JunkCategory) -> some View {
        let items = model.visibleJunk().filter { $0.category == category }
        let selectable = items.filter { $0.blockedReason == nil }
        let allOn = !selectable.isEmpty && selectable.allSatisfy { model.junkSelection.contains($0.id) }
        let open = model.expandedJunk.contains(category.rawValue)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    model.toggleJunkCategory(category)
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .frame(width: 12)
                }
                .buttonStyle(.borderless)
                Toggle("", isOn: Binding(
                    get: { allOn },
                    set: { model.setJunkCategory(category, selected: $0) }
                ))
                .labelsHidden()
                .disabled(selectable.isEmpty || model.isDeleting)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .fontWeight(.semibold)
                    Text(category.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(items.count) · \(ByteFormat.string(from: items.reduce(0) { $0 + $1.bytes }))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if open {
                if category == .downloads {
                    HStack(spacing: 8) {
                        Text("Older than")
                            .font(.subheadline)
                        Picker("Age", selection: Binding(
                            get: { model.downloadAge },
                            set: { model.setDownloadAge($0) }
                        )) {
                            ForEach(DownloadAge.allCases, id: \.self) { age in
                                Text(age.label).tag(age)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 120)
                        if model.downloadAge == .custom {
                            TextField("Days", text: Binding(
                                get: { model.customDownloadAge },
                                set: { model.setCustomDownloadAge($0) }
                            ))
                            .frame(width: 64)
                        }
                        if (model.snapshot?.partialDownloads ?? 0) > 0 {
                            Text("\(model.snapshot?.partialDownloads ?? 0) partial downloads stay.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.leading, 28)
                }
                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Toggle("", isOn: Binding(
                            get: { item.blockedReason == nil && model.junkSelection.contains(item.id) },
                            set: { model.setJunkSelected(item.id, $0) }
                        ))
                        .labelsHidden()
                        .disabled(item.blockedReason != nil || model.isDeleting)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.blockedReason ?? item.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(ByteFormat.string(from: item.bytes))
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                    .padding(.leading, 28)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        let acted = model.onlyTrashSelected ? model.selectedTrashItems : model.movableJunk
        return HStack {
            Text("\(acted.count) items · \(ByteFormat.string(from: acted.reduce(0) { $0 + $1.bytes })) selected")
                .font(.headline)
            Spacer()
            Button(model.onlyTrashSelected ? "Empty Trash" : "Move to Trash") {
                if model.onlyTrashSelected {
                    model.beginEmptyTrash()
                } else {
                    model.beginJunkTrash()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(acted.isEmpty || model.isDeleting || model.trashPreview != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
