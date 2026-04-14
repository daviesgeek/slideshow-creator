import Foundation

enum EncodeSpeedMode: String, Codable, CaseIterable, Identifiable {
    case fastestHardware
    case fastSoftware
    case quality

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fastestHardware:
            return "Fastest (Hardware)"
        case .fastSoftware:
            return "Fast (Software)"
        case .quality:
            return "Quality (Slower)"
        }
    }
}

struct ProjectSettings: Codable {
    let secondsPerImage: Double
    let width: Int
    let height: Int
    let fps: Int
    let encodeSpeedMode: EncodeSpeedMode?
    // Legacy field kept for backwards compatibility with older project files.
    // FFmpeg path is now a global app setting (persisted in UserDefaults),
    // so new project files do not need to store it.
    let ffmpegPath: String?

    init(
        secondsPerImage: Double,
        width: Int,
        height: Int,
        fps: Int,
        encodeSpeedMode: EncodeSpeedMode = .fastestHardware,
        ffmpegPath: String? = nil
    ) {
        self.secondsPerImage = secondsPerImage
        self.width = width
        self.height = height
        self.fps = fps
        self.encodeSpeedMode = encodeSpeedMode
        self.ffmpegPath = ffmpegPath
    }
}
