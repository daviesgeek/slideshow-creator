import SwiftUI
import UniformTypeIdentifiers

struct SoundtracksPaneView: View {
    @ObservedObject var model: AppModel
    @State private var draggedSoundtrackID: SoundtrackItem.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Soundtracks")
                    .font(.headline)
                Spacer()
                Text("Drag rows to reorder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let soundtrackFolderURL = model.soundtrackFolderURL {
                Text(soundtrackFolderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            List {
                ForEach(model.soundtracks) { soundtrack in
                    SoundtrackRow(
                        item: soundtrack,
                        dragProvider: {
                            draggedSoundtrackID = soundtrack.id
                            return NSItemProvider(object: soundtrack.id.uuidString as NSString)
                        }
                    )
                    .onDrop(of: [UTType.text], delegate: SoundtrackReorderDropDelegate(
                        targetItemID: soundtrack.id,
                        model: model,
                        draggedItemID: $draggedSoundtrackID
                    ))
                }

                if !model.soundtracks.isEmpty {
                    Color.clear
                        .frame(height: 24)
                        .listRowSeparator(.hidden)
                        .onDrop(of: [UTType.text], delegate: SoundtrackReorderToEndDropDelegate(
                            model: model,
                            draggedItemID: $draggedSoundtrackID
                        ))
                }
            }
            .frame(minHeight: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SoundtrackReorderDropDelegate: DropDelegate {
    let targetItemID: SoundtrackItem.ID
    let model: AppModel
    @Binding var draggedItemID: SoundtrackItem.ID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID else { return }
        model.moveSoundtrack(withID: draggedItemID, before: targetItemID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}

private struct SoundtrackReorderToEndDropDelegate: DropDelegate {
    let model: AppModel
    @Binding var draggedItemID: SoundtrackItem.ID?

    func dropEntered(info: DropInfo) {
        guard let draggedItemID else { return }
        model.moveSoundtrackToEnd(withID: draggedItemID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}
