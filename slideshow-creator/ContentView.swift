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

    var name: String { url.lastPathComponent }
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

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Set a valid path or install it with Homebrew."
        case .ffmpegFailed(let output):
            return "FFmpeg failed:\n\(output)"
        case .noImages:
            return "No supported images found in the selected folder."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var soundtrackFolderURL: URL?

    @Published var items: [PhotoItem] = []
    @Published var soundtracks: [SoundtrackItem] = []

    @Published var status: String = "Choose a folder to begin."
    @Published var isEncoding = false

    @Published var secondsPerImage: Double = 3
    @Published var width: Int = 1920
    @Published var height: Int = 1080
    @Published var fps: Int = 30

    // Default for Apple Silicon Homebrew. The resolver also checks other common paths.
    @Published var ffmpegPath: String = "/opt/homebrew/bin/ffmpeg"

    private let allowedImageExtensions = Set([
        "jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff"
    ])

    private let allowedAudioExtensions = Set([
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"
    ])

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"

        guard panel.runModal() == .OK, let folder = panel.url else { return }
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

            guard !imageURLs.isEmpty else {
                folderURL = folder
                items = []
                status = AppError.noImages.localizedDescription
                return
            }

            folderURL = folder
            items = imageURLs.map(PhotoItem.init(url:))
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
            soundtracks = audioURLs.map(SoundtrackItem.init(url:))

            if soundtracks.isEmpty {
                status = "No supported audio files found in selected soundtrack folder."
            } else {
                status = "Loaded \(soundtracks.count) soundtrack(s)."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func moveSoundtracks(from source: IndexSet, to destination: Int) {
        soundtracks.move(fromOffsets: source, toOffset: destination)
    }

    func chooseOutputAndEncode() {
        guard !items.isEmpty else {
            status = "Nothing to encode."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "slideshow.mp4"

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        Task {
            await encode(to: outputURL)
        }
    }

    private func encode(to outputURL: URL) async {
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
    @StateObject private var model = AppModel()
    @State private var isPreviewPresented = false
    @State private var previewIndex = 0

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack {
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
                                PhotoRow(item: item) {
                                    openPreview(for: item)
                                }
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
    let onThumbnailTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onThumbnailTap) {
                ThumbnailView(url: item.url)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .help("Open fullscreen preview")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(1)

                Text(item.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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
