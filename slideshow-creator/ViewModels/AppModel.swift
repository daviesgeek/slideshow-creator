import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private enum PendingUserDecision {
        case save
        case discard
        case cancel
    }

    private enum FolderRestoreResult {
        case notConfigured
        case restored(URL)
        case needsRelink
    }

    private static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"
    private static let ffmpegPathDefaultsKey = "globalFFmpegPath"

    @Published var folderURL: URL?
    @Published var soundtrackFolderURL: URL?
    @Published var currentProjectURL: URL?

    @Published var items: [PhotoItem] = []
    @Published var soundtracks: [SoundtrackItem] = []
    @Published var selectedPhotoID: PhotoItem.ID?
    @Published var availableFlags: [String] = []
    @Published var selectedExportFlags: Set<String> = []
    @Published var exportMatchMode: FlagMatchMode = .any

    @Published var status: String = "Choose a folder to begin."
    @Published var isEncoding = false
    @Published var isEncodingWindowPresented = false
    @Published var encodingProgress: Double = 0
    @Published var encodingStatusLine: String = "Idle"
    @Published var encodingElapsedText: String = "00:00"
    @Published var encodingRemainingText: String = "Estimating…"
    @Published private(set) var hasUnsavedChanges = false

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
    private var isPerformingProgrammaticUpdate = false
    private var cancellables: Set<AnyCancellable> = []
    private var encodingTask: Task<Void, Never>?
    private var encodeStartDate: Date?

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

        configureDirtyTracking()
    }

    func newProject() {
        guard confirmPendingChangesIfNeeded() else { return }

        performProgrammaticUpdate {
            stopAllSecurityScopedAccess()

            folderURL = nil
            soundtrackFolderURL = nil
            currentProjectURL = nil
            items = []
            soundtracks = []
            selectedPhotoID = nil
            availableFlags = []
            selectedExportFlags = []
            exportMatchMode = .any

            secondsPerImage = 3
            width = 1920
            height = 1080
            fps = 30
            status = "Started a new project."
            hasUnsavedChanges = false
        }
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
        guard confirmPendingChangesIfNeeded() else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [projectFileType, .json]
        panel.prompt = "Open Project"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(from: url)
    }

    func canCloseWindow() -> Bool {
        confirmPendingChangesIfNeeded()
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
            selectedPhotoID = selectedPhotoID.flatMap { selected in
                items.contains(where: { $0.id == selected }) ? selected : nil
            } ?? items.first?.id
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
            performProgrammaticUpdate {
                currentProjectURL = url
                status = "Saved project: \(url.lastPathComponent)"
                hasUnsavedChanges = false
            }
        } catch {
            status = AppError.projectSaveFailed(error.localizedDescription).localizedDescription
        }
    }

    private func loadProject(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(SlideshowProjectDocument.self, from: data)

            performProgrammaticUpdate {
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

                switch resolveFolderForProject(
                    bookmarkData: document.photosFolderBookmark,
                    fallbackPath: document.photosFolderPath,
                    roleName: "photos"
                ) {
                case .restored(let photosFolder):
                    loadFolder(photosFolder)
                    reorderPhotos(using: document.photoOrder)
                    applyPhotoMetadata(
                        excludedByName: document.photoExcludedByName ?? [:],
                        flagsByName: document.photoFlagsByName ?? [:]
                    )
                case .notConfigured:
                    folderURL = nil
                    items = []
                case .needsRelink:
                    if let relinked = promptForFolderRelink(roleName: "photos") {
                        loadFolder(relinked)
                        reorderPhotos(using: document.photoOrder)
                        applyPhotoMetadata(
                            excludedByName: document.photoExcludedByName ?? [:],
                            flagsByName: document.photoFlagsByName ?? [:]
                        )
                    } else {
                        folderURL = nil
                        items = []
                    }
                }

                switch resolveFolderForProject(
                    bookmarkData: document.soundtrackFolderBookmark,
                    fallbackPath: document.soundtrackFolderPath,
                    roleName: "soundtracks"
                ) {
                case .restored(let soundtrackFolder):
                    loadSoundtrackFolder(soundtrackFolder)
                    reorderSoundtracks(using: document.soundtrackOrder)
                case .notConfigured:
                    soundtrackFolderURL = nil
                    soundtracks = []
                case .needsRelink:
                    if let relinked = promptForFolderRelink(roleName: "soundtracks") {
                        loadSoundtrackFolder(relinked)
                        reorderSoundtracks(using: document.soundtrackOrder)
                    } else {
                        soundtrackFolderURL = nil
                        soundtracks = []
                    }
                }

                currentProjectURL = url
                status = "Opened project: \(url.lastPathComponent)"
                hasUnsavedChanges = false
            }
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
                fps: fps
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
    ) -> FolderRestoreResult {
        let hasSavedReference = bookmarkData != nil || !(fallbackPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        guard hasSavedReference else {
            return .notConfigured
        }

        if let bookmarkData,
           let bookmarkedURL = resolveBookmarkURL(bookmarkData),
           folderExists(at: bookmarkedURL) {
            startSecurityScopedAccess(for: bookmarkedURL)
            return .restored(bookmarkedURL)
        }

        if let fallbackPath {
            let fallbackURL = URL(fileURLWithPath: fallbackPath)
            if folderExists(at: fallbackURL) {
                startSecurityScopedAccess(for: fallbackURL)
                return .restored(fallbackURL)
            }
        }

        return .needsRelink
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

    private func configureDirtyTracking() {
        Publishers.CombineLatest4($secondsPerImage.dropFirst(), $width.dropFirst(), $height.dropFirst(), $fps.dropFirst())
            .sink { [weak self] _, _, _, _ in
                self?.markProjectDirty()
            }
            .store(in: &cancellables)

        $items.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)

        $soundtracks.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)

        $availableFlags.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)

        $selectedExportFlags.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)

        $exportMatchMode.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)

        $folderURL.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)

        $soundtrackFolderURL.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
            .store(in: &cancellables)
    }

    private func performProgrammaticUpdate(_ updates: () -> Void) {
        isPerformingProgrammaticUpdate = true
        updates()
        isPerformingProgrammaticUpdate = false
    }

    private func markProjectDirty() {
        guard !isPerformingProgrammaticUpdate else { return }
        hasUnsavedChanges = true
    }

    private func confirmPendingChangesIfNeeded() -> Bool {
        guard hasUnsavedChanges else { return true }

        switch promptForPendingChanges() {
        case .save:
            if currentProjectURL == nil {
                saveProjectAs()
            } else {
                saveProject()
            }
            return !hasUnsavedChanges
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func promptForPendingChanges() -> PendingUserDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to this project before closing?"
        alert.informativeText = "If you don’t save, your recent project changes will be lost."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
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

    var shortcutFlags: [String] {
        Array(availableFlags.prefix(9))
    }

    func selectPhoto(_ id: PhotoItem.ID?) {
        selectedPhotoID = id
    }

    func toggleExcludeForSelectedPhoto() {
        guard let selectedPhotoID else { return }
        toggleExclude(for: selectedPhotoID)
    }

    func toggleExclude(for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isExcluded.toggle()
    }

    func toggleShortcutFlag(_ number: Int, for id: PhotoItem.ID) {
        guard number >= 1 else { return }
        let flags = shortcutFlags
        guard number <= flags.count else { return }

        let flag = flags[number - 1]
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if items[index].flags.contains(flag) {
            items[index].flags.remove(flag)
        } else {
            items[index].flags.insert(flag)
        }
    }

    func toggleShortcutFlagForSelectedPhoto(_ number: Int) {
        guard let selectedPhotoID else { return }
        toggleShortcutFlag(number, for: selectedPhotoID)
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

    func validateFFmpegPath() {
        do {
            let ffmpegURL = try resolveFFmpegURL()
            do {
                let versionLine = try ffmpegVersionLine(at: ffmpegURL)
                status = "FFmpeg OK: \(ffmpegURL.path) — \(versionLine)"
            } catch {
                status = "FFmpeg launch failed at \(ffmpegURL.path): \(error.localizedDescription)"
            }
        } catch {
            status = error.localizedDescription
        }
    }

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

        encodingTask?.cancel()
        encodingTask = Task { [weak self] in
            await self?.encode(to: outputURL, items: itemsToEncode)
        }
    }

    private func encode(to outputURL: URL, items: [PhotoItem]) async {
        resetEncodingProgress()
        isEncoding = true
        isEncodingWindowPresented = true
        status = "Encoding..."
        defer {
            isEncoding = false
            encodingTask = nil
        }

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
            ) { [weak self] progress, statusLine in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.encodingProgress = progress
                    self.encodingStatusLine = statusLine
                    self.updateEncodingTimeLabels(progress: progress)
                }
            }

            encodingProgress = 1
            encodingStatusLine = "Complete"
            encodingRemainingText = "00:00"
            status = output
        } catch {
            if error is CancellationError {
                encodingStatusLine = "Cancelled"
                encodingRemainingText = "00:00"
                status = AppError.encodingCancelled.localizedDescription
                return
            }

            if case AppError.encodingCancelled = error {
                encodingStatusLine = "Cancelled"
                encodingRemainingText = "00:00"
            } else {
                encodingStatusLine = "Failed"
            }

            status = error.localizedDescription
        }
    }

    func cancelEncoding() {
        guard isEncoding else { return }
        encodingTask?.cancel()
    }

    func closeEncodingProgressWindow() {
        isEncodingWindowPresented = false
    }

    private func resetEncodingProgress() {
        encodeStartDate = Date()
        encodingProgress = 0
        encodingStatusLine = "Starting…"
        encodingElapsedText = "00:00"
        encodingRemainingText = "Estimating…"
    }

    private func updateEncodingTimeLabels(progress: Double) {
        guard let encodeStartDate else { return }

        let elapsed = Date().timeIntervalSince(encodeStartDate)
        encodingElapsedText = Self.formatDuration(elapsed)

        guard progress > 0.03 else {
            encodingRemainingText = "Estimating…"
            return
        }

        let expectedTotal = elapsed / progress
        let remaining = max(0, expectedTotal - elapsed)
        encodingRemainingText = "~\(Self.formatDuration(remaining))"
    }

    private static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func resolveFFmpegURL() throws -> URL {
        // First try a bundled ffmpeg if you later decide to ship one inside the app bundle.
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        let userCandidate = normalizedFFmpegCandidate(from: ffmpegPath)
        let defaultCandidate = normalizedFFmpegCandidate(from: Self.defaultFFmpegPath)
        let intelHomebrewCandidate = normalizedFFmpegCandidate(from: "/usr/local/bin/ffmpeg")
        let userHomebrewCandidate = normalizedFFmpegCandidate(from: "~/.homebrew/bin/ffmpeg")
        let pathCandidate = ffmpegFromEnvironmentPATH()

        let candidates = [
            userCandidate,
            defaultCandidate,
            intelHomebrewCandidate,
            userHomebrewCandidate,
            pathCandidate
        ].compactMap { $0 }

        if let match = candidates.first(where: { isLikelyRunnableExecutable(atPath: $0) }) {
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

    private func normalizedFFmpegCandidate(from rawPath: String) -> String? {
        var candidate = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        candidate = stripWrappingQuotes(from: candidate)

        if candidate.hasPrefix("file://"), let fileURL = URL(string: candidate), fileURL.isFileURL {
            candidate = fileURL.path
        }

        candidate = (candidate as NSString).expandingTildeInPath

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue {
            candidate = (candidate as NSString).appendingPathComponent("ffmpeg")
        }

        // Keep symlink paths as entered (e.g. ~/.homebrew/bin/ffmpeg) instead of
        // forcing a resolved Cellar path, which can be more brittle across installs.
        return (candidate as NSString).standardizingPath
    }

    private func stripWrappingQuotes(from text: String) -> String {
        guard text.count >= 2 else { return text }

        // Handle escaped wrapping quotes, e.g. \"/path/to/ffmpeg\"
        if text.hasPrefix("\\\"") && text.hasSuffix("\\\"") && text.count >= 4 {
            return String(text.dropFirst(2).dropLast(2))
        }

        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
            ("‘", "’")
        ]

        guard let first = text.first, let last = text.last else { return text }

        if quotePairs.contains(where: { $0.0 == first && $0.1 == last }) {
            return String(text.dropFirst().dropLast())
        }

        return text
    }

    private func ffmpegFromEnvironmentPATH() -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"], !path.isEmpty else {
            return nil
        }

        for entry in path.split(separator: ":").map(String.init) {
            let expanded = (entry as NSString).expandingTildeInPath
            let candidate = (expanded as NSString).appendingPathComponent("ffmpeg")
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func isLikelyRunnableExecutable(atPath path: String) -> Bool {
        if FileManager.default.isExecutableFile(atPath: path) {
            return true
        }

        // Some environments may report executable checks inconsistently for symlinks;
        // allow existing files and rely on Process.run() to be the final authority.
        return FileManager.default.fileExists(atPath: path)
    }

    private func ffmpegVersionLine(at url: URL) throws -> String {
        do {
            return try runVersionCommand(executableURL: url, arguments: ["-version"])
        } catch {
            // Fallback for environments where launching symlinked binaries directly fails.
            return try runVersionCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [url.path, "-version"]
            )
        }
    }

    private func runVersionCommand(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? "ffmpeg -version"

        guard process.terminationStatus == 0 else {
            throw AppError.ffmpegFailed(text)
        }

        return firstLine
    }
}
