import AppKit
import CoreLocation
import Foundation

enum WeatherSettingsLocationAction: Equatable {
    case requestAuthorization
    case refreshWeather
    case openSystemSettings
}

enum WeatherLocationPolicy {
    static let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
}

enum WeatherLocationQualityPolicy {
    static let maximumAge: TimeInterval = 120
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 10_000

    static func bestLocation(from locations: [CLLocation], now: Date = Date()) -> CLLocation? {
        locations
            .filter { location in
                let age = now.timeIntervalSince(location.timestamp)
                return location.horizontalAccuracy >= 0
                    && location.horizontalAccuracy <= maximumHorizontalAccuracy
                    && age >= -5
                    && age <= maximumAge
            }
            .min { lhs, rhs in
                if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
    }
}

enum WeatherCurrentLocationFeedbackPolicy {
    static let duration: TimeInterval = 8

    static func shouldHighlight(
        isAutomaticLocation: Bool,
        isLoading: Bool,
        refreshedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isAutomaticLocation else { return false }
        if isLoading { return true }
        guard let refreshedAt else { return false }
        let age = now.timeIntervalSince(refreshedAt)
        return age >= 0 && age < duration
    }
}

struct WeatherManualLocation: Codable, Equatable {
    let displayName: String
    let latitude: Double
    let longitude: Double
}

struct WeatherLocationSelection: Codable, Equatable {
    enum Mode: String, Codable {
        case automatic
        case manual
    }

    let mode: Mode
    let manualLocation: WeatherManualLocation?

    static let automatic = WeatherLocationSelection(mode: .automatic, manualLocation: nil)

    static func manual(_ location: WeatherManualLocation) -> WeatherLocationSelection {
        WeatherLocationSelection(mode: .manual, manualLocation: location)
    }

    var cacheIdentity: String {
        guard mode == .manual, let manualLocation else { return "automatic" }
        return String(
            format: "manual:%.6f,%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            manualLocation.latitude,
            manualLocation.longitude
        )
    }
}

enum WeatherProviderPreference: String, CaseIterable, Codable, Identifiable, Equatable {
    case automatic
    case qWeather
    case openMeteo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic: "自动选择"
        case .qWeather: "和风天气 QWeather"
        case .openMeteo: "Open-Meteo"
        }
    }
}

enum WeatherDataSource: String, Codable, Equatable {
    case qWeather
    case openMeteo

    var displayName: String {
        switch self {
        case .qWeather: "和风天气"
        case .openMeteo: "Open-Meteo"
        }
    }

    var attributionURL: URL {
        switch self {
        case .qWeather: URL(string: "https://www.qweather.com/en/terms/")!
        case .openMeteo: URL(string: "https://open-meteo.com/en/license")!
        }
    }
}

enum WeatherProviderSelectionPolicy {
    static func requestOrder(
        preference: WeatherProviderPreference,
        hasQWeatherCredentials: Bool
    ) -> [WeatherDataSource] {
        switch preference {
        case .automatic:
            hasQWeatherCredentials ? [.qWeather, .openMeteo] : [.openMeteo]
        case .qWeather:
            [.qWeather]
        case .openMeteo:
            [.openMeteo]
        }
    }

    static func cacheSourceMatches(
        _ source: WeatherDataSource,
        preference: WeatherProviderPreference
    ) -> Bool {
        switch preference {
        case .automatic: true
        case .qWeather: source == .qWeather
        case .openMeteo: source == .openMeteo
        }
    }
}

enum HomeModule: String, CaseIterable, Codable, Identifiable, Equatable {
    case player
    case todo
    case calendar
    case weather

    var id: String { rawValue }
}

enum HomeModuleOrderPolicy {
    static let defaultOrder: [HomeModule] = [.player, .todo, .calendar, .weather]

    static func normalized(_ order: [HomeModule]) -> [HomeModule] {
        var unique: [HomeModule] = []
        for module in order where !unique.contains(module) {
            unique.append(module)
        }
        for module in defaultOrder where !unique.contains(module) {
            unique.append(module)
        }
        return unique
    }

    static func visibleOrder(
        order: [HomeModule],
        showTodo: Bool,
        showCalendar: Bool,
        showWeather: Bool
    ) -> [HomeModule] {
        normalized(order).filter { module in
            switch module {
            case .player: true
            case .todo: showTodo
            case .calendar: showCalendar
            case .weather: showWeather
            }
        }
    }

