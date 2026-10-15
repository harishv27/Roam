import SwiftUI
import MapKit
import RoamCore

struct AttractionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let attraction: Attraction

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let url = attraction.thumbnailURL {
                        AsyncImage(url: url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill().frame(height: 220).frame(maxWidth: .infinity).clipped()
                            } else {
                                Color.secondary.opacity(0.12).frame(height: 220)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attraction.title).font(.title2.weight(.bold))
                        if let blurb = attraction.blurb { Text(blurb).font(.subheadline).foregroundStyle(.secondary) }
                        Text("\(Format.distance(attraction.distanceMeters)) from the centre").font(.footnote).foregroundStyle(.tertiary)
                    }
                    if !attraction.summary.isEmpty { Text(attraction.summary).font(.body) }
                    HStack(spacing: 12) {
                        Button { directions() } label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent)
                        Link(destination: attraction.pageURL) { Label("Wikipedia", systemImage: "safari").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered)
                    }
                    Text("Text and photos from Wikipedia, available under free licences.").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, Theme.side)
                .padding(.bottom, 24)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func directions() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: attraction.latitude, longitude: attraction.longitude)))
        item.name = attraction.title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

struct FullMapView: View {
    @Environment(\.dismiss) private var dismiss
    let place: Place
    let attractions: [Attraction]
    let onSelect: (Attraction) -> Void
    @State private var selection: Int?

    var body: some View {
        NavigationStack {
            Map(initialPosition: .region(MapRegion.fitting(place: place, attractions: attractions)), selection: $selection) {
                Marker(place.name, systemImage: "mappin", coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                    .tint(.red).tag(-1)
                ForEach(attractions) { item in
                    Marker(item.title, coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)).tag(item.id)
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: selection) { _, id in
                guard let id, let item = attractions.first(where: { $0.id == id }) else { return }
                dismiss()
                // The sheet belongs to the screen underneath, which can only present it once this cover is gone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onSelect(item) }
            }
        }
    }
}
