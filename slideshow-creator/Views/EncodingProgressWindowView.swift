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
