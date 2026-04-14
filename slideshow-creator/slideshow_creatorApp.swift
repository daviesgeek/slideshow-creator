//
//  slideshow_creatorApp.swift
//  slideshow-creator
//
//  Created by Matthew Davies on 4/14/26.
//

import SwiftUI
import SwiftData

@main
struct slideshow_creatorApp: App {
    @StateObject private var appModel = AppModel()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
        }
        .modelContainer(sharedModelContainer)

        Window("Encoding Progress", id: "encoding-progress") {
            EncodingProgressWindowView()
                .environmentObject(appModel)
        }
        .windowResizability(.contentSize)
    }
}
