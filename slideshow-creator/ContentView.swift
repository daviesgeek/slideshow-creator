//
//  ContentView.swift
//  slideshow-creator
//
//  Created by Matthew Davies on 4/14/26.
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Model

struct PhotoItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var isExcluded = false
    var flags: Set<String> = []

    init(url: URL, isExcluded: Bool = false, flags: Set<String> = []) {
        self.url = url
        self.isExcluded = isExcluded
        self.flags = flags
    }

    var name: String { url.lastPathComponent }
}

enum FlagMatchMode: String, Codable, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .all: return "All"
        }
    }
}

struct SoundtrackItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
}

enum AppError: LocalizedError {
    case ffmpegNotFound
    case ffmpegFailed(String)
    case noImages
    case noExportableImages
    case projectSaveFailed(String)
    case projectLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Set a valid path or install it with Homebrew."
        case .ffmpegFailed(let output):
            return "FFmpeg failed:\n\(output)"
        case .noImages:
            return "No supported images found in the selected folder."
        case .noExportableImages:
            return "No exportable photos match your exclude/flag filters."
        case .projectSaveFailed(let message):
            return "Could not save project: \(message)"
        case .projectLoadFailed(let message):
            return "Could not open project: \(message)"
        }
    }
}

private struct ProjectSettings: Codable {
    let secondsPerImage: Double
    let width: Int
    let height: Int
    let fps: Int
    let ffmpegPath: String
}

private struct SlideshowProjectDocument: Codable {
    let version: Int
    let photosFolderPath: String?
    let soundtrackFolderPath: String?
    let photosFolderBookmark: Data?
    let soundtrackFolderBookmark: Data?
    let photoOrder: [String]
    let soundtrackOrder: [String]
    let settings: ProjectSettings
    let availableFlags: [String]?
    let selectedExportFlags: [String]?
    let exportMatchMode: String?
    let photoExcludedByName: [String: Bool]?
    let photoFlagsByName: [String: [String]]?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var soundtrackFolderURL: URL?
    @Published var currentProjectURL: URL?

    @Published var items: [PhotoItem] = []
    @Published var soundtracks: [SoundtrackItem] = []
    @Published var availableFlags: [String] = []
    @Published var selectedExportFlags: Set<String> = []
    @Published var exportMatchMode: FlagMatchMode = .any

    @Published var status: String = "Choose a folder to begin."
    @Published var isEncoding = false

    @Published var secondsPerImage: Double = 3
    @Published var width: Int = 1920
    @Published var height: Int = 1080
    @Published var fps: Int = 30

    // Default for Apple Silicon Homebrew. The resolver also checks other common paths.
    @Published var ffmpegPath: String = "/opt/homebrew/bin/ffmpeg"

    private var activeSecurityScopedURLs: Set<URL> = []

    private let allowedImageExtensions = Set([
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff"
    ])

    private let allowedAudioExtensions = Set([
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"
    ])

    private var projectFileType: UTType {
        UTType(filenameExtension: "slideshowproject") ?? .json
    }

    func newProject() {
        stopAllSecurityScopedAccess()

        folderURL = nil
        soundtrackFolderURL = nil
        currentProjectURL = nil
        items = []
        soundtracks = []
        availableFlags = []
        selectedExportFlags = []
        exportMatchMode = .any

        secondsPerImage = 3
        width = 1920
        height = 1080
        fps = 30
        ffmpegPath = "/opt/homebrew/bin/ffmpeg"

        status = "Started a new project."
    }

    func saveProject() {
        guard let currentProjectURL else {
            saveProjectAs()
            return
        }

        saveProject(to: currentProjectURL)
    }

