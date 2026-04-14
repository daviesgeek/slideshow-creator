import Foundation

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
            let pipe = Pipe()
            let ffmpegArguments = makeArguments(
                items: items,
                soundtracks: soundtracks,
                outputURL: outputURL,
                secondsPerImage: secondsPerImage,
                width: width,
                height: height,
                fps: fps
            )

            func makeProcess(executableURL: URL, arguments: [String]) -> Process {
                let process = Process()

                process.executableURL = executableURL
                process.arguments = arguments
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

                return process
            }

            let primary = makeProcess(executableURL: ffmpegURL, arguments: ffmpegArguments)
            do {
                try primary.run()
            } catch {
                // Fallback launch path for environments where direct executable launch fails.
                let fallback = makeProcess(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: [ffmpegURL.path] + ffmpegArguments
                )

                do {
                    try fallback.run()
                } catch {
                    continuation.resume(throwing: error)
                }
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
}
