import SwiftUI

struct PhotoGridCellView: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let isDropTarget: Bool
    let thumbnailHeight: CGFloat
    let thumbnailMaxPixelSize: CGFloat
    let onSelect: () -> Void
    let onThumbnailTap: () -> Void
    let onExcludeToggle: (Bool) -> Void
    let onFlagToggle: (String, Bool) -> Void
    let dragProvider: () -> NSItemProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onThumbnailTap) {
                ThumbnailView(url: item.url, maxPixelSize: thumbnailMaxPixelSize)
                    .frame(height: thumbnailHeight)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .onDrag(dragProvider)
            .help("Drag to reorder")

            Text(item.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            if !shortcutFlags.isEmpty {
                PhotoFlagControlsView(
                    shortcutFlags: shortcutFlags,
                    selectedFlags: item.flags,
                    visibleFlagLimit: 3,
                    onFlagToggle: onFlagToggle
                )
            }
        }
        .padding(10)
        .background(cardBackground)
        .overlay(alignment: .leading) {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(item.isExcluded ? 0.45 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onSelect)
    }

    private var cardBackground: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.12))
        }
        return AnyShapeStyle(Color.primary.opacity(0.04))
    }
}
