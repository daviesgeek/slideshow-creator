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
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(6)
                    }
            }
            .buttonStyle(.plain)
            .onDrag(dragProvider)
            .help("Drag to reorder")

            Text(item.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            HStack(spacing: 8) {
                Button(item.isExcluded ? "Include (X)" : "Exclude (X)") {
                    onExcludeToggle(!item.isExcluded)
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer(minLength: 0)
            }

            if !shortcutFlags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(shortcutFlags.enumerated()), id: \.offset) { index, flag in
                            let enabled = item.flags.contains(flag)
                            Button {
                                onFlagToggle(flag, !enabled)
                            } label: {
                                Text("\(index + 1) \(flag)")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(enabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.18), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("Shortcut: \(index + 1)")
                        }
                    }
                }
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
