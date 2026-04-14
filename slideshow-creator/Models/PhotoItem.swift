import Foundation

struct PhotoItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var isExcluded = false
    var flags: Set<String> = []

    init(url: URL, isExcluded: Bool = false, flags: Set<String> = []) {
        self.url = url
        self.isExcluded = isExcluded
        self.flags = flags
    }

    var name: String { url.lastPathComponent }
}