    func saveProjectAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [projectFileType]
        panel.nameFieldStringValue = "slideshow.slideshowproject"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveProject(to: url)
    }

    func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [projectFileType, .json]
        panel.prompt = "Open Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(from: url)
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        startSecurityScopedAccess(for: folder)
        loadFolder(folder)
    }

    func loadFolder(_ folder: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let imageURLs = urls
                .filter { allowedImageExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            let existingByName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

            guard !imageURLs.isEmpty else {
                folderURL = folder
                items = []
                status = AppError.noImages.localizedDescription
                return
            }

            folderURL = folder
            items = imageURLs.map { url in
                let name = url.lastPathComponent
                if let existing = existingByName[name] {
                    return PhotoItem(url: url, isExcluded: existing.isExcluded, flags: existing.flags)
                }
                return PhotoItem(url: url)
            }
            status = "Loaded \(items.count) images."
        } catch {
            status = error.localizedDescription
        }
    }

    func pickSoundtrackFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        startSecurityScopedAccess(for: folder)
        loadSoundtrackFolder(folder)
    }

    func loadSoundtrackFolder(_ folder: URL) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let audioURLs = urls
                .filter { allowedAudioExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

            soundtrackFolderURL = folder
            soundtracks = audioURLs.map { SoundtrackItem(url: $0) }

            if soundtracks.isEmpty {
                status = "No supported audio files found in selected soundtrack folder."
            } else {
                status = "Loaded \(soundtracks.count) soundtrack(s)."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func saveProject(to url: URL) {
        do {
            let document = try buildProjectDocument()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)

            try data.write(to: url, options: .atomic)
            currentProjectURL = url
            status = "Saved project: \(url.lastPathComponent)"
        } catch {
            status = AppError.projectSaveFailed(error.localizedDescription).localizedDescription
        }
    }

    private func loadProject(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(SlideshowProjectDocument.self, from: data)

            stopAllSecurityScopedAccess()

            secondsPerImage = document.settings.secondsPerImage
            width = document.settings.width
            height = document.settings.height
            fps = document.settings.fps
            ffmpegPath = document.settings.ffmpegPath
            availableFlags = (document.availableFlags ?? []).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
            selectedExportFlags = Set(document.selectedExportFlags ?? [])
            exportMatchMode = FlagMatchMode(rawValue: document.exportMatchMode ?? "any") ?? .any

            if let photosFolder = resolveFolderForProject(
                bookmarkData: document.photosFolderBookmark,
                fallbackPath: document.photosFolderPath,
                roleName: "photos"
            ) {
                loadFolder(photosFolder)
                reorderPhotos(using: document.photoOrder)
                applyPhotoMetadata(
                    excludedByName: document.photoExcludedByName ?? [:],
                    flagsByName: document.photoFlagsByName ?? [:]
                )
            } else {
                folderURL = nil
                items = []
            }

            if let soundtrackFolder = resolveFolderForProject(
                bookmarkData: document.soundtrackFolderBookmark,
                fallbackPath: document.soundtrackFolderPath,
                roleName: "soundtracks"
            ) {
                loadSoundtrackFolder(soundtrackFolder)
                reorderSoundtracks(using: document.soundtrackOrder)
            } else {
                soundtrackFolderURL = nil
                soundtracks = []
            }

            currentProjectURL = url
            status = "Opened project: \(url.lastPathComponent)"
        } catch {
            status = AppError.projectLoadFailed(error.localizedDescription).localizedDescription
        }
    }

    private func buildProjectDocument() throws -> SlideshowProjectDocument {
        let photosBookmark = try folderURL?.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let soundtrackBookmark = try soundtrackFolderURL?.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return SlideshowProjectDocument(
            version: 1,
            photosFolderPath: folderURL?.path,
            soundtrackFolderPath: soundtrackFolderURL?.path,
            photosFolderBookmark: photosBookmark,
            soundtrackFolderBookmark: soundtrackBookmark,
            photoOrder: items.map(\.name),
            soundtrackOrder: soundtracks.map(\.name),
            settings: ProjectSettings(
                secondsPerImage: secondsPerImage,
                width: width,
                height: height,
                fps: fps,
                ffmpegPath: ffmpegPath
            ),
            availableFlags: availableFlags,
            selectedExportFlags: Array(selectedExportFlags),
            exportMatchMode: exportMatchMode.rawValue,
            photoExcludedByName: Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.isExcluded) }),
            photoFlagsByName: Dictionary(uniqueKeysWithValues: items.map { ($0.name, Array($0.flags)) })
        )
    }

    private func resolveFolderForProject(
        bookmarkData: Data?,
        fallbackPath: String?,
        roleName: String
    ) -> URL? {
        if let bookmarkData,
           let bookmarkedURL = resolveBookmarkURL(bookmarkData),
           folderExists(at: bookmarkedURL) {
            startSecurityScopedAccess(for: bookmarkedURL)
            return bookmarkedURL
        }

        if let fallbackPath {
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            if folderExists(at: fallbackURL) {
                startSecurityScopedAccess(for: fallbackURL)
                return fallbackURL
            }
        }

        return promptForFolderRelink(roleName: roleName)
    }

    private func resolveBookmarkURL(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private func folderExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func promptForFolderRelink(roleName: String) -> URL? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t find the \(roleName) folder"
        alert.informativeText = "Select a new \(roleName) folder to relink this project, or skip it for now."
        alert.addButton(withTitle: "Relink Folder")
        alert.addButton(withTitle: "Skip")

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Relink"

        guard panel.runModal() == .OK, let relinkedURL = panel.url else { return nil }
        startSecurityScopedAccess(for: relinkedURL)
        return relinkedURL
    }

    private func reorderPhotos(using savedOrder: [String]) {
        guard !savedOrder.isEmpty else { return }

        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        let ordered = savedOrder.compactMap { byName[$0] }
        let leftovers = items.filter { !savedOrder.contains($0.name) }
        items = ordered + leftovers
    }

    private func reorderSoundtracks(using savedOrder: [String]) {
        guard !savedOrder.isEmpty else { return }

        let byName = Dictionary(uniqueKeysWithValues: soundtracks.map { ($0.name, $0) })
        let ordered = savedOrder.compactMap { byName[$0] }
        let leftovers = soundtracks.filter { !savedOrder.contains($0.name) }
        soundtracks = ordered + leftovers
    }

    private func applyPhotoMetadata(
        excludedByName: [String: Bool],
        flagsByName: [String: [String]]
    ) {
        for index in items.indices {
            let name = items[index].name
            items[index].isExcluded = excludedByName[name] ?? false
            items[index].flags = Set(flagsByName[name] ?? [])
        }

        if availableFlags.isEmpty {
            let discoveredFlags = Set(items.flatMap { $0.flags })
            availableFlags = Array(discoveredFlags).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        }

        selectedExportFlags = selectedExportFlags.intersection(Set(availableFlags))
    }

    private func startSecurityScopedAccess(for url: URL) {
        guard !activeSecurityScopedURLs.contains(url) else { return }

        if url.startAccessingSecurityScopedResource() {
            activeSecurityScopedURLs.insert(url)
        }
    }

    private func stopAllSecurityScopedAccess() {
        for url in activeSecurityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURLs.removeAll()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func moveSoundtracks(from source: IndexSet, to destination: Int) {
        soundtracks.move(fromOffsets: source, toOffset: destination)
    }

    func addFlag(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !availableFlags.contains(name) else { return }

        availableFlags.append(name)
        availableFlags.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func removeFlag(_ flag: String) {
        availableFlags.removeAll { $0 == flag }
        selectedExportFlags.remove(flag)

        for index in items.indices {
            items[index].flags.remove(flag)
        }
    }

    func setPhotoExcluded(_ isExcluded: Bool, for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isExcluded = isExcluded
    }

    func setFlag(_ flag: String, enabled: Bool, for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        if enabled {
            items[index].flags.insert(flag)
        } else {
            items[index].flags.remove(flag)
        }
    }

    func setExportFlagSelection(flag: String, isSelected: Bool) {
        if isSelected {
            selectedExportFlags.insert(flag)
        } else {
            selectedExportFlags.remove(flag)
        }
    }

    var exportableItems: [PhotoItem] {
        let included = items.filter { !$0.isExcluded }

        guard !selectedExportFlags.isEmpty else { return included }

        switch exportMatchMode {
        case .any:
            return included.filter { !$0.flags.isDisjoint(with: selectedExportFlags) }
        case .all:
            return included.filter { selectedExportFlags.isSubset(of: $0.flags) }
        }
    }

    var exportableItemsCount: Int { exportableItems.count }

    func chooseOutputAndEncode() {
        guard !items.isEmpty else {
            status = "Nothing to encode."
            return
        }

        let itemsToEncode = exportableItems
        guard !itemsToEncode.isEmpty else {
            status = AppError.noExportableImages.localizedDescription
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "slideshow.mp4"

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        Task {
            await encode(to: outputURL, items: itemsToEncode)
        }
    }

    private func encode(to outputURL: URL, items: [PhotoItem]) async {
        isEncoding = true
        status = "Encoding..."
        defer { isEncoding = false }

        do {
            let ffmpegURL = try resolveFFmpegURL()
            let output = try await FFmpegEncoder.run(
                ffmpegURL: ffmpegURL,
                items: items,
                soundtracks: soundtracks,
                outputURL: outputURL,
                secondsPerImage: secondsPerImage,
                width: width,
                height: height,
                fps: fps
            )
            status = output
        } catch {
            status = error.localizedDescription
        }
    }

    private func resolveFFmpegURL() throws -> URL {
        // First try a bundled ffmpeg if you later decide to ship one inside the app bundle.
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let candidates = [
            ffmpegPath,
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: match)
        }

        throw AppError.ffmpegNotFound
    }
}

// MARK: - FFmpeg

enum FFmpegEncoder {
    static func run(
        ffmpegURL: URL,
        items: [PhotoItem],
        soundtracks: [SoundtrackItem],
        outputURL: URL,
        secondsPerImage: Double,
        width: Int,
        height: Int,
        fps: Int
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = ffmpegURL
            process.arguments = makeArguments(
                items: items,
                soundtracks: soundtracks,
                outputURL: outputURL,
                secondsPerImage: secondsPerImage,
                width: width,
                height: height,
                fps: fps
            )
            process.standardOutput = pipe
            process.standardError = pipe

            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)

                if process.terminationStatus == 0 {
                    continuation.resume(returning: "Done: \(outputURL.path)")
                } else {
                    continuation.resume(throwing: AppError.ffmpegFailed(text))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func makeArguments(
        items: [PhotoItem],
        soundtracks: [SoundtrackItem],
        outputURL: URL,
        secondsPerImage: Double,
        width: Int,
        height: Int,
        fps: Int
    ) -> [String] {
        let slideshowDuration = Double(items.count) * secondsPerImage

        var args: [String] = ["-y"]

        for item in items {
            args += [
                "-loop", "1",
                "-t", String(secondsPerImage),
                "-i", item.url.path
            ]
        }

        for soundtrack in soundtracks {
            args += [
                "-i", soundtrack.url.path
            ]
        }

        var filterParts: [String] = []

        for index in items.indices {
            let part =
                "[\(index):v]" +
                "scale=\(width):\(height):force_original_aspect_ratio=decrease," +
                "pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2," +
                "setsar=1," +
                "format=yuv420p" +
                "[v\(index)]"
            filterParts.append(part)
        }

        let concatInputs = items.indices.map { "[v\($0)]" }.joined()
        filterParts.append("\(concatInputs)concat=n=\(items.count):v=1:a=0[v]")

        if !soundtracks.isEmpty {
            let audioStartIndex = items.count

            for index in soundtracks.indices {
                let inputIndex = audioStartIndex + index
                filterParts.append("[\(inputIndex):a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a\(index)]")
            }

            let audioConcatInputs = soundtracks.indices.map { "[a\($0)]" }.joined()
            let fadeDuration = max(0.1, min(1.0, slideshowDuration))
            let fadeStart = max(0.0, slideshowDuration - fadeDuration)

            filterParts.append("\(audioConcatInputs)concat=n=\(soundtracks.count):v=0:a=1,atrim=0:\(slideshowDuration),afade=t=out:st=\(fadeStart):d=\(fadeDuration)[a]")
        }

        args += [
            "-filter_complex", filterParts.joined(separator: ";"),
            "-map", "[v]",
            "-r", "\(fps)",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-movflags", "+faststart"
        ]

        if !soundtracks.isEmpty {
            args += [
                "-map", "[a]",
                "-c:a", "aac",
                "-b:a", "192k"
            ]
        }

        args += [outputURL.path]

        return args
    }
}

// MARK: - UI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isPreviewPresented = false
    @State private var previewIndex = 0
    @State private var newFlagName = ""

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
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

            if let projectURL = model.currentProjectURL {
                Text("Project: \(projectURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

                HStack(spacing: 12) {
                    TextField("FFmpeg path", text: $model.ffmpegPath)

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

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos")
                            .font(.headline)

                        if let folderURL = model.folderURL {
                            Text(folderURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }

                        List {
                            ForEach(model.items) { item in
                                PhotoRow(
                                    item: item,
                                    availableFlags: model.availableFlags,
                                    onThumbnailTap: { openPreview(for: item) },
                                    onExcludeToggle: { isExcluded in
                                        model.setPhotoExcluded(isExcluded, for: item.id)
                                    },
                                    onFlagToggle: { flag, isEnabled in
                                        model.setFlag(flag, enabled: isEnabled, for: item.id)
                                    }
                                )
                            }
                            .onMove(perform: model.move)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Soundtracks")
                            .font(.headline)

                        if let soundtrackFolderURL = model.soundtrackFolderURL {
                            Text(soundtrackFolderURL.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .textSelection(.enabled)
                        }

                        List {
                            ForEach(model.soundtracks) { soundtrack in
                                SoundtrackRow(item: soundtrack)
                            }
                            .onMove(perform: model.moveSoundtracks)
                        }
                    }
                }


                Text(model.status)
                    .font(.callout.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(minWidth: 900, minHeight: 600)

            if isPreviewPresented {
                FullscreenPhotoPreview(
                    items: model.items,
                    currentIndex: $previewIndex,
                    onClose: { isPreviewPresented = false }
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    private func openPreview(for item: PhotoItem) {
        guard let index = model.items.firstIndex(of: item) else { return }
        previewIndex = index
        isPreviewPresented = true
    }
}

struct SoundtrackRow: View {
    let item: SoundtrackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .lineLimit(1)

            Text(item.url.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

struct PhotoRow: View {
    let item: PhotoItem
    let availableFlags: [String]
    let onThumbnailTap: () -> Void
    let onExcludeToggle: (Bool) -> Void
    let onFlagToggle: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onThumbnailTap) {
                ThumbnailView(url: item.url)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .help("Open fullscreen preview")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .lineLimit(1)

                    Toggle(
                        "Exclude",
                        isOn: Binding(
                            get: { item.isExcluded },
                            set: { onExcludeToggle($0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .font(.caption)

                    if !availableFlags.isEmpty {
                        Menu("Flags") {
                            ForEach(availableFlags, id: \.self) { flag in
                                Toggle(
                                    isOn: Binding(
                                        get: { item.flags.contains(flag) },
                                        set: { isOn in onFlagToggle(flag, isOn) }
                                    )
                                ) {
                                    Text(flag)
                                }
                            }
                        }
                        .font(.caption)
                    }
                }

                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !item.flags.isEmpty {
                    Text(item.flags.sorted().joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .opacity(item.isExcluded ? 0.45 : 1)
        .padding(.vertical, 4)
    }
}

struct FullscreenPhotoPreview: View {
    let items: [PhotoItem]
    @Binding var currentIndex: Int
    let onClose: () -> Void

    private var hasItems: Bool { !items.isEmpty }

    private var safeIndex: Int {
        guard hasItems else { return 0 }
        return min(max(currentIndex, 0), items.count - 1)
    }

    private var currentItem: PhotoItem? {
        guard hasItems else { return nil }
        return items[safeIndex]
    }

    private func goPrevious() {
        currentIndex = max(0, safeIndex - 1)
    }

    private func goNext() {
        currentIndex = min(items.count - 1, safeIndex + 1)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item = currentItem {
                if let image = NSImage(contentsOf: item.url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                } else {
                    Text("Unable to preview image")
                        .foregroundStyle(.white)
                }

                VStack {
                    Spacer()

                    HStack(spacing: 12) {
                        Button("Previous", action: goPrevious)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(safeIndex == 0)

                        Button("Next", action: goNext)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .disabled(safeIndex == items.count - 1)

                        Divider()
                            .frame(height: 18)

                        Text(item.url.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        } label: {
                            Image(systemName: "arrow.up.forward")
                        }
                        .help("Reveal in Finder")

                        Spacer(minLength: 0)

                        Text("\(safeIndex + 1) / \(items.count)")
                            .font(.caption.monospacedDigit())

                        Button("Close", action: onClose)
                            .keyboardShortcut(.escape, modifiers: [])
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 10) {
                    Text("No images to preview")
                        .foregroundStyle(.white)
                    Button("Close", action: onClose)
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .onAppear {
            guard hasItems else { return }
            currentIndex = safeIndex
        }
    }
}

struct ThumbnailView: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay(Text("No Preview").font(.caption2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

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
