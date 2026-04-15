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
                    .onChange(of: textValue) { _, newValue in
                        validateAndUpdateBinding(newValue)
                    }
                    .onSubmit {
                        commitValue()
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

    /// Validates and updates the binding when text changes
    private func validateAndUpdateBinding(_ text: String) {
        // Allow empty text while editing
        guard !text.isEmpty else { return }

        // Parse the input (accept both . and , as decimal separator)
        let cleanedText = text.replacingOccurrences(of: ",", with: ".")
        guard let parsedValue = Double(cleanedText) else {
            // Invalid input, don't update binding
            return
        }

        // Clamp to valid range
        let clampedValue = min(max(parsedValue, minValue), maxValue)

        // Update binding with clamped value
        value = clampedValue
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
