import SwiftUI
import SwiftData

@main
struct RoamApp: App {
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .modelContainer(for: SavedPlace.self)
        }
    }
}
