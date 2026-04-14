import Foundation

struct SoundtrackItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL

    var name: String { url.lastPathComponent }
}
