import SwiftUI
import AppKit

struct ThumbnailView: View {
    let url: URL

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .overlay(Text("No Preview").font(.caption2))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
