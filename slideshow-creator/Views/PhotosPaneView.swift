import SwiftUI
import UniformTypeIdentifiers

struct PhotosPaneView: View {
    @ObservedObject var model: AppModel
    let onThumbnailTap: (PhotoItem) -> Void
    @State private var draggedPhotoID: PhotoItem.ID?

    private func keyEquivalent(for number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(number)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos")
                    .font(.headline)
                Spacer()
                Text("Drag rows to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let folderURL = model.folderURL {
                Text(folderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            List(selection: Binding(get: {
                model.selectedPhotoID
            }, set: { newValue in
                model.selectPhoto(newValue)
            })) {
                ForEach(model.items) { item in
                    PhotoRow(
                        item: item,
                        shortcutFlags: model.shortcutFlags,
                        isSelected: model.selectedPhotoID == item.id,
                        dragProvider: {
                            draggedPhotoID = item.id
                            return NSItemProvider(object: item.id.uuidString as NSString)
                        },
                        onSelect: { model.selectPhoto(item.id) },
                        onThumbnailTap: {
                            model.selectPhoto(item.id)
                            onThumbnailTap(item)
                        },
                        onExcludeToggle: { isExcluded in
                            model.setPhotoExcluded(isExcluded, for: item.id)
                        },
                        onFlagToggle: { flag, isEnabled in
                            model.setFlag(flag, enabled: isEnabled, for: item.id)
                        }
                    )
                    .tag(item.id)
                    .onDrop(of: [UTType.text], delegate: PhotoReorderDropDelegate(
                        targetItemID: item.id,
                        model: model,
                        draggedItemID: $draggedPhotoID
                    ))
                }
                if !model.items.isEmpty {
                    Color.clear
                        .frame(height: 24)
                        .listRowSeparator(.hidden)
                        .onDrop(of: [UTType.text], delegate: PhotoReorderToEndDropDelegate(
                            model: model,
                            draggedItemID: $draggedPhotoID
                        ))
                }
            }
            .frame(minHeight: 260)

            HStack(spacing: 0) {
                Button("Toggle Exclude") {
                    model.toggleExcludeForSelectedPhoto()
                }
                .keyboardShortcut("x", modifiers: [])
                .opacity(0.001)
                .frame(width: 0, height: 0)

                ForEach(1...9, id: \.self) { number in
                    Button("Toggle Flag \(number)") {
                        model.toggleShortcutFlagForSelectedPhoto(number)
                    }
                    .keyboardShortcut(keyEquivalent(for: number), modifiers: [])
                    .opacity(0.001)
                    .frame(width: 0, height: 0)
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PhotoReorderDropDelegate: DropDelegate {
    let targetItemID: PhotoItem.ID
    let model: AppModel
    @Binding var draggedItemID: PhotoItem.ID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID else { return }
        model.movePhoto(withID: draggedItemID, before: targetItemID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}

private struct PhotoReorderToEndDropDelegate: DropDelegate {
    let model: AppModel
    @Binding var draggedItemID: PhotoItem.ID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID else { return }
        model.movePhotoToEnd(withID: draggedItemID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}
