import SwiftUI

struct ProjectToolbarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            Button("New Project", action: model.newProject)
            Button("Open Project…", action: model.openProject)
            Button("Save Project", action: model.saveProject)
            Button("Save Project As…", action: model.saveProjectAs)

            Divider()

            Button("Choose Photos Folder", action: model.pickFolder)
            Button("Choose Soundtrack Folder", action: model.pickSoundtrackFolder)

            Button("Encode…", action: model.chooseOutputAndEncode)
                .disabled(model.items.isEmpty || model.isEncoding)

            Spacer()

            if model.isEncoding {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}