    static func moving(
        _ order: [HomeModule],
        _ source: HomeModule,
        before destination: HomeModule
    ) -> [HomeModule] {
        var normalizedOrder = normalized(order)
        guard source != destination,
              let sourceIndex = normalizedOrder.firstIndex(of: source),
              let destinationIndex = normalizedOrder.firstIndex(of: destination) else {
            return normalizedOrder
        }
        normalizedOrder.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        normalizedOrder.insert(source, at: insertionIndex)
        return normalizedOrder
    }

    /// Moves a module into the horizontal slot currently occupied by the
    /// destination. The remaining modules close the gap while preserving
    /// their relative order.
    static func reordering(
        _ order: [HomeModule],
        moving source: HomeModule,
        to destination: HomeModule
    ) -> [HomeModule] {
        var normalizedOrder = normalized(order)
        guard source != destination,
              let sourceIndex = normalizedOrder.firstIndex(of: source),
              let destinationIndex = normalizedOrder.firstIndex(of: destination)
        else { return normalizedOrder }

        normalizedOrder.remove(at: sourceIndex)
        normalizedOrder.insert(source, at: min(destinationIndex, normalizedOrder.count))
        return normalizedOrder
    }

    static func swapping(
        _ order: [HomeModule],
        _ source: HomeModule,
        with destination: HomeModule
    ) -> [HomeModule] {
        var normalizedOrder = normalized(order)
        guard source != destination,
              let sourceIndex = normalizedOrder.firstIndex(of: source),
              let destinationIndex = normalizedOrder.firstIndex(of: destination) else {
            return normalizedOrder
        }
        normalizedOrder.swapAt(sourceIndex, destinationIndex)
        return normalizedOrder
    }

    static func shifting(
        _ order: [HomeModule],
        module: HomeModule,
        horizontalOffset: Int
    ) -> [HomeModule] {
        var normalizedOrder = normalized(order)
        guard horizontalOffset != 0,
              let currentIndex = normalizedOrder.firstIndex(of: module)
        else { return normalizedOrder }

        let targetIndex = currentIndex + (horizontalOffset < 0 ? -1 : 1)
        guard normalizedOrder.indices.contains(targetIndex) else {
            return normalizedOrder
        }
        normalizedOrder.swapAt(currentIndex, targetIndex)
        return normalizedOrder
    }

    static func shouldShowLyrics(
        enableLyrics: Bool,
        showTodo: Bool,
        showCalendar: Bool,
        showWeather: Bool
    ) -> Bool {
        enableLyrics && !showTodo && !showCalendar && !showWeather
    }
}

enum WeatherSettingsInteractionPolicy {
    static func locationAction(
        authorizationStatus: CLAuthorizationStatus,
        isLoading: Bool
    ) -> WeatherSettingsLocationAction? {
        guard !isLoading else { return nil }
        switch authorizationStatus {
        case .notDetermined:
            return .requestAuthorization
        case .authorizedAlways:
            return .refreshWeather
        case .denied, .restricted:
            return .openSystemSettings
        @unknown default:
            return nil
        }
    }
}

enum WeatherAutomaticLocationAction: Equatable {
    case requestAuthorization
    case requestLocation
    case showPermissionHelp
    case unavailable
}

enum WeatherAutomaticLocationPolicy {
    static func action(for authorizationStatus: CLAuthorizationStatus) -> WeatherAutomaticLocationAction {
        switch authorizationStatus {
        case .notDetermined:
            return .requestAuthorization
        case .authorizedAlways:
            return .requestLocation
        case .denied, .restricted:
            return .showPermissionHelp
        @unknown default:
            return .unavailable
        }
    }

    static func shouldActivateApplication(for action: WeatherAutomaticLocationAction) -> Bool {
        action == .requestAuthorization
    }

    static func statusMessage(for action: WeatherAutomaticLocationAction) -> String? {
        switch action {
        case .requestAuthorization:
            return "请在系统弹窗中允许定位"
        case .requestLocation:
            return nil
        case .showPermissionHelp:
            return "请允许定位，以显示当前地区天气"
        case .unavailable:
            return "暂时无法获取定位权限状态"
        }
    }
}

struct WeatherLocationControlsLayout: Equatable {
    let spacing: CGFloat = 5
    let horizontalPadding: CGFloat = 6
    let verticalPadding: CGFloat = 4
    let statusIconSize: CGFloat = 12

    var estimatedTotalWidth: CGFloat {
        let switchCityButtonWidth: CGFloat = 61
        let currentLocationButtonWidth: CGFloat = 61
        return switchCityButtonWidth + currentLocationButtonWidth + statusIconSize + spacing * 2
    }
}

enum WeatherTrailingAccessory: Equatable {
    case source
    case progress
    case error
}

