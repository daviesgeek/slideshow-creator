import SwiftUI
import AppKit

struct PhotoGridCellView: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let isDropTarget: Bool
    let thumbnailHeight: CGFloat
    let thumbnailMaxPixelSize: CGFloat
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onThumbnailTap: () -> Void
    let onFlagToggle: (String, Bool) -> Void
    let dragProvider: () -> NSItemProvider

    var body: some View {
        cellContent
            .modifier(PhotoGridSelectionInteractions(onSelect: onSelect, onThumbnailTap: onThumbnailTap))
            .background(cellBackground)
            .overlay(cellBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(item.isExcluded ? 0.45 : 1)
    }

    private var cellContent: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailView(url: item.url, maxPixelSize: thumbnailMaxPixelSize)
                    .frame(height: thumbnailHeight)
                    .frame(maxWidth: .infinity)
                    .onDrag(dragProvider)

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

            if isDropTarget {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 2)
            }
        }
    }

    private var cellBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
    }

    private var cellBorder: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.clear, lineWidth: 2)
    }
}

private struct PhotoGridSelectionInteractions: ViewModifier {
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onThumbnailTap: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture(count: 2, perform: onThumbnailTap)
            .onTapGesture(count: 1) {
                let modifiers = NSEvent.modifierFlags.intersection([.shift, .command])
                onSelect(modifiers)
            }
    }
}
