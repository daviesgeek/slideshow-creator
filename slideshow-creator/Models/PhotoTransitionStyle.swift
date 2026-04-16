import Foundation

enum PhotoTransitionStyle: String, Codable, CaseIterable, Identifiable, Equatable {
    case none
    case fade
    case wipeleft
    case wiperight
    case wipeup
    case wipedown
    case slideleft
    case slideright
    case slideup
    case slidedown
    case circlecrop
    case rectcrop
    case distance
    case fadeblack
    case fadewhite
    case radial
    case smoothleft
    case smoothright
    case smoothup
    case smoothdown
    case circleopen
    case circleclose
    case vertopen
    case vertclose
    case horzopen
    case horzclose
    case dissolve
    case pixelize
    case diagtl
    case diagtr
    case diagbl
    case diagbr
    case hlslice
    case hrslice
    case vuslice
    case vdslice
    case hblur
    case fadegrays
    case wipetl
    case wipetr
    case wipebl
    case wipebr
    case squeezeh
    case squeezev
    case zoomin
    case fadefast
    case fadeslow
    case hlwind
    case hrwind
    case vuwind
    case vdwind
    case coverleft
    case coverright
    case coverup
    case coverdown
    case revealleft
    case revealright
    case revealup
    case revealdown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:
            return "None"
        default:
            return rawValue
        }
    }

    var ffmpegName: String? {
        guard self != .none else { return nil }
        return rawValue
    }
}
