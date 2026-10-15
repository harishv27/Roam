import Foundation

public enum Geo {
    /// Great-circle distance in metres (haversine).
    public static func distance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }

    /// "350 m", "1.2 km", or miles for the imperial system. Rounded so the text does not jitter.
    public static func format(meters: Double, metric: Bool) -> String {
        if metric {
            if meters < 950 { return "\(Int((meters / 10).rounded() * 10)) m" }
            let km = meters / 1000
            return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
        }
        let miles = meters / 1609.344
        if miles < 0.15 { return "\(Int((meters * 3.28084 / 10).rounded() * 10)) ft" }
        return miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles.rounded())) mi"
    }
}
