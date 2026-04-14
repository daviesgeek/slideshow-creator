import Foundation

struct ProjectSettings: Codable {
    let secondsPerImage: Double
    let width: Int
    let height: Int
    let fps: Int
    // Legacy field kept for backwards compatibility with older project files.
    // FFmpeg path is now a global app setting (persisted in UserDefaults),
    // so new project files do not need to store it.
    let ffmpegPath: String?

    init(
        secondsPerImage: Double,
        width: Int,
        height: Int,
        fps: Int,
        ffmpegPath: String? = nil
    ) {
        self.secondsPerImage = secondsPerImage
        self.width = width
        self.height = height
        self.fps = fps
        self.ffmpegPath = ffmpegPath
    }
}
