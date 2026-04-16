import SwiftUI
import AppKit

struct PhotoRow: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let dragProvider: (() -> NSItemProvider)?
    let onActivate: () -> Void
    let onExcludeToggle: (Bool) -> Void
    let onFlagToggle: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let dragProvider {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 20)
                    .contentShape(Rectangle())
                    .onDrag(dragProvider)
                    .help("Drag to reorder")
            }

            ThumbnailView(url: item.url, maxPixelSize: 72)
                .frame(width: 72, height: 72)
                .help("Open fullscreen preview")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .lineLimit(1)

                    Button(item.isExcluded ? "Include (X)" : "Exclude (X)") {
                        onExcludeToggle(!item.isExcluded)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Shortcut: X")

                    if !shortcutFlags.isEmpty {
                        PhotoFlagControlsView(
                            shortcutFlags: shortcutFlags,
                            selectedFlags: item.flags,
                            visibleFlagLimit: 4,
                            onFlagToggle: onFlagToggle
                        )
                    }
                }

                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !item.flags.isEmpty {
                    Text(item.flags.sorted().joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .opacity(item.isExcluded ? 0.45 : 1)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .modifier(PhotoRowActivationInteractions(isSelected: isSelected, onActivate: onActivate))
    }
}

private struct PhotoRowActivationInteractions: ViewModifier {
    let isSelected: Bool
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 1) {
                let clickCount = NSApp.currentEvent?.clickCount ?? 1
                let modifiers = (NSApp.currentEvent?.modifierFlags ?? [])
                    .intersection([.shift, .command])

                guard modifiers.isEmpty else { return }

                if clickCount == 2 || isSelected {
                    onActivate()
                }
            }
    }
}
