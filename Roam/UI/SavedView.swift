import SwiftUI
import SwiftData
import RoamCore

struct SavedView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPlace.savedAt, order: .reverse) private var saved: [SavedPlace]

    var body: some View {
        NavigationStack {
            Group {
                if saved.isEmpty {
                    Message(symbol: "heart", title: "Nothing saved yet",
                            detail: "Tap the heart on a place to keep it here. Saved places open without a connection.")
                } else {
                    List {
                        ForEach(saved) { item in
                            NavigationLink(value: item.place) { PlaceRow(place: item.place) }
                                .swipeActions { Button("Remove", role: .destructive) { remove(item) } }
                        }
                        Section {} footer: {
                            Text("Weather and landmarks are kept from the last time you opened each place.")
                        }
                    }
                }
            }
            .navigationTitle("Saved")
            .navigationDestination(for: Place.self) { PlaceDetailView(place: $0) }
        }
    }

    private func remove(_ item: SavedPlace) {
        context.delete(item)
        try? context.save()
    }
}
