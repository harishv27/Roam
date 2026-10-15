import Foundation

/// Wikipedia's geosearch returns every article with coordinates: statues and castles, but also military academies,
/// medieval kingdoms and mayors born nearby. This keeps what a visitor would want to see.
public enum AttractionRanker {
    /// Descriptions that mark a person, group or abstraction rather than a place to go.
    private static let notAPlace = try! NSRegularExpression(
        pattern: #"\b(politician|footballer|singer|actor|actress|musician|writer|poet|painter|businessman|businesswoman|journalist|athlete|player|born|company|corporation|organization|organisation|party|dynasty|kingdom|emirate|taifa|era|period|battle|war|treaty|municipality|parish|civil parish|district|freguesia|neighbourhood|constituency|ward|station|institution|institute|agency|association|bureau|ministry|committee|union|federation)\b"#,
        options: .caseInsensitive)

    /// Best first: pages with a photo, a description and a real summary, then nearer before farther. The article
    /// about the place itself ("Lisbon" when browsing Lisbon) is not a thing to see, so it is left out.
    public static func rank(_ items: [Attraction], excludingTitle placeName: String? = nil, limit: Int = 20) -> [Attraction] {
        var seen = Set<Int>()
        return items
            .filter { placeName == nil || $0.title.caseInsensitiveCompare(placeName!) != .orderedSame }
            .filter { seen.insert($0.id).inserted }
            .filter { !looksLikeNotAPlace($0) }
            .sorted { (score($0), -$0.distanceMeters) > (score($1), -$1.distanceMeters) }
            .prefix(limit).map { $0 }
    }

    static func score(_ item: Attraction) -> Int {
        (item.thumbnailURL != nil ? 4 : 0) + (item.blurb != nil ? 2 : 0) + (item.summary.count > 120 ? 1 : 0)
    }

    static func looksLikeNotAPlace(_ item: Attraction) -> Bool {
        guard let blurb = item.blurb else { return false }
        return notAPlace.firstMatch(in: blurb, range: NSRange(location: 0, length: (blurb as NSString).length)) != nil
    }
}
