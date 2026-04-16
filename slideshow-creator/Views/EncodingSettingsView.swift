import SwiftUI

struct EncodingSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            TextField("FFmpeg path", text: $model.ffmpegPath)
                .onSubmit {
                    model.validateFFmpegPath()
                }

            Button("Validate FFmpeg") {
                model.validateFFmpegPath()
            }

            SecondsPerPhotoField(
                label: "Seconds/photo:",
                value: $model.secondsPerImage
            )

            Picker("Default transition", selection: $model.defaultTransitionToNext) {
                ForEach(PhotoTransitionStyle.allCases) { transition in
                    Text(transition.label).tag(transition)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            SecondsPerPhotoField(
                label: "Default trans sec:",
                value: $model.defaultTransitionDurationToNext
            )

            Picker("Mode", selection: $model.encodeSpeedMode) {
                ForEach(EncodeSpeedMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            LabeledIntField(label: "W", value: $model.width)
            LabeledIntField(label: "H", value: $model.height)
            LabeledIntField(label: "FPS", value: $model.fps)
        }
    }
}