enum WeatherTrailingAccessoryPolicy {
    static func accessory(
        isLoading: Bool,
        isResolvingCity: Bool,
        statusMessage: String?
    ) -> WeatherTrailingAccessory {
        if isLoading || isResolvingCity { return .progress }
        if statusMessage != nil { return .error }
        return .source
    }
}

enum WeatherCityPickerLayout {
    static func width(visibleScreenWidth: CGFloat) -> CGFloat {
        min(380, max(340, visibleScreenWidth * 0.25))
    }

    static func height(visibleScreenHeight: CGFloat) -> CGFloat {
        min(340, max(300, visibleScreenHeight * 0.36))
    }
}

@MainActor
enum WeatherSettingsWindowFocus {
    @discardableResult
    static func activate(_ window: NSWindow?) -> Bool {
        guard let window, window.canBecomeKey else { return false }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

@MainActor
final class WeatherSettingsFocusView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        Task { @MainActor [weak self] in
            WeatherSettingsWindowFocus.activate(self?.window)
        }
    }
}

struct MusicToolbarLayout: Equatable {
    let hasSidebar: Bool

    var verticalOffset: CGFloat { hasSidebar ? -12 : 0 }
    var visualScale: CGFloat { 1 }
    var spacing: CGFloat { 6 }
    var usesCenteredCompactGroup: Bool { hasSidebar }
}

struct BoringHeaderEdgeInsets: Equatable {
    let leading: CGFloat
    let trailing: CGFloat
}

enum NotchShellLayout {
    static let additionalHorizontalInset: CGFloat = 12

    static func shapeHorizontalInset(cornerRadiusScaling: Bool) -> CGFloat {
        cornerRadiusScaling ? 19 : 24
    }

    static func contentHorizontalInset(cornerRadiusScaling: Bool) -> CGFloat {
        shapeHorizontalInset(cornerRadiusScaling: cornerRadiusScaling)
            + additionalHorizontalInset
    }

    static func contentHorizontalPadding(cornerRadiusScaling: Bool) -> CGFloat {
        contentHorizontalInset(cornerRadiusScaling: cornerRadiusScaling) * 2
    }
}

enum BoringHeaderLayout {
    static let controlSpacing: CGFloat = 1.5
    static let tabButtonSize: CGFloat = 32
    static let batteryPercentageMinimumWidth: CGFloat = 38

    /// The outer notch container already supplies symmetric horizontal padding.
    /// Keep both header groups on that same edge regardless of module count.
    static func edgeInsets(sidebarCount _: Int) -> BoringHeaderEdgeInsets {
        BoringHeaderEdgeInsets(leading: 0, trailing: 0)
    }
}

enum HomeModuleOrderSettingsLayout {
    static let cardSpacing: CGFloat = 9
    static let maximumCardWidth: CGFloat = 108

    static func cardWidth(availableWidth: CGFloat, moduleCount: Int = 4) -> CGFloat {
        guard moduleCount > 0 else { return 0 }
        let spacingWidth = CGFloat(max(0, moduleCount - 1)) * cardSpacing
        return min(
            maximumCardWidth,
            max(1, floor((availableWidth - spacingWidth) / CGFloat(moduleCount)))
        )
    }
}

struct WeatherSnapshot: Codable, Equatable {
    let locationName: String
    let locationIdentity: String
    let temperatureCelsius: Int
    let humidityPercent: Int
    let conditionText: String
    let iconCode: String
    let source: WeatherDataSource
    let observedAt: Date
    let fetchedAt: Date

    init(
        locationName: String,
        locationIdentity: String = WeatherLocationSelection.automatic.cacheIdentity,
        temperatureCelsius: Int,
        humidityPercent: Int,
        conditionText: String,
        iconCode: String,
        source: WeatherDataSource = .openMeteo,
        observedAt: Date,
        fetchedAt: Date
    ) {
        self.locationName = locationName
        self.locationIdentity = locationIdentity
        self.temperatureCelsius = temperatureCelsius
        self.humidityPercent = humidityPercent
        self.conditionText = conditionText
        self.iconCode = iconCode
        self.source = source
        self.observedAt = observedAt
        self.fetchedAt = fetchedAt
    }

    init(
        response: OpenMeteoCurrentResponse,
        locationName: String,
        locationIdentity: String = WeatherLocationSelection.automatic.cacheIdentity,
        fetchedAt: Date
    ) {
        self.init(
            locationName: locationName,
            locationIdentity: locationIdentity,
            temperatureCelsius: Int(response.current.temperature2m.rounded()),
            humidityPercent: response.current.relativeHumidity2m,
            conditionText: WMOWeatherMapper.description(for: response.current.weatherCode),
            iconCode: String(response.current.weatherCode),
            source: .openMeteo,
            observedAt: fetchedAt,
            fetchedAt: fetchedAt
        )
    }


