import SwiftUI

/// A control for entering "seconds per photo" values with freeform text input
/// and increment/decrement buttons.
///
/// - Supports values from 0.01 to 999.99 with two decimal place precision
/// - Step increment of 0.5 when using the +/- buttons
/// - Freeform text input that accepts decimal values
struct SecondsPerPhotoField: View {
    let label: String
    @Binding var value: Double

    /// Text editing state for the input field
    @State private var textValue: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    /// Minimum allowed value
    private let minValue: Double = 0.01

    /// Maximum allowed value
    private let maxValue: Double = 999.99

    /// Step increment for +/- buttons
    private let stepIncrement: Double = 0.5

    /// Number formatter for display and parsing
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ""
        return formatter
    }()

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 4) {
                Button(action: decrementValue) {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(value <= minValue)
                .controlSize(.small)

                TextField(label, text: $textValue)
                    .frame(width: 70)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        commitValue()
                    }
                    .onChange(of: isTextFieldFocused) { _, isFocused in
                        isEditing = isFocused
                        if !isFocused {
                            commitValue()
                        }
                    }

                Button(action: incrementValue) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(value >= maxValue)
                .controlSize(.small)
            }

            Text("sec")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .onAppear {
            textValue = formatValue(value)
        }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                textValue = formatValue(newValue)
            }
        }
    }

    /// Formats a double value for display in the text field
    private func formatValue(_ val: Double) -> String {
        numberFormatter.string(from: NSNumber(value: val)) ?? String(format: "%.2f", val)
    }

    /// Commits the current text value and validates it
    private func commitValue() {
        isEditing = false

        let cleanedText = textValue.replacingOccurrences(of: ",", with: ".")
        guard let parsedValue = Double(cleanedText) else {
            // Revert to current binding value
            textValue = formatValue(value)
            return
        }

        // Clamp to valid range
        let clampedValue = min(max(parsedValue, minValue), maxValue)

        // Round to two decimal places
        let roundedValue = (clampedValue * 100).rounded() / 100

        // Update binding
        value = roundedValue

        // Update text field with formatted value
        textValue = formatValue(roundedValue)
    }

    /// Decrements the value by the step increment
    private func decrementValue() {
        let newValue = value - stepIncrement
        value = min(max(newValue, minValue), maxValue)
        textValue = formatValue(value)
    }

    /// Increments the value by the step increment
    private func incrementValue() {
        let newValue = value + stepIncrement
        value = min(max(newValue, minValue), maxValue)
        textValue = formatValue(value)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var secondsPerPhoto: Double = 2.5

        var body: some View {
            VStack(spacing: 20) {
                SecondsPerPhotoField(
                    label: "Duration:",
                    value: $secondsPerPhoto
                )

                Text("Current value: \(secondsPerPhoto, specifier: "%.2f") seconds")
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
