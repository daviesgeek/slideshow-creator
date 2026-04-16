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

    private enum LastProjectRestoreResult {
        case notConfigured
        case restored(URL)
        case missingOrInvalid
    }

    enum PhotosViewMode: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: Self { self }

        var title: String {
            switch self {
            case .list: return "List"
            case .grid: return "Grid"
            }
        }
    }

    enum PhotosExclusionFilter: String, CaseIterable, Identifiable {
        case all
        case included
        case excluded

        var id: Self { self }

        var title: String {
            switch self {
            case .all: return "All"
            case .included: return "Included"
            case .excluded: return "Excluded"
            }
        }
    }

    private static let defaultFFmpegPath = "/opt/homebrew/bin/ffmpeg"
    private static let ffmpegPathDefaultsKey = "globalFFmpegPath"
    private static let photosViewModeDefaultsKey = "photosViewMode"
    private static let photosExclusionFilterDefaultsKey = "photosExclusionFilter"
    private static let photosSoundtracksSplitRatioDefaultsKey = "photosSoundtracksSplitRatio"
    private static let photosGridCellWidthDefaultsKey = "photosGridCellWidth"
    private static let lastProjectBookmarkDefaultsKey = "lastOpenedProjectBookmark"
    private static let lastProjectPathDefaultsKey = "lastOpenedProjectPath"

    @Published var folderURL: URL?
    @Published var soundtrackFolderURL: URL?
    @Published var currentProjectURL: URL?

    @Published var items: [PhotoItem] = []
    @Published var soundtracks: [SoundtrackItem] = []
    @Published var selectedPhotoID: PhotoItem.ID?
    @Published var selectedPhotoIDs: Set<PhotoItem.ID> = []
    @Published var selectionAnchorPhotoID: PhotoItem.ID?
    @Published var photosViewMode: PhotosViewMode {
        didSet {
            UserDefaults.standard.set(photosViewMode.rawValue, forKey: Self.photosViewModeDefaultsKey)
        }
    }
    @Published var photosExclusionFilter: PhotosExclusionFilter {
        didSet {
            UserDefaults.standard.set(photosExclusionFilter.rawValue, forKey: Self.photosExclusionFilterDefaultsKey)
        }
    }
    @Published var photosSoundtracksSplitRatio: Double {
        didSet {
            UserDefaults.standard.set(
                Self.clampSplitRatio(photosSoundtracksSplitRatio),
                forKey: Self.photosSoundtracksSplitRatioDefaultsKey
            )
        }
    }
    @Published var photosGridCellWidth: Double {
        didSet {
            UserDefaults.standard.set(
                Self.clampGridCellWidth(photosGridCellWidth),
                forKey: Self.photosGridCellWidthDefaultsKey
            )
        }
    }
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
    @Published var encodingLogText: String = ""
    @Published private(set) var hasUnsavedChanges = false

    @Published var secondsPerImage: Double = 3
    @Published var defaultTransitionToNext: PhotoTransitionStyle = .none
    @Published var defaultTransitionDurationToNext: Double = 1.0
    @Published var width: Int = 1920
    @Published var height: Int = 1080
    @Published var fps: Int = 30
    @Published var encodeSpeedMode: EncodeSpeedMode = .fastestHardware

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
    private var encodingTickerTask: Task<Void, Never>?
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

        if let storedMode = defaults.string(forKey: Self.photosViewModeDefaultsKey),
           let mode = PhotosViewMode(rawValue: storedMode) {
            photosViewMode = mode
        } else {
            photosViewMode = .list
        }

        if let storedFilter = defaults.string(forKey: Self.photosExclusionFilterDefaultsKey),
           let filter = PhotosExclusionFilter(rawValue: storedFilter) {
            photosExclusionFilter = filter
        } else {
            photosExclusionFilter = .all
        }

        if defaults.object(forKey: Self.photosSoundtracksSplitRatioDefaultsKey) != nil {
            photosSoundtracksSplitRatio = Self.clampSplitRatio(
                defaults.double(forKey: Self.photosSoundtracksSplitRatioDefaultsKey)
            )
        } else {
            photosSoundtracksSplitRatio = 0.62
        }

        if defaults.object(forKey: Self.photosGridCellWidthDefaultsKey) != nil {
            photosGridCellWidth = Self.clampGridCellWidth(
                defaults.double(forKey: Self.photosGridCellWidthDefaultsKey)
            )
        } else {
            photosGridCellWidth = 170
        }

        configureDirtyTracking()

        switch restoreLastOpenedProject() {
        case .restored(let url):
            loadProject(from: url)
        case .missingOrInvalid:
            clearLastOpenedProject()
        case .notConfigured:
            break
        }
    }

    private static func clampSplitRatio(_ value: Double) -> Double {
        min(0.9, max(0.1, value))
    }

    private static func clampGridCellWidth(_ value: Double) -> Double {
        min(280, max(120, value))
    }

    func newProject() {
        guard confirmProjectSavedIfNeeded(before: "starting a new project") else { return }

        performProgrammaticUpdate {
            stopAllSecurityScopedAccess()

            folderURL = nil
            soundtrackFolderURL = nil
            currentProjectURL = nil
            items = []
            soundtracks = []
            clearPhotoSelection()
            availableFlags = []
            selectedExportFlags = []
            exportMatchMode = .any

            secondsPerImage = 3
            defaultTransitionToNext = .none
            defaultTransitionDurationToNext = 1.0
            width = 1920
            height = 1080
            fps = 30
            encodeSpeedMode = .fastestHardware
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
        guard confirmProjectSavedIfNeeded(before: "opening another project") else { return }

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
        confirmProjectSavedIfNeeded(before: "closing")
    }

    func pickFolder() {
        guard confirmProjectSavedIfNeeded(before: "changing the photos folder") else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        startSecurityScopedAccess(for: folder)
        loadFolder(folder)
    }

    func refreshPhotos() {
        guard let folderURL else {
            status = "Choose a photos folder first."
            return
        }

        loadFolder(folderURL, preservingMissingItems: true, isManualRefresh: true)
    }

    func loadFolder(_ folder: URL) {
        loadFolder(folder, preservingMissingItems: false)
    }

    private func loadFolder(
        _ folder: URL,
        preservingMissingItems: Bool,
        isManualRefresh: Bool = false
    ) {
        do {
            let imageURLs = try normalizedImageURLs(in: folder)
            let scannedByReference = Dictionary(uniqueKeysWithValues: imageURLs.map { ($0.lastPathComponent, $0) })
            let existingByReference = Dictionary(uniqueKeysWithValues: items.map { ($0.referenceName, $0) })

            var updatedItems: [PhotoItem] = imageURLs.map { url in
                let referenceName = url.lastPathComponent
                if var existing = existingByReference[referenceName] {
                    if existing.isRelinked {
                        if let relinkedURL = resolveRelinkedPhotoURL(
                            bookmarkData: existing.relinkedBookmark,
                            fallbackPath: existing.relinkedPath
                        ) {
                            existing.url = relinkedURL
                            existing.isMissing = false
                        } else {
                            existing.isMissing = true
                        }
                    } else {
                        existing.url = url
                        existing.isMissing = false
                    }
                    return existing
                }

                return PhotoItem(referenceName: referenceName, url: url)
            }

            if preservingMissingItems {
                let representedReferences = Set(updatedItems.map(\.referenceName))
                let leftovers = items.compactMap { existing -> PhotoItem? in
                    guard !representedReferences.contains(existing.referenceName) else { return nil }

                    var carried = existing
                    if existing.isRelinked,
                       let relinkedURL = resolveRelinkedPhotoURL(
                           bookmarkData: existing.relinkedBookmark,
                           fallbackPath: existing.relinkedPath
                       ) {
                        carried.url = relinkedURL
                        carried.isMissing = false
                    } else {
                        carried.isMissing = true
                    }
                    return carried
                }
                updatedItems.append(contentsOf: leftovers)
            }

            let previousReferences = Set(items.map(\.referenceName))
            folderURL = folder
            items = updatedItems
            refreshPhotoAvailability(using: scannedByReference)

            guard !items.isEmpty else {
                clearPhotoSelection()
                status = AppError.noImages.localizedDescription
                return
            }

            selectedPhotoID = selectedPhotoID.flatMap { selected in
                items.contains(where: { $0.id == selected }) ? selected : nil
            } ?? items.first?.id
            selectedPhotoIDs = selectedPhotoID.map { [$0] } ?? []
            selectionAnchorPhotoID = selectedPhotoID

            let addedCount = imageURLs.reduce(into: 0) { count, url in
                if !previousReferences.contains(url.lastPathComponent) {
                    count += 1
                }
            }
            let missingCount = items.filter(\.isMissing).count
            if isManualRefresh {
                if addedCount > 0, missingCount > 0 {
                    status = "Added \(addedCount) new photo(s). \(missingCount) photo(s) are missing."
                } else if addedCount > 0 {
                    status = "Added \(addedCount) new photo(s)."
                } else if missingCount > 0 {
                    status = "\(missingCount) photo(s) are missing."
                } else {
                    status = "No changes found."
                }
            } else {
                status = "Loaded \(items.count) images."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func pickSoundtrackFolder() {
        guard confirmProjectSavedIfNeeded(before: "changing the soundtrack folder") else { return }

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
            persistLastOpenedProject(url: url)
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
                defaultTransitionToNext = document.settings.defaultTransitionStyle ?? .none
                defaultTransitionDurationToNext = document.settings.defaultTransitionDuration ?? 1.0
                width = document.settings.width
                height = document.settings.height
                fps = document.settings.fps
                encodeSpeedMode = document.settings.encodeSpeedMode ?? .fastestHardware
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
                        flagsByName: document.photoFlagsByName ?? [:],
                        relinkedPathByName: document.photoRelinkedPathByName ?? [:],
                        relinkedBookmarkByName: document.photoRelinkedBookmarkByName ?? [:],
                        secondsOverrideByName: document.photoSecondsOverrideByName ?? [:],
                        transitionToNextByName: document.photoTransitionToNextByName ?? [:],
                        transitionDurationToNextByName: document.photoTransitionDurationToNextByName ?? [:]
                    )
                case .notConfigured:
                    folderURL = nil
                    items = []
                    clearPhotoSelection()
                case .needsRelink:
                    if let relinked = promptForFolderRelink(roleName: "photos") {
                        loadFolder(relinked)
                        reorderPhotos(using: document.photoOrder)
                        applyPhotoMetadata(
                            excludedByName: document.photoExcludedByName ?? [:],
                            flagsByName: document.photoFlagsByName ?? [:],
                            relinkedPathByName: document.photoRelinkedPathByName ?? [:],
                            relinkedBookmarkByName: document.photoRelinkedBookmarkByName ?? [:],
                            secondsOverrideByName: document.photoSecondsOverrideByName ?? [:],
                            transitionToNextByName: document.photoTransitionToNextByName ?? [:],
                            transitionDurationToNextByName: document.photoTransitionDurationToNextByName ?? [:]
                        )
                    } else {
                        folderURL = nil
                        items = []
                        clearPhotoSelection()
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
            persistLastOpenedProject(url: url)
        } catch {
            status = AppError.projectLoadFailed(error.localizedDescription).localizedDescription
        }
    }

    private func restoreLastOpenedProject() -> LastProjectRestoreResult {
        let defaults = UserDefaults.standard

        if let bookmarkData = defaults.data(forKey: Self.lastProjectBookmarkDefaultsKey) {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let resolvedURL = bookmarkedURL.standardizedFileURL
                if FileManager.default.fileExists(atPath: resolvedURL.path) {
                    if isStale {
                        persistLastOpenedProject(url: resolvedURL)
                    }
                    return .restored(resolvedURL)
                }
                return .missingOrInvalid
            }

            return .missingOrInvalid
        }

        if let path = defaults.string(forKey: Self.lastProjectPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) {
                return .restored(url)
            }
            return .missingOrInvalid
        }

        return .notConfigured
    }

    private func persistLastOpenedProject(url: URL) {
        let defaults = UserDefaults.standard
        let normalizedURL = url.standardizedFileURL

        defaults.set(normalizedURL.path, forKey: Self.lastProjectPathDefaultsKey)

        if let bookmarkData = try? normalizedURL.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(bookmarkData, forKey: Self.lastProjectBookmarkDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.lastProjectBookmarkDefaultsKey)
        }
    }

    private func clearLastOpenedProject() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.lastProjectBookmarkDefaultsKey)
        defaults.removeObject(forKey: Self.lastProjectPathDefaultsKey)
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

        let relinkedPathByName = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard item.isRelinked, let path = item.relinkedPath else { return nil }
            return (item.referenceName, path)
        })
        let relinkedBookmarkByName = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, Data)? in
            guard item.isRelinked, let bookmark = item.relinkedBookmark else { return nil }
            return (item.referenceName, bookmark)
        })
        let transitionToNextByName = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, PhotoTransitionStyle)? in
            guard let transition = item.transitionToNext else { return nil }
            return (item.referenceName, transition)
        })
        let secondsOverrideByName = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, Double)? in
            guard let secondsOverride = item.secondsOverride else { return nil }
            return (item.referenceName, secondsOverride)
        })
        let transitionDurationToNextByName = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, Double)? in
            guard let duration = item.transitionDurationToNext else { return nil }
            return (item.referenceName, duration)
        })

        return SlideshowProjectDocument(
            version: 1,
            photosFolderPath: folderURL?.path,
            soundtrackFolderPath: soundtrackFolderURL?.path,
            photosFolderBookmark: photosBookmark,
            soundtrackFolderBookmark: soundtrackBookmark,
            photoOrder: items.map(\.referenceName),
            soundtrackOrder: soundtracks.map(\.name),
            settings: ProjectSettings(
                secondsPerImage: secondsPerImage,
                width: width,
                height: height,
                fps: fps,
                encodeSpeedMode: encodeSpeedMode,
                defaultTransitionStyle: defaultTransitionToNext,
                defaultTransitionDuration: defaultTransitionDurationToNext
            ),
            availableFlags: availableFlags,
            selectedExportFlags: Array(selectedExportFlags),
            exportMatchMode: exportMatchMode.rawValue,
            photoExcludedByName: Dictionary(uniqueKeysWithValues: items.map { ($0.referenceName, $0.isExcluded) }),
            photoFlagsByName: Dictionary(uniqueKeysWithValues: items.map { ($0.referenceName, Array($0.flags)) }),
            photoRelinkedPathByName: relinkedPathByName,
            photoRelinkedBookmarkByName: relinkedBookmarkByName,
            photoSecondsOverrideByName: secondsOverrideByName,
            photoTransitionToNextByName: transitionToNextByName,
            photoTransitionDurationToNextByName: transitionDurationToNextByName
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

    private func resolveRelinkedPhotoURL(bookmarkData: Data?, fallbackPath: String?) -> URL? {
        if let bookmarkData {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let resolved = bookmarkedURL.standardizedFileURL
                if FileManager.default.fileExists(atPath: resolved.path) {
                    startSecurityScopedAccess(for: resolved)
                    return resolved
                }
            }
        }

        if let fallbackPath,
           !fallbackPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let fallbackURL = URL(fileURLWithPath: fallbackPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: fallbackURL.path) {
                startSecurityScopedAccess(for: fallbackURL)
                return fallbackURL
            }
        }

        return nil
    }

    private func normalizedImageURLs(in folder: URL) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return urls
            .filter { allowedImageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func fallbackURL(forReferenceName referenceName: String) -> URL {
        if let folderURL {
            return folderURL.appendingPathComponent(referenceName)
        }
        return URL(fileURLWithPath: referenceName)
    }

    private func refreshPhotoAvailability(using scannedByReference: [String: URL]? = nil) {
        let folderByReference: [String: URL]
        if let scannedByReference {
            folderByReference = scannedByReference
        } else if let folderURL,
                  let scanned = try? normalizedImageURLs(in: folderURL) {
            folderByReference = Dictionary(uniqueKeysWithValues: scanned.map { ($0.lastPathComponent, $0) })
        } else {
            folderByReference = [:]
        }

        for index in items.indices {
            if items[index].isRelinked,
               let relinkedURL = resolveRelinkedPhotoURL(
                   bookmarkData: items[index].relinkedBookmark,
                   fallbackPath: items[index].relinkedPath
               ) {
                items[index].url = relinkedURL
                items[index].isMissing = false
                continue
            }

            if items[index].isRelinked {
                items[index].isMissing = true
                continue
            }

            if let folderURL = folderByReference[items[index].referenceName] {
                items[index].url = folderURL
                items[index].isMissing = false
            } else {
                items[index].isMissing = true
            }
        }
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

        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.referenceName, $0) })
        let ordered = savedOrder.map { referenceName in
            byName[referenceName] ?? PhotoItem(
                referenceName: referenceName,
                url: fallbackURL(forReferenceName: referenceName),
                isMissing: true
            )
        }
        let leftovers = items.filter { !savedOrder.contains($0.referenceName) }
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
        flagsByName: [String: [String]],
        relinkedPathByName: [String: String],
        relinkedBookmarkByName: [String: Data],
        secondsOverrideByName: [String: Double],
        transitionToNextByName: [String: PhotoTransitionStyle],
        transitionDurationToNextByName: [String: Double]
    ) {
        for index in items.indices {
            let name = items[index].referenceName
            items[index].isExcluded = excludedByName[name] ?? false
            items[index].flags = Set(flagsByName[name] ?? [])
            items[index].relinkedPath = relinkedPathByName[name]
            items[index].relinkedBookmark = relinkedBookmarkByName[name]
            items[index].isRelinked = items[index].relinkedPath != nil || items[index].relinkedBookmark != nil
            items[index].secondsOverride = secondsOverrideByName[name]
            items[index].transitionToNext = transitionToNextByName[name]
            items[index].transitionDurationToNext = transitionDurationToNextByName[name]
        }

        refreshPhotoAvailability()

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

        Publishers.CombineLatest($defaultTransitionToNext.dropFirst(), $defaultTransitionDurationToNext.dropFirst())
            .sink { [weak self] _, _ in
                self?.markProjectDirty()
            }
            .store(in: &cancellables)

        $encodeSpeedMode.dropFirst()
            .sink { [weak self] _ in self?.markProjectDirty() }
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

    private func confirmProjectSavedIfNeeded(before actionDescription: String) -> Bool {
        guard requiresSavingBeforeMajorAction else { return true }

        switch promptToSaveBeforeMajorAction(actionDescription: actionDescription) {
        case .save:
            if currentProjectURL == nil {
                saveProjectAs()
            } else {
                saveProject()
            }
            return !requiresSavingBeforeMajorAction
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private var requiresSavingBeforeMajorAction: Bool {
        hasUnsavedChanges || currentProjectURL == nil
    }

    private func promptToSaveBeforeMajorAction(actionDescription: String) -> PendingUserDecision {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save this project before \(actionDescription)?"
        if hasUnsavedChanges {
            alert.informativeText = "If you don’t save, your recent project changes will be lost."
        } else {
            alert.informativeText = "This project has not been saved yet."
        }
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

    func movePhoto(withID draggedID: PhotoItem.ID, before targetID: PhotoItem.ID) {
        movePhotos(withIDs: [draggedID], before: targetID)
    }

    func movePhotoToEnd(withID draggedID: PhotoItem.ID) {
        movePhotosToEnd(withIDs: [draggedID])
    }

    func movePhotos(withIDs ids: Set<PhotoItem.ID>, before targetID: PhotoItem.ID) {
        let movingIDs = normalizedPhotoSelection(ids)
        guard !movingIDs.isEmpty else { return }
        guard !movingIDs.contains(targetID) else { return }

        let movingItems = items.filter { movingIDs.contains($0.id) }
        guard !movingItems.isEmpty else { return }

        var remainingItems = items.filter { !movingIDs.contains($0.id) }
        guard let targetIndex = remainingItems.firstIndex(where: { $0.id == targetID }) else { return }

        remainingItems.insert(contentsOf: movingItems, at: targetIndex)
        items = remainingItems
    }

    func movePhotosToEnd(withIDs ids: Set<PhotoItem.ID>) {
        let movingIDs = normalizedPhotoSelection(ids)
        guard !movingIDs.isEmpty else { return }

        let movingItems = items.filter { movingIDs.contains($0.id) }
        guard !movingItems.isEmpty else { return }

        let remainingItems = items.filter { !movingIDs.contains($0.id) }
        items = remainingItems + movingItems
    }

    func moveSoundtrack(withID draggedID: SoundtrackItem.ID, before targetID: SoundtrackItem.ID) {
        guard draggedID != targetID,
              let sourceIndex = soundtracks.firstIndex(where: { $0.id == draggedID }),
              let targetIndex = soundtracks.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        var reordered = soundtracks
        let movedItem = reordered.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        reordered.insert(movedItem, at: adjustedTargetIndex)
        soundtracks = reordered
    }

    func moveSoundtrackToEnd(withID draggedID: SoundtrackItem.ID) {
        guard let sourceIndex = soundtracks.firstIndex(where: { $0.id == draggedID }) else { return }

        var reordered = soundtracks
        let movedItem = reordered.remove(at: sourceIndex)
        reordered.append(movedItem)
        soundtracks = reordered
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

    func filteredPhotoItems(for filter: PhotosExclusionFilter, in sourceItems: [PhotoItem]? = nil) -> [PhotoItem] {
        let itemsToFilter = sourceItems ?? items
        switch filter {
        case .all:
            return itemsToFilter
        case .included:
            return itemsToFilter.filter { !$0.isExcluded }
        case .excluded:
            return itemsToFilter.filter { $0.isExcluded }
        }
    }

    var filteredPhotoItems: [PhotoItem] {
        filteredPhotoItems(for: photosExclusionFilter)
    }

    var missingPhotoCount: Int {
        items.filter(\.isMissing).count
    }

    func selectPhoto(_ id: PhotoItem.ID?) {
        let normalizedID = id.flatMap { candidate in
            items.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        selectedPhotoID = normalizedID
        selectedPhotoIDs = normalizedID.map { [$0] } ?? []
        selectionAnchorPhotoID = normalizedID
    }

    func selectPhotos(_ ids: Set<PhotoItem.ID>) {
        let normalized = normalizedPhotoSelection(ids)
        selectedPhotoIDs = normalized

        selectedPhotoID = {
            if let selectedPhotoID, normalized.contains(selectedPhotoID) {
                return selectedPhotoID
            }

            return firstSelectedPhotoIDInItemOrder(normalized)
        }()

        if let anchorID = selectionAnchorPhotoID, normalized.contains(anchorID) {
            selectionAnchorPhotoID = anchorID
        } else {
            selectionAnchorPhotoID = selectedPhotoID
        }
    }

    func setPrimarySelectedPhoto(_ id: PhotoItem.ID?) {
        guard let id else {
            if selectedPhotoIDs.isEmpty {
                selectedPhotoID = nil
                selectionAnchorPhotoID = nil
            }
            return
        }

        guard selectedPhotoIDs.contains(id) else { return }
        selectedPhotoID = id
        selectionAnchorPhotoID = id
    }

    func togglePhotoSelection(_ id: PhotoItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }

        if selectedPhotoIDs.contains(id) {
            var updatedSelection = selectedPhotoIDs
            updatedSelection.remove(id)
            selectedPhotoIDs = updatedSelection

            if selectedPhotoID == id || (selectedPhotoID.map { !updatedSelection.contains($0) } ?? true) {
                selectedPhotoID = firstSelectedPhotoIDInItemOrder(updatedSelection)
            }
        } else {
            selectedPhotoIDs.insert(id)
            selectedPhotoID = id
            selectionAnchorPhotoID = id
        }

        if selectedPhotoIDs.isEmpty {
            clearPhotoSelection()
        } else if selectionAnchorPhotoID.map({ selectedPhotoIDs.contains($0) }) != true {
            selectionAnchorPhotoID = selectedPhotoID
        }
    }

    func extendPhotoSelection(to id: PhotoItem.ID, orderedIDs: [PhotoItem.ID], additive: Bool = false) {
        guard let targetIndex = orderedIDs.firstIndex(of: id) else { return }
        let anchorID = selectionAnchorPhotoID ?? selectedPhotoID ?? id
        guard let anchorIndex = orderedIDs.firstIndex(of: anchorID) else {
            selectPhoto(id)
            return
        }

        let lowerBound = min(anchorIndex, targetIndex)
        let upperBound = max(anchorIndex, targetIndex)
        let rangeSelection = normalizedPhotoSelection(Set(orderedIDs[lowerBound ... upperBound]))
        selectedPhotoIDs = additive ? selectedPhotoIDs.union(rangeSelection) : rangeSelection
        selectedPhotoID = id
        selectionAnchorPhotoID = anchorID
    }

    func toggleExcludeForSelectedPhoto() {
        let targetIDs = effectiveSelectedPhotoIDs
        guard !targetIDs.isEmpty else { return }
        toggleExclude(for: targetIDs)
    }

    func toggleExclude(for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isExcluded.toggle()
    }

    func toggleExclude(for ids: Set<PhotoItem.ID>) {
        let normalized = normalizedPhotoSelection(ids)
        guard !normalized.isEmpty else { return }

        for index in items.indices where normalized.contains(items[index].id) {
            items[index].isExcluded.toggle()
        }
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

    func setPhotosExcluded(_ isExcluded: Bool, for ids: Set<PhotoItem.ID>) {
        let normalized = normalizedPhotoSelection(ids)
        guard !normalized.isEmpty else { return }

        for index in items.indices where normalized.contains(items[index].id) {
            items[index].isExcluded = isExcluded
        }
    }

    func relinkPhoto(id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Relink"

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        guard allowedImageExtensions.contains(selectedURL.pathExtension.lowercased()) else {
            status = "Selected file is not a supported image."
            return
        }

        startSecurityScopedAccess(for: selectedURL)
        let bookmarkData = try? selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        items[index].url = selectedURL
        items[index].isMissing = false
        items[index].isRelinked = true
        items[index].relinkedPath = selectedURL.path
        items[index].relinkedBookmark = bookmarkData
        status = "Relinked \(items[index].referenceName)."
    }

    func moveSelectedPhotosUp(_ ids: Set<PhotoItem.ID>) {
        let selected = normalizedPhotoSelection(ids)
        guard !selected.isEmpty else { return }

        var reordered = items
        for index in 1..<reordered.count {
            let currentID = reordered[index].id
            let previousID = reordered[index - 1].id
            if selected.contains(currentID), !selected.contains(previousID) {
                reordered.swapAt(index, index - 1)
            }
        }
        items = reordered
    }

    func moveSelectedPhotosDown(_ ids: Set<PhotoItem.ID>) {
        let selected = normalizedPhotoSelection(ids)
        guard !selected.isEmpty else { return }

        var reordered = items
        for index in stride(from: reordered.count - 2, through: 0, by: -1) {
            let currentID = reordered[index].id
            let nextID = reordered[index + 1].id
            if selected.contains(currentID), !selected.contains(nextID) {
                reordered.swapAt(index, index + 1)
            }
        }
        items = reordered
    }

    func moveSelectedPhotosToTop(_ ids: Set<PhotoItem.ID>) {
        let selected = normalizedPhotoSelection(ids)
        guard !selected.isEmpty else { return }

        let selectedItems = items.filter { selected.contains($0.id) }
        let unselectedItems = items.filter { !selected.contains($0.id) }
        items = selectedItems + unselectedItems
    }

    func moveSelectedPhotosToBottom(_ ids: Set<PhotoItem.ID>) {
        let selected = normalizedPhotoSelection(ids)
        guard !selected.isEmpty else { return }

        let unselectedItems = items.filter { !selected.contains($0.id) }
        let selectedItems = items.filter { selected.contains($0.id) }
        items = unselectedItems + selectedItems
    }

    func setFlag(_ flag: String, enabled: Bool, for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }

        if enabled {
            items[index].flags.insert(flag)
        } else {
            items[index].flags.remove(flag)
        }
    }

    func setFlag(_ flag: String, enabled: Bool, for ids: Set<PhotoItem.ID>) {
        let normalized = normalizedPhotoSelection(ids)
        guard !normalized.isEmpty else { return }

        for index in items.indices where normalized.contains(items[index].id) {
            if enabled {
                items[index].flags.insert(flag)
            } else {
                items[index].flags.remove(flag)
            }
        }
    }

    func effectiveTransitionToNext(for item: PhotoItem) -> PhotoTransitionStyle {
        item.transitionToNext ?? defaultTransitionToNext
    }

    func effectiveSecondsPerPhoto(for item: PhotoItem) -> Double {
        item.secondsOverride ?? secondsPerImage
    }

    func effectiveTransitionDurationToNext(for item: PhotoItem) -> Double {
        item.transitionDurationToNext ?? defaultTransitionDurationToNext
    }

    func setPhotoTransitionToNext(_ transition: PhotoTransitionStyle?, for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].transitionToNext = transition
    }

    func setPhotoSecondsOverride(_ seconds: Double?, for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].secondsOverride = seconds.map { max(0.01, min(999.99, $0)) }
    }

    func setPhotoTransitionDurationToNext(_ duration: Double?, for id: PhotoItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].transitionDurationToNext = duration.map { max(0.01, min(999.99, $0)) }
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

    private var effectiveSelectedPhotoIDs: Set<PhotoItem.ID> {
        if !selectedPhotoIDs.isEmpty {
            return normalizedPhotoSelection(selectedPhotoIDs)
        }

        if let selectedPhotoID {
            return normalizedPhotoSelection([selectedPhotoID])
        }

        return []
    }

    private func normalizedPhotoSelection(_ ids: Set<PhotoItem.ID>) -> Set<PhotoItem.ID> {
        let availableIDs = Set(items.map(\.id))
        return ids.intersection(availableIDs)
    }

    private func firstSelectedPhotoIDInItemOrder(_ ids: Set<PhotoItem.ID>) -> PhotoItem.ID? {
        items.first(where: { ids.contains($0.id) })?.id
    }

    private func clearPhotoSelection() {
        selectedPhotoID = nil
        selectedPhotoIDs = []
        selectionAnchorPhotoID = nil
    }

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
        guard confirmProjectSavedIfNeeded(before: "encoding") else { return }

        guard !items.isEmpty else {
            status = "Nothing to encode."
            return
        }

        let itemsToEncode = exportableItems
        guard !itemsToEncode.isEmpty else {
            status = AppError.noExportableImages.localizedDescription
            return
        }

        let missingExportableItems = itemsToEncode.filter(\.isMissing)
        guard missingExportableItems.isEmpty else {
            status = "\(missingExportableItems.count) exportable photo(s) are missing. Relink or exclude them before encoding."
            if let firstMissing = missingExportableItems.first {
                selectPhoto(firstMissing.id)
            }
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
        startEncodingTicker()
        isEncoding = true
        isEncodingWindowPresented = true
        status = "Encoding..."
        let selectedEncoder = selectedVideoEncoder
        defer {
            isEncoding = false
            encodingTask = nil
            stopEncodingTicker()
        }

        do {
            let ffmpegURL = try resolveFFmpegURL()
            let output = try await runEncodingPass(
                ffmpegURL: ffmpegURL,
                items: items,
                outputURL: outputURL,
                videoEncoder: selectedEncoder
            )

            encodingProgress = 1
            encodingStatusLine = "Complete"
            encodingRemainingText = "00:00"
            status = output
        } catch {
            if selectedEncoder == .hardwareH264,
               case AppError.ffmpegFailed(let output) = error,
               output.localizedCaseInsensitiveContains("h264_videotoolbox") {
                do {
                    status = "Hardware encoder unavailable. Falling back to software fast mode…"
                    let ffmpegURL = try resolveFFmpegURL()
                    let fallbackOutput = try await runEncodingPass(
                        ffmpegURL: ffmpegURL,
                        items: items,
                        outputURL: outputURL,
                        videoEncoder: .softwareFastH264
                    )

                    encodingProgress = 1
                    encodingStatusLine = "Complete"
                    encodingRemainingText = "00:00"
                    status = fallbackOutput
                    return
                } catch {
                    // Fall through to standard error handling below.
                }
            }

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

    private func runEncodingPass(
        ffmpegURL: URL,
        items: [PhotoItem],
        outputURL: URL,
        videoEncoder: FFmpegEncoder.VideoEncoder
    ) async throws -> String {
        try await FFmpegEncoder.run(
            ffmpegURL: ffmpegURL,
            items: items,
            soundtracks: soundtracks,
            outputURL: outputURL,
            secondsPerImage: secondsPerImage,
            defaultTransitionToNext: defaultTransitionToNext,
            defaultTransitionDurationToNext: defaultTransitionDurationToNext,
            width: width,
            height: height,
            fps: fps,
            videoEncoder: videoEncoder
        ) { [weak self] progress, statusLine in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.encodingProgress = progress
                self.encodingStatusLine = statusLine
                self.updateEncodingTimeLabels(progress: progress)
            }
        } onLogLine: { [weak self] line in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendEncodingLogLine(line)
            }
        }
    }

    private var selectedVideoEncoder: FFmpegEncoder.VideoEncoder {
        switch encodeSpeedMode {
        case .fastestHardware:
            return .hardwareH264
        case .fastSoftware:
            return .softwareFastH264
        case .quality:
            return .softwareQualityH264
        }
    }

    func cancelEncoding() {
        guard isEncoding else { return }
        encodingStatusLine = "Cancelling…"
        status = "Cancelling…"
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
        encodingLogText = ""
    }

    private func appendEncodingLogLine(_ line: String) {
        let cappedLine = line.count > 500 ? String(line.prefix(500)) + "…" : line
        if encodingLogText.isEmpty {
            encodingLogText = cappedLine
        } else {
            encodingLogText += "\n" + cappedLine
        }

        // Keep the log window responsive by capping retained text size.
        let maxCharacters = 30_000
        if encodingLogText.count > maxCharacters {
            encodingLogText = String(encodingLogText.suffix(maxCharacters))
        }
    }

    private func startEncodingTicker() {
        encodingTickerTask?.cancel()
        encodingTickerTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await MainActor.run {
                    self.updateEncodingTimeLabels(progress: self.encodingProgress)
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopEncodingTicker() {
        encodingTickerTask?.cancel()
        encodingTickerTask = nil
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