    init(
        response: QWeatherNowResponse,
        locationName: String,
        locationIdentity: String = WeatherLocationSelection.automatic.cacheIdentity,
        fetchedAt: Date
    ) throws {
        guard response.code == "200",
              let temperature = Int(response.now.temp),
              let humidity = Int(response.now.humidity) else {
            throw WeatherCoreError.invalidPayload
        }
        let observedAt = ISO8601DateFormatter().date(from: response.now.obsTime) ?? fetchedAt
        self.init(
            locationName: locationName,
            locationIdentity: locationIdentity,
            temperatureCelsius: temperature,
            humidityPercent: humidity,
            conditionText: response.now.text,
            iconCode: response.now.icon,
            source: .qWeather,
            observedAt: observedAt,
            fetchedAt: fetchedAt
        )
    }
}

struct OpenMeteoCurrentResponse: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature2m: Double
        let relativeHumidity2m: Int
        let isDay: Int
        let weatherCode: Int

        private enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case isDay = "is_day"
            case weatherCode = "weather_code"
        }
    }

    let current: Current
}

struct QWeatherNowResponse: Decodable {
    struct Now: Decodable {
        let obsTime: String
        let temp: String
        let icon: String
        let text: String
        let humidity: String
    }

    let code: String
    let updateTime: String?
    let now: Now
}

enum WeatherCoreError: Error, Equatable {
    case invalidURL
    case invalidHost
    case invalidPayload
}

enum QWeatherHostValidator {
    static func normalizedHost(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WeatherCoreError.invalidHost }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let rawHost = components.host else {
            throw WeatherCoreError.invalidHost
        }

        let host = rawHost.lowercased()
        let isOfficialHost = host == "devapi.qweather.com"
            || host == "api.qweather.com"
            || (host.hasSuffix(".qweatherapi.com") && host != "qweatherapi.com")
        guard isOfficialHost else { throw WeatherCoreError.invalidHost }
        return host
    }
}

enum QWeatherRequestBuilder {
    static func weatherURL(
        apiHost: String,
        longitude: Double,
        latitude: Double
    ) throws -> URL {
        let host = try QWeatherHostValidator.normalizedHost(apiHost)
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v7/weather/now"
        components.queryItems = [
            URLQueryItem(name: "location", value: coordinate(longitude) + "," + coordinate(latitude)),
            URLQueryItem(name: "lang", value: "zh"),
            URLQueryItem(name: "unit", value: "m"),
        ]
        guard let url = components.url else { throw WeatherCoreError.invalidURL }
        return url
    }

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

enum WeatherCachePolicy {
    static let cacheKey = "MacDynamicIsland.weather.snapshot.v5"
    static let legacyCacheKeys = [
        "MacDynamicIsland.weather.snapshot.v1",
        "MacDynamicIsland.weather.snapshot.v2",
        "MacDynamicIsland.weather.snapshot.v3",
        "MacDynamicIsland.weather.snapshot.v4",
    ]
    static let refreshInterval: TimeInterval = 15 * 60

    static func isFresh(_ snapshot: WeatherSnapshot, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince(snapshot.fetchedAt)
        return age >= 0 && age < refreshInterval
    }

