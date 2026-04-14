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

            Stepper(
                "Seconds/photo: \(model.secondsPerImage, specifier: "%.1f")",
                value: $model.secondsPerImage,
                in: 1...30,
                step: 0.5
            )
            .frame(width: 180)

            LabeledIntField(label: "W", value: $model.width)
            LabeledIntField(label: "H", value: $model.height)
            LabeledIntField(label: "FPS", value: $model.fps)
        }
    }
}
