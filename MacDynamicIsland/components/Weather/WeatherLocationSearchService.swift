import Foundation
import MapKit

struct WeatherLocationSearchSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    fileprivate let completion: MKLocalSearchCompletion
}

@MainActor
final class WeatherLocationSearchService: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [WeatherLocationSearchSuggestion] = []
    @Published private(set) var statusMessage: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            statusMessage = nil
            completer.queryFragment = ""
            return
        }
        statusMessage = "正在搜索…"
        completer.queryFragment = trimmed
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.enumerated().map { index, completion in
            WeatherLocationSearchSuggestion(
                id: "\(completion.title)|\(completion.subtitle)|\(index)",
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }
        statusMessage = suggestions.isEmpty ? "没有找到匹配的城市或地区" : nil
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
        statusMessage = "城市搜索暂时不可用，请稍后重试"
    }

    func resolve(_ suggestion: WeatherLocationSearchSuggestion) async throws -> WeatherManualLocation {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw WeatherLocationSearchError.noCoordinate
        }

        let placemark = item.placemark
        let displayName = WeatherLocationSearchService.displayName(
            fallback: suggestion.title,
            placemark: placemark
        )
        return WeatherManualLocation(
            displayName: displayName,
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
    }

    private static func displayName(fallback: String, placemark: MKPlacemark) -> String {
        let city = placemark.locality ?? placemark.administrativeArea
        let district = placemark.subLocality
        if let district,
           let city,
           !district.isEmpty,
           district.localizedCaseInsensitiveCompare(city) != .orderedSame {
            return "\(district) · \(city)"
        }
        return city ?? district ?? fallback
    }
}

enum WeatherLocationSearchError: LocalizedError {
    case noCoordinate

    var errorDescription: String? {
        switch self {
        case .noCoordinate:
            "没有找到可用于天气查询的位置"
        }
    }
}
