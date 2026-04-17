import Foundation

enum FFmpegEncoder {
    enum VideoEncoder {
        case hardwareH264
        case softwareFastH264
        case softwareQualityH264
    }

    struct BoundaryTransition {
        let style: PhotoTransitionStyle
        let duration: Double
    }

    struct TransitionPlan {
        let internalTransitions: [BoundaryTransition]
        let terminalTransition: BoundaryTransition?
        let contentDurations: [Double]
        let inputDurations: [Double]
        let totalDuration: Double
    }

    nonisolated static func run(
        ffmpegURL: URL,
        items: [PhotoItem],
        soundtracks: [SoundtrackItem],
        outputURL: URL,
        secondsPerImage: Double,
        defaultTransitionToNext: PhotoTransitionStyle,
        defaultTransitionDurationToNext: Double,
        width: Int,
        height: Int,
        fps: Int,
        videoEncoder: VideoEncoder,
        onProgress: @escaping @Sendable (_ progress: Double, _ statusLine: String) -> Void,
        onLogLine: @escaping @Sendable (_ line: String) -> Void
    ) async throws -> String {
        let transitionPlan = try makeTransitionPlan(
            items: items,
            secondsPerImage: secondsPerImage,
            defaultTransitionToNext: defaultTransitionToNext,
            defaultTransitionDurationToNext: defaultTransitionDurationToNext,
            fps: fps
        )

        final class CancellationState: @unchecked Sendable {
            let lock = NSLock()
            var process: Process?
            var didRequestCancellation = false
        }

        let totalDuration = max(0.001, transitionPlan.totalDuration)
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
                    width: width,
                    height: height,
                    fps: fps,
                    videoEncoder: videoEncoder,
                    transitionPlan: transitionPlan
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
                            onLogLine(line)

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

                        cancellationState.lock.lock()
                        let didRequestCancellation = cancellationState.didRequestCancellation
                        cancellationState.lock.unlock()

                        if didRequestCancellation {
                            complete(.failure(AppError.encodingCancelled))
                        } else if process.terminationStatus == 0 {
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
            cancellationState.didRequestCancellation = true
            cancellationState.lock.unlock()

            if let process, process.isRunning {
                process.interrupt()
                process.terminate()

                // Last-resort hard kill if ffmpeg ignores terminate.
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }

    nonisolated static func makeTransitionPlan(
        items: [PhotoItem],
        secondsPerImage: Double,
        defaultTransitionToNext: PhotoTransitionStyle,
        defaultTransitionDurationToNext: Double,
        fps: Int
    ) throws -> TransitionPlan {
        guard secondsPerImage > 0 else {
            throw AppError.invalidTransition("Seconds/photo must be greater than zero.")
        }

        let normalizedFPS = max(1, fps)
        let frameQuantum = 1.0 / Double(normalizedFPS)
        let minimumPhotoDuration = frameQuantum * 2

        func normalizedDuration(_ value: Double) -> Double {
            let rounded = (value / frameQuantum).rounded() * frameQuantum
            return max(frameQuantum, rounded)
        }

        func resolvedPhotoDuration(_ value: Double) -> Double {
            max(minimumPhotoDuration, normalizedDuration(value))
        }

        func resolvedTransitionDuration(_ value: Double, maxAllowed: Double) -> Double {
            guard maxAllowed > 0 else { return 0 }

            let rounded = normalizedDuration(value)
            if rounded >= maxAllowed {
                return min(1.0, maxAllowed)
            }
            return min(rounded, maxAllowed)
        }

        let contentDurations = items.map { item in
            let seconds = item.isSecondsOverrideEnabled ? (item.secondsOverride ?? secondsPerImage) : secondsPerImage
            return resolvedPhotoDuration(seconds)
        }

        var internalTransitions: [BoundaryTransition] = []
        internalTransitions.reserveCapacity(max(items.count - 1, 0))

        for index in 0..<max(items.count - 1, 0) {
            let style = items[index].isTransitionOverrideEnabled
                ? (items[index].transitionToNext ?? defaultTransitionToNext)
                : defaultTransitionToNext

            if style == .none {
                internalTransitions.append(BoundaryTransition(style: .none, duration: 0))
                continue
            }

            let durationValue = items[index].isTransitionOverrideEnabled
                ? (items[index].transitionDurationToNext ?? defaultTransitionDurationToNext)
                : defaultTransitionDurationToNext
            let maxAllowed = min(contentDurations[index], contentDurations[index + 1]) - frameQuantum
            let duration = resolvedTransitionDuration(durationValue, maxAllowed: maxAllowed)

            guard duration > 0 else {
                internalTransitions.append(BoundaryTransition(style: .none, duration: 0))
                continue
            }

            internalTransitions.append(BoundaryTransition(style: style, duration: duration))
        }

        let terminalTransition: BoundaryTransition?
        if let lastItem = items.last {
            let style = lastItem.isTransitionOverrideEnabled
                ? (lastItem.transitionToNext ?? defaultTransitionToNext)
                : defaultTransitionToNext
            if style == .none {
                terminalTransition = nil
            } else {
                let durationValue = lastItem.isTransitionOverrideEnabled
                    ? (lastItem.transitionDurationToNext ?? defaultTransitionDurationToNext)
                    : defaultTransitionDurationToNext
                let maxAllowed = contentDurations[items.count - 1] - frameQuantum
                let duration = resolvedTransitionDuration(durationValue, maxAllowed: maxAllowed)

                terminalTransition = duration > 0
                    ? BoundaryTransition(style: style, duration: duration)
                    : nil
            }
        } else {
            terminalTransition = nil
        }

        var inputDurations = contentDurations
        for index in internalTransitions.indices {
            guard internalTransitions[index].style != .none, internalTransitions[index].duration > 0 else { continue }
            inputDurations[index] += internalTransitions[index].duration
        }

        let totalDuration = contentDurations.reduce(0, +)
        return TransitionPlan(
            internalTransitions: internalTransitions,
            terminalTransition: terminalTransition,
            contentDurations: contentDurations,
            inputDurations: inputDurations,
            totalDuration: totalDuration
        )
    }

    nonisolated static func makeArguments(
        items: [PhotoItem],
        soundtracks: [SoundtrackItem],
        outputURL: URL,
        width: Int,
        height: Int,
        fps: Int,
        videoEncoder: VideoEncoder,
        transitionPlan: TransitionPlan
    ) -> [String] {
        let targetVideoBitrate = recommendedVideoBitrate(width: width, height: height, fps: fps)

        var args: [String] = ["-y", "-hide_banner", "-progress", "pipe:2", "-nostats", "-sws_flags", "fast_bilinear"]

        for (index, item) in items.enumerated() {
            args += [
                "-loop", "1",
                "-t", ffmpegTime(transitionPlan.inputDurations[index]),
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
                "fps=\(fps)," +
                "format=yuv420p," +
                "settb=AVTB," +
                "setpts=PTS-STARTPTS" +
                "[p\(index)]"
            filterParts.append(part)
        }

        let groups = makeHardCutGroups(itemCount: items.count, transitions: transitionPlan.internalTransitions)
        var groupOutputLabels: [String] = []

        for (groupIndex, range) in groups.enumerated() {
            if range.lowerBound == range.upperBound {
                groupOutputLabels.append("p\(range.lowerBound)")
                continue
            }

            var currentLabel = "p\(range.lowerBound)"
            var cumulativeDuration = transitionPlan.contentDurations[range.lowerBound]

            for boundaryIndex in range.lowerBound..<range.upperBound {
                let transition = transitionPlan.internalTransitions[boundaryIndex]
                guard transition.style != .none, transition.duration > 0 else { continue }

                let nextLabel = "p\(boundaryIndex + 1)"
                let outputLabel = "g\(groupIndex)_x\(boundaryIndex)"
                let offset = cumulativeDuration

                filterParts.append(
                    "[\(currentLabel)][\(nextLabel)]" +
                    "xfade=transition=\(transition.style.rawValue):duration=\(ffmpegTime(transition.duration)):offset=\(ffmpegTime(offset))" +
                    "[\(outputLabel)]"
                )

                currentLabel = outputLabel
                cumulativeDuration += transitionPlan.contentDurations[boundaryIndex + 1]
            }

            groupOutputLabels.append(currentLabel)
        }

        let contentLabel: String
        switch groupOutputLabels.count {
        case 0:
            contentLabel = "v"
            filterParts.append("color=c=black:s=\(width)x\(height):r=\(fps):d=0.001,format=yuv420p[v]")
        case 1:
            contentLabel = groupOutputLabels[0]
        default:
            let concatInputs = groupOutputLabels.map { "[\($0)]" }.joined()
            contentLabel = "v_content"
            filterParts.append("\(concatInputs)concat=n=\(groupOutputLabels.count):v=1:a=0[\(contentLabel)]")
        }

        let finalVideoLabel: String
        if let terminalTransition = transitionPlan.terminalTransition {
            let blackLabel = "v_black"
            let terminalLabel = "v"
            let offset = max(0, transitionPlan.totalDuration - terminalTransition.duration)

            filterParts.append(
                "color=c=black:s=\(width)x\(height):r=\(fps):d=\(ffmpegTime(max(transitionPlan.totalDuration, terminalTransition.duration)))," +
                "format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS" +
                "[\(blackLabel)]"
            )
            filterParts.append(
                "[\(contentLabel)][\(blackLabel)]" +
                "xfade=transition=\(terminalTransition.style.rawValue):duration=\(ffmpegTime(terminalTransition.duration)):offset=\(ffmpegTime(offset))" +
                "[\(terminalLabel)]"
            )
            finalVideoLabel = terminalLabel
        } else {
            finalVideoLabel = contentLabel
        }

        if !soundtracks.isEmpty {
            let audioStartIndex = items.count

            for index in soundtracks.indices {
                let inputIndex = audioStartIndex + index
                filterParts.append("[\(inputIndex):a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a\(index)]")
            }

            let audioConcatInputs = soundtracks.indices.map { "[a\($0)]" }.joined()
            filterParts.append("\(audioConcatInputs)concat=n=\(soundtracks.count):v=0:a=1,atrim=0:\(ffmpegTime(transitionPlan.totalDuration))[a]")
        }

        args += [
            "-filter_complex", filterParts.joined(separator: ";"),
            "-map", "[\(finalVideoLabel)]",
            "-r", "\(fps)"
        ]

        switch videoEncoder {
        case .hardwareH264:
            args += [
                "-c:v", "h264_videotoolbox",
                "-b:v", targetVideoBitrate,
                "-pix_fmt", "yuv420p"
            ]
        case .softwareFastH264:
            args += [
                "-c:v", "libx264",
                "-preset", "ultrafast",
                "-crf", "28",
                "-threads", "0",
                "-pix_fmt", "yuv420p"
            ]
        case .softwareQualityH264:
            args += [
                "-c:v", "libx264",
                "-preset", "medium",
                "-crf", "20",
                "-threads", "0",
                "-pix_fmt", "yuv420p"
            ]
        }

        args += [
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

    nonisolated private static func makeHardCutGroups(itemCount: Int, transitions: [BoundaryTransition]) -> [ClosedRange<Int>] {
        guard itemCount > 0 else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var start = 0

        for boundaryIndex in 0..<max(itemCount - 1, 0) {
            let transition = transitions[boundaryIndex]
            if transition.style == .none || transition.duration <= 0 {
                ranges.append(start...boundaryIndex)
                start = boundaryIndex + 1
            }
        }

        ranges.append(start...(itemCount - 1))
        return ranges
    }

    nonisolated private static func ffmpegTime(_ value: Double) -> String {
        let precision = String(format: "%.6f", value)
        let trimmed = precision
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
        return trimmed.isEmpty ? "0" : trimmed
    }

    nonisolated private static func parseTimecode(_ value: String) -> Double {
        let parts = value.split(separator: ":").map(String.init)
        guard parts.count == 3 else { return 0 }

        let hours = Double(parts[0]) ?? 0
        let minutes = Double(parts[1]) ?? 0
        let seconds = Double(parts[2]) ?? 0

        return (hours * 3600) + (minutes * 60) + seconds
    }

    nonisolated private static func recommendedVideoBitrate(width: Int, height: Int, fps: Int) -> String {
        let pixelsPerSecond = width * height * max(fps, 1)

        switch pixelsPerSecond {
        case ...27_648_000: // up to 1280x720 @ 30 fps
            return "4M"
        case ...62_208_000: // up to 1920x1080 @ 30 fps
            return "8M"
        case ...124_416_000: // up to 1920x1080 @ 60 fps
            return "12M"
        case ...221_184_000: // up to 2560x1440 @ 60 fps
            return "20M"
        default: // 4K and above
            return "30M"
        }
    }
}
