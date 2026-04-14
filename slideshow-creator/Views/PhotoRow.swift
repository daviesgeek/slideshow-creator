import SwiftUI

struct PhotoRow: View {
    let item: PhotoItem
    let availableFlags: [String]
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

                    Toggle(
                        "Exclude",
                        isOn: Binding(
                            get: { item.isExcluded },
                            set: { onExcludeToggle($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.caption)

                    if !availableFlags.isEmpty {
                        Menu("Flags") {
                            ForEach(availableFlags, id: \.self) { flag in
                                Toggle(
                                    isOn: Binding(
                                        get: { item.flags.contains(flag) },
                                        set: { isOn in onFlagToggle(flag, isOn) }
                                    )
                                ) {
                                    Text(flag)
                                }
                            }
                        }
                        .font(.caption)
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
        .padding(.vertical, 4)
    }
}