    static func isFresh(
        _ snapshot: WeatherSnapshot,
        matching selection: WeatherLocationSelection,
        preference: WeatherProviderPreference = .automatic,
        now: Date = Date()
    ) -> Bool {
        snapshot.locationIdentity == selection.cacheIdentity
            && WeatherProviderSelectionPolicy.cacheSourceMatches(snapshot.source, preference: preference)
            && isFresh(snapshot, now: now)
    }
}

enum WeatherIconMapper {
    static func systemSymbol(for code: String, source: WeatherDataSource = .openMeteo) -> String {
        if source == .qWeather {
            return qWeatherSystemSymbol(for: code)
        }
        guard let value = Int(code) else { return "cloud.fill" }
        switch value {
        case 0, 1:
            return "sun.max.fill"
        case 2:
            return "cloud.sun.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82:
            return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    private static func qWeatherSystemSymbol(for code: String) -> String {
        guard let value = Int(code) else { return "cloud.fill" }
        switch value {
        case 100, 150:
            return value == 150 ? "moon.stars.fill" : "sun.max.fill"
        case 101, 102, 103, 151, 152, 153:
            return value >= 150 ? "cloud.moon.fill" : "cloud.sun.fill"
        case 104, 154:
            return "cloud.fill"
        case 300...399:
            return value == 302 || value == 303 || value == 304 ? "cloud.bolt.rain.fill" : "cloud.rain.fill"
        case 400...499:
            return "cloud.snow.fill"
        case 500...515:
            return "cloud.fog.fill"
        default:
            return "cloud.fill"
        }
    }
}

enum WMOWeatherMapper {
    static func description(for code: Int) -> String {
        switch code {
        case 0: return "晴"
        case 1: return "晴间多云"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51: return "毛毛雨"
        case 53, 55: return "毛毛雨"
        case 56, 57: return "冻毛毛雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 66, 67: return "冻雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75: return "大雪"
        case 77: return "米雪"
        case 80: return "小阵雨"
        case 81: return "阵雨"
        case 82: return "强阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷暴"
        case 96, 99: return "雷暴伴冰雹"
        default: return "天气未知"
        }
    }
}

struct NotchHomeLayout: Equatable {
    let closedNotchWidth: CGFloat
    let showTodo: Bool
    let showCalendar: Bool
    let showWeather: Bool
    let availableScreenWidth: CGFloat?
    let contentHorizontalPadding: CGFloat

    private static let sidebarWidth: CGFloat = 165
    private static let compactWidthIncrement: CGFloat = 352
    private static let dividerAndSpacingPerSidebar: CGFloat = 17
    private static let legacyContentHorizontalPadding: CGFloat = 46
    private static let minimumSidebarPlayerWidth: CGFloat = 330
    private static let minimumConstrainedPlayerWidth: CGFloat = 220
    private static let screenHorizontalMargin: CGFloat = 32
    private static let maximumWindowContentWidth: CGFloat = 1176

    init(
        closedNotchWidth: CGFloat,
        showTodo: Bool,
        showCalendar: Bool,
        showWeather: Bool,
        availableScreenWidth: CGFloat? = nil,
        contentHorizontalPadding: CGFloat = Self.legacyContentHorizontalPadding
    ) {
        self.closedNotchWidth = closedNotchWidth
        self.showTodo = showTodo
        self.showCalendar = showCalendar
        self.showWeather = showWeather
        self.availableScreenWidth = availableScreenWidth
        self.contentHorizontalPadding = contentHorizontalPadding
    }

    var sidebarCount: Int {
        [showTodo, showCalendar, showWeather].filter { $0 }.count
    }

    var playerWidth: CGFloat {
        guard sidebarCount > 0 else { return closedNotchWidth + 252 }

        let legacyWidth = closedNotchWidth + 79
        let preferredWidth = max(legacyWidth, Self.minimumSidebarPlayerWidth)
        let widthRemainingOnScreen = maximumOpenWidth - nonPlayerContentWidth

        return min(
            preferredWidth,
            max(Self.minimumConstrainedPlayerWidth, widthRemainingOnScreen)
        )
    }

    var todoWidth: CGFloat {
        sidebarCount >= 2 ? 145 : Self.sidebarWidth
    }

    var openWidth: CGFloat {
        let compactWidth = closedNotchWidth + Self.compactWidthIncrement
        guard sidebarCount > 0 else { return compactWidth }

        let minimumWidth = sidebarCount >= 2 ? CGFloat(640) : compactWidth
        let contentWidth = playerWidth + nonPlayerContentWidth
        return ceil(min(maximumOpenWidth, max(minimumWidth, contentWidth)))
    }

    var homeModulesContentWidth: CGFloat {
        playerWidth + sidebarsWidth
            + (CGFloat(sidebarCount) * Self.dividerAndSpacingPerSidebar)
    }

    private var sidebarsWidth: CGFloat {
        var width: CGFloat = 0
        if showTodo { width += todoWidth }
        if showCalendar { width += Self.sidebarWidth }
        if showWeather { width += Self.sidebarWidth }
        return width
    }

    private var nonPlayerContentWidth: CGFloat {
        sidebarsWidth
            + (CGFloat(sidebarCount) * Self.dividerAndSpacingPerSidebar)
            + contentHorizontalPadding
    }

    private var maximumOpenWidth: CGFloat {
        guard let availableScreenWidth else {
            return Self.maximumWindowContentWidth
        }
        return min(
            Self.maximumWindowContentWidth,
            max(640, availableScreenWidth - Self.screenHorizontalMargin)
        )
    }
}

enum OpenMeteoRequestBuilder {
    static func weatherURL(
        longitude: Double,
        latitude: Double
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: coordinateString(latitude)),
            URLQueryItem(name: "longitude", value: coordinateString(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,is_day,weather_code"
            ),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { throw WeatherCoreError.invalidURL }
        return url
    }

    private static func coordinateString(_ value: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
