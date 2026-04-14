import SwiftUI

struct PhotosPaneView: View {
    @ObservedObject var model: AppModel
    let onThumbnailTap: (PhotoItem) -> Void

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

            List {
                ForEach(model.items) { item in
                    PhotoRow(
                        item: item,
                        availableFlags: model.availableFlags,
                        onThumbnailTap: { onThumbnailTap(item) },
                        onExcludeToggle: { isExcluded in
                            model.setPhotoExcluded(isExcluded, for: item.id)
                        },
                        onFlagToggle: { flag, isEnabled in
                            model.setFlag(flag, enabled: isEnabled, for: item.id)
                        }
                    )
                }
                .onMove(perform: model.move)
            }
        }
    }
}
