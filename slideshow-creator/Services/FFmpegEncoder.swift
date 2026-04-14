import Foundation

enum FFmpegEncoder {
    nonisolated static func run(
        ffmpegURL: URL,
        items: [PhotoItem],
        soundtracks: [SoundtrackItem],
        outputURL: URL,
        secondsPerImage: Double,
        width: Int,
        height: Int,
        fps: Int,
        onProgress: @escaping @Sendable (_ progress: Double, _ statusLine: String) -> Void
    ) async throws -> String {
        final class CancellationState {
            let lock = NSLock()
            var process: Process?
        }

        let totalDuration = max(0.001, Double(items.count) * secondsPerImage)
        let cancellationState = CancellationState()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let progressPipe = Pipe()
                let stdoutPipe = Pipe()
                let parserQueue = DispatchQueue(label: "FFmpegEncoder.parser")
                let completionLock = NSLock()

                var hasCompleted = false
                var rawOutput = ""
                var partialLine = ""

                func complete(_ result: Result<String, Error>) {
                    completionLock.lock()
                    defer { completionLock.unlock() }
                    guard !hasCompleted else { return }
                    hasCompleted = true

                    progressPipe.fileHandleForReading.readabilityHandler = nil

                    cancellationState.lock.lock()
                    cancellationState.process = nil
                    cancellationState.lock.unlock()

                    switch result {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                // Use /usr/bin/env to reliably launch ffmpeg binaries from user-selected paths.
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [ffmpegURL.path] + makeArguments(
                    items: items,
                    soundtracks: soundtracks,
                    outputURL: outputURL,
                    secondsPerImage: secondsPerImage,
                    width: width,
                    height: height,
                    fps: fps
                )
                process.standardOutput = stdoutPipe
                process.standardError = progressPipe

                cancellationState.lock.lock()
                cancellationState.process = process
                cancellationState.lock.unlock()

                progressPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }

                    let text = String(decoding: data, as: UTF8.self)
                    parserQueue.async {
                        rawOutput += text
                        partialLine += text

                        while let newlineRange = partialLine.range(of: "\n") {
                            let line = String(partialLine[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            partialLine = String(partialLine[newlineRange.upperBound...])

                            guard !line.isEmpty else { continue }

                            if line.hasPrefix("out_time=") {
                                let timecode = String(line.dropFirst("out_time=".count))
                                let encodedSeconds = parseTimecode(timecode)
                                let progress = min(max(encodedSeconds / totalDuration, 0), 1)
                                onProgress(progress, "Encoding…")
                            }
                        }
                    }
                }

                process.terminationHandler = { process in
                    parserQueue.async {
                        let remainingData = progressPipe.fileHandleForReading.readDataToEndOfFile()
                        if !remainingData.isEmpty {
                            rawOutput += String(decoding: remainingData, as: UTF8.self)
                        }

                        if process.terminationStatus == 0 {
                            onProgress(1, "Finishing…")
                            complete(.success("Done: \(outputURL.path)"))
                        } else if process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGTERM {
                            complete(.failure(AppError.encodingCancelled))
                        } else {
                            complete(.failure(AppError.ffmpegFailed(rawOutput)))
                        }
                    }
                }

                do {
                    try process.run()
                } catch {
                    complete(.failure(error))
                }
            }
        } onCancel: {
            cancellationState.lock.lock()
            let process = cancellationState.process
            cancellationState.lock.unlock()

            if let process, process.isRunning {
                process.terminate()
            }
        }
    }

    nonisolated static func makeArguments(
        items: [PhotoItem],
        soundtracks: [SoundtrackItem],
        outputURL: URL,
        secondsPerImage: Double,
        width: Int,
        height: Int,
        fps: Int
    ) -> [String] {
        let slideshowDuration = Double(items.count) * secondsPerImage

        var args: [String] = ["-y", "-progress", "pipe:2", "-nostats"]

        for item in items {
            args += [
                "-loop", "1",
                "-t", String(secondsPerImage),
                "-i", item.url.path
            ]
        }

        for soundtrack in soundtracks {
            args += ["-i", soundtrack.url.path]
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

    nonisolated private static func parseTimecode(_ value: String) -> Double {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 3 else { return 0 }

        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0

        return (hours * 3600) + (minutes * 60) + seconds
    }
}
