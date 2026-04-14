import SwiftUI

struct LabeledIntField: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            TextField(label, value: $value, format: .number)
                .frame(width: 70)
                .textFieldStyle(.roundedBorder)
        }
    }
}
