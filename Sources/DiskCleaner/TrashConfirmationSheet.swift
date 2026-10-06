import DiskCleanerCore
import SwiftUI

struct TrashConfirmationSheet: View {
    @ObservedObject var model: ScanModel

    var body: some View {
        let items = model.trashPreview ?? []
        let permanent = model.trashPreviewIsPermanent
        VStack(alignment: .leading, spacing: 12) {
            Text(permanent ? "Delete permanently" : "Move to Trash")
                .font(.title2)
            Text(permanent
                ? "These items cannot be restored from the Trash."
                : "These items will go to the Trash. You can put them back.")
            Text("\(items.count) · \(ByteFormat.string(from: items.reduce(0) { $0 + $1.bytes }))")
                .foregroundStyle(.secondary)
            List(items) { item in
                HStack {
                    Text(item.name)
                        .lineLimit(1)
                    Spacer()
                    Text(ByteFormat.string(from: item.bytes))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 120, maxHeight: 240)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelTrashPreview() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isDeleting)
                Button(permanent ? "Delete Permanently" : "Move to Trash") {
                    model.confirmTrash()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.isDeleting)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
