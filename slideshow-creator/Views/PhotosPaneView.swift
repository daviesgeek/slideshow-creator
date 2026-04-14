import SwiftUI

struct PhotosPaneView: View {
    @ObservedObject var model: AppModel
    let onThumbnailTap: (PhotoItem) -> Void

    private func keyEquivalent(for number: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(number)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photos")
                .font(.headline)

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
                }
                .onMove(perform: model.move)
            }

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
    }
}
