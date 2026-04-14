import SwiftUI

struct SoundtracksPaneView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Soundtracks")
                .font(.headline)

            if let soundtrackFolderURL = model.soundtrackFolderURL {
                Text(soundtrackFolderURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            List {
                ForEach(model.soundtracks) { soundtrack in
                    SoundtrackRow(item: soundtrack)
                }
                .onMove(perform: model.moveSoundtracks)
            }
        }
    }
}
