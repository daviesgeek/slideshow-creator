import Foundation

struct SlideshowProjectDocument: Codable {
    let version: Int
    let photosFolderPath: String?
    let soundtrackFolderPath: String?
    let photosFolderBookmark: Data?
    let soundtrackFolderBookmark: Data?
    let photoOrder: [String]
    let soundtrackOrder: [String]
    let settings: ProjectSettings
    let availableFlags: [String]?
    let selectedExportFlags: [String]?
    let exportMatchMode: String?
    let photoExcludedByName: [String: Bool]?
    let photoFlagsByName: [String: [String]]?
    let photoRelinkedPathByName: [String: String]?
    let photoRelinkedBookmarkByName: [String: Data]?
    let photoTransitionToNextByName: [String: PhotoTransitionStyle]?
    let photoTransitionDurationToNextByName: [String: Double]?
}
