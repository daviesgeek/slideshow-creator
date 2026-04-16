import Foundation

struct PhotoItem: Identifiable, Equatable {
    let id: UUID
    let referenceName: String
    var url: URL
    var isExcluded = false
    var flags: Set<String> = []
    var isMissing = false
    var isRelinked = false
    var relinkedPath: String?
    var relinkedBookmark: Data?
    var transitionToNext: PhotoTransitionStyle?
    var transitionDurationToNext: Double?

    init(
        id: UUID = UUID(),
        referenceName: String? = nil,
        url: URL,
        isExcluded: Bool = false,
        flags: Set<String> = [],
        isMissing: Bool = false,
        isRelinked: Bool = false,
        relinkedPath: String? = nil,
        relinkedBookmark: Data? = nil,
        transitionToNext: PhotoTransitionStyle? = nil,
        transitionDurationToNext: Double? = nil
    ) {
        self.id = id
        self.referenceName = referenceName ?? url.lastPathComponent
        self.url = url
        self.isExcluded = isExcluded
        self.flags = flags
        self.isMissing = isMissing
        self.isRelinked = isRelinked
        self.relinkedPath = relinkedPath
        self.relinkedBookmark = relinkedBookmark
        self.transitionToNext = transitionToNext
        self.transitionDurationToNext = transitionDurationToNext
    }

    var name: String { url.lastPathComponent }
}
