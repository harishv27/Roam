import SwiftUI
import RoamCore

struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 14) {
            Text(place.flag.isEmpty ? "📍" : place.flag).font(.system(size: 28)).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.medium))
                Text(place.subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let population = place.population, population > 0 {
                Text(Format.population(population)).font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct Message: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Thumbnail: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.12)
            Image(systemName: "photo").foregroundStyle(.tertiary)
        }
    }
}

/// A weather symbol that stays visible on a white card: the cloud is grey, and the sun, rain or bolt keep their colour.
/// (The system's multicolour rendering draws clouds white, which disappears on a light background.)
struct WeatherIcon: View {
    let code: Int
    var isDay = true

    var body: some View {
        Image(systemName: WeatherCode.symbol(code, isDay: isDay))
            .symbolRenderingMode(.palette)
            .foregroundStyle(primary, secondary)
    }

    private var hasCloud: Bool { code != 0 }
    private var primary: Color { hasCloud ? Color(.systemGray3) : .yellow }
    private var secondary: Color {
        switch code {
        case 1, 2: return isDay ? .orange : .indigo
        case 51...67, 80...82: return .blue
        case 71...77, 85, 86: return .cyan
        case 95...99: return .yellow
        default: return Color(.systemGray3)
        }
    }
}
