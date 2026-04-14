import SwiftUI

struct EncodingProgressWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var progressPercentText: String {
        "\(Int((model.encodingProgress * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Encoding Progress")
                .font(.headline)

            ProgressView(value: model.encodingProgress, total: 1)
                .progressViewStyle(.linear)

            Text(progressPercentText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(model.encodingStatusLine)
                .font(.callout)

            HStack(spacing: 16) {
                Label(model.encodingElapsedText, systemImage: "clock")
                Label(model.encodingRemainingText, systemImage: "hourglass")
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("FFmpeg Log")
                    .font(.subheadline.weight(.semibold))

                ScrollView {
                    Text(model.encodingLogText.isEmpty ? "Waiting for ffmpeg output…" : model.encodingLogText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 140, maxHeight: 200)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            HStack {
                Spacer()

                if model.isEncoding {
                    Button("Cancel") {
                        model.cancelEncoding()
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("Close") {
                        model.closeEncodingProgressWindow()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420)
        .onDisappear {
            model.closeEncodingProgressWindow()
        }
    }
}
