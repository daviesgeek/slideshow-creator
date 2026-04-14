import SwiftUI

struct PhotoRow: View {
    let item: PhotoItem
    let shortcutFlags: [String]
    let isSelected: Bool
    let onSelect: () -> Void
    let onThumbnailTap: () -> Void
    let onExcludeToggle: (Bool) -> Void
    let onFlagToggle: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onThumbnailTap) {
                ThumbnailView(url: item.url)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
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
        .onTapGesture(perform: onSelect)
    }
}
