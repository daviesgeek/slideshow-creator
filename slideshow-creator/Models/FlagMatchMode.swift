import Foundation

enum FlagMatchMode: String, Codable, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .all: return "All"
        }
    }
}
