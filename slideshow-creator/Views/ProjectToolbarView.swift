import SwiftUI

struct ProjectToolbarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    Button("New Project", action: model.newProject)
                    Button("Open Project…", action: model.openProject)
                    Button("Save Project", action: model.saveProject)
                    Button("Save Project As…", action: model.saveProjectAs)
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 8)

                Button("Encode…", action: model.chooseOutputAndEncode)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.items.isEmpty || model.isEncoding)

                if model.isEncoding {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 8) {
                Button("Choose Photos Folder", action: model.pickFolder)
                    .buttonStyle(.bordered)
                Button("Choose Soundtrack Folder", action: model.pickSoundtrackFolder)
                    .buttonStyle(.bordered)
                Spacer()
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: model.isEncoding)
    }
}
