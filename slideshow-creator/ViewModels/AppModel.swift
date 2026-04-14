import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"
    private static let ffmpegPathDefaultsKey = "globalFFmpegPath"

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

    // Global FFmpeg path (persisted across app launches/projects).
    @Published var ffmpegPath: String {
        didSet {
            persistGlobalFFmpegPath()
        }
    }

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

    init() {
        let defaults = UserDefaults.standard
        let storedPath = defaults.string(forKey: Self.ffmpegPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedPath, !storedPath.isEmpty {
            ffmpegPath = storedPath
        } else {
            // Default for Apple Silicon Homebrew. The resolver also checks other common paths.
            ffmpegPath = Self.defaultFFmpegPath
        }
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
            // FFmpeg path is now global and persisted via UserDefaults.
            // If this is the first run with no persisted value, migrate from legacy project setting.
            if UserDefaults.standard.object(forKey: Self.ffmpegPathDefaultsKey) == nil,
               let legacyPath = document.settings.ffmpegPath?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !legacyPath.isEmpty {
                ffmpegPath = legacyPath
            }
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
            Self.defaultFFmpegPath,
            "/usr/local/bin/ffmpeg"
        ]

        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: match)
        }

        throw AppError.ffmpegNotFound
    }

    private func persistGlobalFFmpegPath() {
        let trimmed = ffmpegPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.ffmpegPathDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: Self.ffmpegPathDefaultsKey)
        }
    }
}
