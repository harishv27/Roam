import SwiftUI
import RoamCore

struct ExploreView: View {
    @Environment(AppServices.self) private var services
    @State private var model = SearchModel()
    @State private var query = ""
    @State private var path: [Place] = []

    private static let ideas = ["Lisbon", "Kyoto", "Cape Town", "Reykjavik", "Buenos Aires", "Marrakesh"]

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(Theme.background)
                .navigationTitle("Explore")
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search a city")
                .autocorrectionDisabled()
                // `task(id:)` cancels the previous search when the text changes, so only the latest one counts. The
                // pause is the debounce: nothing is sent while the person is still typing.
                .task(id: query) {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await model.search(query, using: services.service)
                }
                .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            ScrollView { idle.padding(.horizontal, Theme.side).padding(.bottom, 24) }
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results(let places, let stale):
            List {
                ForEach(places) { place in
                    Button { open(place) } label: { PlaceRow(place: place) }.buttonStyle(.plain)
                }
                if stale {
                    Text("You're offline. These results were saved earlier.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        case .empty:
            Message(symbol: "mappin.slash", title: "No places found", detail: "Try the city name on its own, like \"Porto\".")
        case .failed(let text):
            Message(symbol: "wifi.slash", title: text, detail: "Searching needs a connection, unless you searched for this before.")
        }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !services.recents.places.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Recent").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { services.recents.clear() }.font(.footnote)
                    }
                    VStack(spacing: 0) {
                        ForEach(services.recents.places) { place in
                            Button { open(place) } label: { PlaceRow(place: place).padding(.vertical, 8).padding(.horizontal, 14) }
                                .buttonStyle(.plain)
                            if place.id != services.recents.places.last?.id { Divider().padding(.leading, 62) }
                        }
                    }
                    .card()
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Try one of these").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                FlowChips(items: Self.ideas) { query = $0 }
            }
        }
        .padding(.top, 12)
    }

    private func open(_ place: Place) {
        services.recents.add(place)
        path.append(place)
    }
}

private struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { action(item) } label: {
                    Text(item).font(.subheadline).lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 9).frame(maxWidth: .infinity)
                        .background(Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
