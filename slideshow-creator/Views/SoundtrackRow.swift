import SwiftUI

struct SoundtrackRow: View {
    let item: SoundtrackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .lineLimit(1)

            Text(item.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
