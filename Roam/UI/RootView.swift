import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ExploreView()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }
            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
        }
    }
}
