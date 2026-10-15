import MapKit
import RoamCore

enum MapRegion {
    /// A region that shows the place and every landmark, never tighter than about 2 km.
    static func fitting(place: Place, attractions: [Attraction]) -> MKCoordinateRegion {
        let lats = [place.latitude] + attractions.map(\.latitude)
        let lons = [place.longitude] + attractions.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (lats.max()! - lats.min()!) * 1.3),
                                    longitudeDelta: max(0.02, (lons.max()! - lons.min()!) * 1.3))
        return MKCoordinateRegion(center: center, span: span)
    }
}
