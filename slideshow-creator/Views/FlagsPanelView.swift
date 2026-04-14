import SwiftUI

struct FlagsPanelView: View {
    @ObservedObject var model: AppModel
    @Binding var newFlagName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Flags")
                    .font(.headline)

                TextField("Add flag", text: $newFlagName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                Button("Add") {
                    model.addFlag(newFlagName)
                    newFlagName = ""
                }
                .disabled(newFlagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()
                    .frame(height: 16)

                Picker("Match", selection: $model.exportMatchMode) {
                    ForEach(FlagMatchMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Menu("Filter Flags (\(model.selectedExportFlags.count))") {
                    if model.availableFlags.isEmpty {
                        Text("No flags yet")
                    }

                    ForEach(model.availableFlags, id: \.self) { flag in
                        Toggle(
                            isOn: Binding(
                                get: { model.selectedExportFlags.contains(flag) },
                                set: { isOn in
                                    model.setExportFlagSelection(flag: flag, isSelected: isOn)
                                }
                            )
                        ) {
                            Text(flag)
                        }
                    }

                    if !model.selectedExportFlags.isEmpty {
                        Divider()
                        Button("Clear Selection") {
                            model.selectedExportFlags = []
                        }
                    }
                }

                Text("Will export \(model.exportableItemsCount) photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !model.availableFlags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.availableFlags, id: \.self) { flag in
                            HStack(spacing: 6) {
                                Text(flag)
                                    .font(.caption)
                                Button {
                                    model.removeFlag(flag)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .help("Remove flag")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}
