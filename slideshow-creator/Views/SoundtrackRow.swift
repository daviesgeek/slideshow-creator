import SwiftUI

struct SoundtrackRow: View {
    let item: SoundtrackItem
    let dragProvider: (() -> NSItemProvider)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let dragProvider {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onDrag(dragProvider)
                    .help("Drag to reorder")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(1)

                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
