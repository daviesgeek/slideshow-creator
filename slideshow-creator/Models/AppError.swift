import Foundation

enum AppError: LocalizedError {
    case ffmpegNotFound
    case ffmpegFailed(String)
    case encodingCancelled
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
        case .encodingCancelled:
            return "Encoding cancelled."
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
