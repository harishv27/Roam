import SwiftUI
import SwiftData
import MapKit
import RoamCore

struct PlaceDetailView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var context
    @Query private var saved: [SavedPlace]

    let place: Place
    @State private var model: PlaceDetailModel?
    @State private var selected: Attraction?
    @State private var showingMap = false
    @State private var heartTicks = 0

    private var isSaved: Bool { saved.contains { $0.placeID == place.id } }

    var body: some View {
        ScrollView {
            if let model {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let age = model.staleAge { OfflineBanner(age: age) { Task { await model.load(force: true) } } }
                    weather(model)
                    attractions(model)
                }
                .padding(.horizontal, Theme.side)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background)
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { toggleSaved() } label: { Image(systemName: isSaved ? "heart.fill" : "heart") }
                    .accessibilityLabel(isSaved ? "Remove from saved" : "Save place")
            }
        }
        .sensoryFeedback(.success, trigger: heartTicks)
        .task {
            let model = PlaceDetailModel(place: place, service: services.service)
            self.model = model
            await model.load()
        }
        .refreshable { await model?.load(force: true) }
        .sheet(item: $selected) { AttractionSheet(attraction: $0) }
        .fullScreenCover(isPresented: $showingMap) {
            FullMapView(place: place, attractions: model?.attractions?.value ?? [], onSelect: { selected = $0 })
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(place.flag.isEmpty ? "📍" : place.flag).font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.title2.weight(.bold))
                Text(place.subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Weather

    @ViewBuilder private func weather(_ model: PlaceDetailModel) -> some View {
        if let forecast = model.forecast?.value {
            WeatherCard(forecast: forecast)
        } else if let error = model.forecastError {
            ErrorCard(title: "Weather unavailable", detail: error) { Task { await model.load(force: true) } }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(40).card()
        }
    }

    // MARK: Attractions

    @ViewBuilder private func attractions(_ model: PlaceDetailModel) -> some View {
        if let items = model.attractions?.value {
            VStack(alignment: .leading, spacing: 12) {
                Text("Things to see nearby").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if items.isEmpty {
                    Text("Wikipedia has nothing listed near here.").font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16).card()
                } else {
                    MapCard(place: place, attractions: items) { showingMap = true }
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            Button { selected = item } label: { AttractionRow(attraction: item) }.buttonStyle(.plain)
                            if item.id != items.last?.id { Divider().padding(.leading, 86) }
                        }
                    }
                    .card()
                }
            }
        } else if let error = model.attractionsError {
            ErrorCard(title: "Nearby places unavailable", detail: error) { Task { await model.load(force: true) } }
        }
    }

    private func toggleSaved() {
        if let existing = saved.first(where: { $0.placeID == place.id }) { context.delete(existing) } else { context.insert(SavedPlace(place)) }
        try? context.save()
        heartTicks += 1
    }
}

// MARK: - Pieces

private struct OfflineBanner: View {
    let age: TimeInterval
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline").font(.subheadline.weight(.semibold))
                Text("Showing what was saved \(Format.age(age)).").font(.footnote)
            }
            Spacer()
            Button("Retry", action: retry).font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct ErrorCard: View {
    let title: String
    let detail: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.footnote).foregroundStyle(.secondary)
            Button("Try again", action: retry).font(.subheadline).padding(.top, 2)
        }
        .frame(maxWidth: .infinity).padding(20).card()
    }
}

private struct WeatherCard: View {
    let forecast: Forecast

    var body: some View {
        let now = forecast.current
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                WeatherIcon(code: now.weatherCode, isDay: now.isDay).font(.system(size: 40)).frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.temperature(now.temperatureC)).font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("\(WeatherCode.description(now.weatherCode)) · wind \(Format.wind(now.windKph))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            Divider()
            HStack(spacing: 0) {
                ForEach(Array(forecast.days.enumerated()), id: \.element.id) { index, day in
                    VStack(spacing: 6) {
                        Text(Format.weekday(day.date, isFirst: index == 0)).font(.caption2).foregroundStyle(.secondary)
                        WeatherIcon(code: day.weatherCode).font(.system(size: 18)).frame(height: 22)
                        Text(Format.temperature(day.highC)).font(.caption.weight(.semibold))
                        Text(Format.temperature(day.lowC)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(Format.weekday(day.date, isFirst: index == 0)), \(WeatherCode.description(day.weatherCode)), high \(Format.temperature(day.highC)), low \(Format.temperature(day.lowC))")
                }
            }
        }
        .padding(16).card()
    }
}

private struct MapCard: View {
    let place: Place
    let attractions: [Attraction]
    let open: () -> Void

    var body: some View {
        Map(initialPosition: .region(MapRegion.fitting(place: place, attractions: attractions)), interactionModes: []) {
            Marker(place.name, systemImage: "mappin", coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)).tint(.red)
            ForEach(attractions) { item in
                Annotation(item.title, coordinate: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude), anchor: .center) {
                    Circle().fill(Color.accentColor).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button(action: open) {
                Label("Open map", systemImage: "arrow.up.left.and.arrow.down.right").font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial, in: Capsule())
            }
            .padding(10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Map of \(attractions.count) places near \(place.name)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open map", open)
    }
}

private struct AttractionRow: View {
    let attraction: Attraction

    var body: some View {
        HStack(spacing: 14) {
            Thumbnail(url: attraction.thumbnailURL, size: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(attraction.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let blurb = attraction.blurb { Text(blurb).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                Text(Format.distance(attraction.distanceMeters)).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
