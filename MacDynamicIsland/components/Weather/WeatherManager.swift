import AppKit
import Combine
import CoreLocation
import Defaults
import Foundation
import Security

final class WeatherManager: NSObject, ObservableObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WeatherManager()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var locationSelection: WeatherLocationSelection
    @Published private(set) var isCurrentLocationFeedbackHighlighted = false
    @Published private(set) var providerPreference: WeatherProviderPreference
    @Published private(set) var qWeatherHost: String
    @Published private(set) var hasQWeatherCredentials: Bool
    @Published private(set) var credentialStatusMessage: String?
    @Published private(set) var isTestingCredentials = false

    private let locationManager = CLLocationManager()
    private let session: URLSession
    private var refreshTask: Task<Void, Never>?
    private var currentLocationFeedbackTask: Task<Void, Never>?

    private override convenience init() {
        self.init(session: .shared)
    }

    init(session: URLSession) {
        let credentials = QWeatherCredentialStore.load()
        self.session = session
        self.locationSelection = Defaults[.weatherLocationSelection]
        self.providerPreference = Defaults[.weatherProviderPreference]
        self.qWeatherHost = QWeatherCredentialStore.loadPreferredHost()
        self.hasQWeatherCredentials = credentials != nil
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = WeatherLocationPolicy.desiredAccuracy
        authorizationStatus = locationManager.authorizationStatus
        snapshot = loadCachedSnapshot(matching: locationSelection, preference: providerPreference)
        for key in WeatherCachePolicy.legacyCacheKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    deinit {
        refreshTask?.cancel()
        currentLocationFeedbackTask?.cancel()
    }

    func requestLocationAndRefresh(force: Bool = false) {
        refreshCurrentSelection(force: force)
    }

    func refreshCurrentSelection(force: Bool = false) {
        if !force,
           let snapshot,
           WeatherCachePolicy.isFresh(
               snapshot,
               matching: locationSelection,
               preference: providerPreference
           ) {
            statusMessage = nil
            return
        }

        if locationSelection.mode == .manual,
           let location = locationSelection.manualLocation {
            refreshWeather(
                for: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                selection: locationSelection,
                locationName: location.displayName
            )
            return
        }

        requestAutomaticLocation()
    }

    func selectManualLocation(_ location: WeatherManualLocation) {
        currentLocationFeedbackTask?.cancel()
        isCurrentLocationFeedbackHighlighted = false
        let selection = WeatherLocationSelection.manual(location)
        locationSelection = selection
        Defaults[.weatherLocationSelection] = selection
        snapshot = nil
        refreshWeather(
            for: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            selection: selection,
            locationName: location.displayName
        )
    }

    func useCurrentLocation() {
        currentLocationFeedbackTask?.cancel()
        isCurrentLocationFeedbackHighlighted = true
        locationSelection = .automatic
        Defaults[.weatherLocationSelection] = .automatic
        refreshCurrentSelection(force: true)
    }

    func requestLocationAuthorization() {
        requestAutomaticLocation()
    }

    func setProviderPreference(_ preference: WeatherProviderPreference) {
        guard providerPreference != preference else { return }
        providerPreference = preference
        Defaults[.weatherProviderPreference] = preference
        snapshot = loadCachedSnapshot(matching: locationSelection, preference: preference)
        refreshCurrentSelection(force: true)
    }

    func saveAndTestQWeatherCredentials(apiHost: String, apiKey: String) {
        guard !isTestingCredentials else { return }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            credentialStatusMessage = "请输入 API Key"
            return
        }

        let normalizedHost: String
        do {
            normalizedHost = try QWeatherHostValidator.normalizedHost(apiHost)
        } catch {
            credentialStatusMessage = "API Host 无效，请填写和风天气提供的 HTTPS Host"
            return
        }

        isTestingCredentials = true
        credentialStatusMessage = "正在验证和风天气配置…"
        let session = self.session
        Task { [weak self] in
            do {
                let url = try QWeatherRequestBuilder.weatherURL(
                    apiHost: normalizedHost,
                    longitude: 116.41,
                    latitude: 39.90
                )
                _ = try await Self.fetchQWeather(from: url, apiKey: trimmedKey, session: session)
                try QWeatherCredentialStore.save(host: normalizedHost, apiKey: trimmedKey)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.qWeatherHost = normalizedHost
                    self.hasQWeatherCredentials = true
                    self.isTestingCredentials = false
                    self.credentialStatusMessage = "配置验证成功，已安全保存到钥匙串"
                    self.refreshCurrentSelection(force: true)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isTestingCredentials = false
                    self?.credentialStatusMessage = Self.credentialMessage(for: error)
                }
            }
        }
    }

    func saveQWeatherHost(_ apiHost: String) {
        let normalizedHost: String
        do {
            normalizedHost = try QWeatherHostValidator.normalizedHost(apiHost)
        } catch {
            credentialStatusMessage = "API Host 无效，请填写和风天气提供的 HTTPS Host"
            return
        }

        QWeatherCredentialStore.savePreferredHost(normalizedHost)
        qWeatherHost = normalizedHost
        credentialStatusMessage = "主机名已保存，应用更新不会覆盖"

        if hasQWeatherCredentials, providerPreference != .openMeteo {
            snapshot = nil
            refreshCurrentSelection(force: true)
        }
    }

    func clearQWeatherCredentials() {
        QWeatherCredentialStore.deleteAPIKey()
        hasQWeatherCredentials = false
        credentialStatusMessage = "已清除 API Key，主机名已保留"
        if providerPreference != .openMeteo {
            snapshot = nil
            refreshCurrentSelection(force: true)
        }
    }

    private func requestAutomaticLocation() {
        authorizationStatus = locationManager.authorizationStatus
        let action = WeatherAutomaticLocationPolicy.action(for: authorizationStatus)
        statusMessage = WeatherAutomaticLocationPolicy.statusMessage(for: action)

        switch action {
        case .requestAuthorization:
            isLoading = true
            if WeatherAutomaticLocationPolicy.shouldActivateApplication(for: action) {
                NSApp.activate(ignoringOtherApps: true)
            }
            locationManager.requestWhenInUseAuthorization()
        case .requestLocation:
            isLoading = true
            locationManager.requestLocation()
        case .showPermissionHelp, .unavailable:
            isLoading = false
            isCurrentLocationFeedbackHighlighted = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways {
                self.requestLocationAndRefresh(force: true)
            } else if manager.authorizationStatus == .denied
                || manager.authorizationStatus == .restricted
            {
                self.isLoading = false
                self.statusMessage = "请允许定位，以显示当前地区天气"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locationSelection.mode == .automatic else { return }
        guard let location = WeatherLocationQualityPolicy.bestLocation(from: locations) else {
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                self?.isCurrentLocationFeedbackHighlighted = false
                self?.statusMessage = "定位精度不足，请稍后重试"
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshWeather(for: location.coordinate, selection: self.locationSelection)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
            self?.isCurrentLocationFeedbackHighlighted = false
            self?.statusMessage = "定位失败，请稍后重试"
        }
    }

    private func refreshWeather(
        for coordinate: CLLocationCoordinate2D,
        selection: WeatherLocationSelection,
        locationName: String? = nil
    ) {
        refreshTask?.cancel()
        isLoading = true
        statusMessage = nil
        let session = self.session
        let preference = providerPreference
        let credentials = QWeatherCredentialStore.load()

        refreshTask = Task { [weak self] in
            do {
                let resolvedName: String
                if let locationName {
                    resolvedName = locationName
                } else {
                    resolvedName = await Self.locationName(for: coordinate)
                }
                let freshSnapshot = try await Self.fetchWeatherSnapshot(
                    for: coordinate,
                    selection: selection,
                    locationName: resolvedName,
                    preference: preference,
                    credentials: credentials,
                    session: session
                )
                try Task.checkCancellation()

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.locationSelection == selection,
                          self.providerPreference == preference else { return }
                    self.snapshot = freshSnapshot
                    self.saveCachedSnapshot(freshSnapshot)
                    self.isLoading = false
                    self.statusMessage = nil
                    if selection.mode == .automatic {
                        self.isCurrentLocationFeedbackHighlighted = true
                        self.scheduleCurrentLocationFeedbackReset()
                    }
                }
            } catch is CancellationError {
                // A newer refresh replaced this request.
            } catch {
                await MainActor.run { [weak self] in
                    self?.isLoading = false
                    if self?.locationSelection.mode == .automatic {
                        self?.isCurrentLocationFeedbackHighlighted = false
                    }
                    self?.statusMessage = Self.userMessage(for: error)
                }
            }
        }
    }

    private static func fetchWeatherSnapshot(
        for coordinate: CLLocationCoordinate2D,
        selection: WeatherLocationSelection,
        locationName: String,
        preference: WeatherProviderPreference,
        credentials: QWeatherCredentials?,
        session: URLSession
    ) async throws -> WeatherSnapshot {
        let requestOrder = WeatherProviderSelectionPolicy.requestOrder(
            preference: preference,
            hasQWeatherCredentials: credentials != nil
        )
        if preference == .qWeather && credentials == nil {
            throw WeatherManagerError.qWeatherNotConfigured
        }

        var lastError: Error?
        for source in requestOrder {
            do {
                let fetchedAt = Date()
                switch source {
                case .qWeather:
                    guard let credentials else { throw WeatherManagerError.qWeatherNotConfigured }
                    let url = try QWeatherRequestBuilder.weatherURL(
                        apiHost: credentials.host,
                        longitude: coordinate.longitude,
                        latitude: coordinate.latitude
                    )
                    let response = try await fetchQWeather(
                        from: url,
                        apiKey: credentials.apiKey,
                        session: session
                    )
                    return try WeatherSnapshot(
                        response: response,
                        locationName: locationName,
                        locationIdentity: selection.cacheIdentity,
                        fetchedAt: fetchedAt
                    )
                case .openMeteo:
                    let url = try OpenMeteoRequestBuilder.weatherURL(
                        longitude: coordinate.longitude,
                        latitude: coordinate.latitude
                    )
                    let response = try await fetch(
                        OpenMeteoCurrentResponse.self,
                        from: url,
                        session: session
                    )
                    return WeatherSnapshot(
                        response: response,
                        locationName: locationName,
                        locationIdentity: selection.cacheIdentity,
                        fetchedAt: fetchedAt
                    )
                }
            } catch {
                lastError = error
                if preference != .automatic { throw error }
            }
        }
        throw lastError ?? WeatherManagerError.invalidServerResponse
    }

    private func scheduleCurrentLocationFeedbackReset() {
        currentLocationFeedbackTask?.cancel()
        let nanoseconds = UInt64(WeatherCurrentLocationFeedbackPolicy.duration * 1_000_000_000)
        currentLocationFeedbackTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.isCurrentLocationFeedbackHighlighted = false
            }
        }
    }

    private static func fetch<T: Decodable>(
        _ type: T.Type,
        from url: URL,
        session: URLSession
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherManagerError.invalidServerResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherManagerError.httpStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func fetchQWeather(
        from url: URL,
        apiKey: String,
        session: URLSession
    ) async throws -> QWeatherNowResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(apiKey, forHTTPHeaderField: "X-QW-Api-Key")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherManagerError.invalidServerResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WeatherManagerError.httpStatus(httpResponse.statusCode)
        }
        let decoded = try JSONDecoder().decode(QWeatherNowResponse.self, from: data)
        guard decoded.code == "200" else {
            throw WeatherManagerError.qWeatherCode(decoded.code)
        }
        return decoded
    }

    private static func locationName(for coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return await withCheckedContinuation { continuation in
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "zh_CN")
            ) { placemarks, _ in
                guard let placemark = placemarks?.first else {
                    continuation.resume(returning: "当前位置")
                    return
                }

                let city = placemark.locality
                    ?? placemark.subAdministrativeArea
                    ?? placemark.administrativeArea
                let district = placemark.subLocality
                if let district,
                   let city,
                   !district.isEmpty,
                   district.localizedCaseInsensitiveCompare(city) != .orderedSame {
                    continuation.resume(returning: "\(district) · \(city)")
                } else {
                    continuation.resume(returning: city ?? district ?? "当前位置")
                }
            }
        }
    }

    private func loadCachedSnapshot(
        matching selection: WeatherLocationSelection,
        preference: WeatherProviderPreference
    ) -> WeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: WeatherCachePolicy.cacheKey) else {
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(WeatherSnapshot.self, from: data),
              WeatherCachePolicy.isFresh(
                  snapshot,
                  matching: selection,
                  preference: preference
              ) else {
            return nil
        }
        return snapshot
    }

    private func saveCachedSnapshot(_ snapshot: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: WeatherCachePolicy.cacheKey)
    }

    private static func userMessage(for error: Error) -> String {
        if let error = error as? WeatherManagerError {
            return error.localizedDescription
        }
        if error is DecodingError {
            return "天气数据格式暂时无法读取"
        }
        return "天气更新失败，请检查网络后重试"
    }

    private static func credentialMessage(for error: Error) -> String {
        if case WeatherManagerError.qWeatherCode(let code) = error {
            return "验证失败（和风天气错误码 \(code)），请检查 Host 和 API Key"
        }
        if let error = error as? WeatherCoreError, error == .invalidHost {
            return "API Host 无效，请检查后重试"
        }
        return "验证失败，请检查 Host、API Key 和网络"
    }
}

enum WeatherManagerError: LocalizedError {
    case invalidServerResponse
    case httpStatus(Int)
    case qWeatherNotConfigured
    case qWeatherCode(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidServerResponse:
            return "无法读取天气服务器响应，请检查网络后重试"
        case .httpStatus(429):
            return "天气请求较频繁，请稍后重试"
        case .httpStatus(let status) where status >= 500:
            return "天气服务暂时不可用，请稍后重试"
        case .httpStatus(let status):
            return "天气请求失败（错误码 \(status)）"
        case .qWeatherNotConfigured:
            return "请先在天气设置中配置和风天气 API Host 和 API Key"
        case .qWeatherCode(let code):
            return "和风天气请求失败（错误码 \(code)）"
        case .keychain:
            return "无法将和风天气配置保存到系统钥匙串"
        }
    }
}

struct QWeatherCredentials: Equatable, @unchecked Sendable {
    let host: String
    let apiKey: String
}

private enum QWeatherCredentialStore {
    private static let defaultHost = "devapi.qweather.com"
    private static let preferredHostDefaultsKey = "qweather-api-host-preference"

    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "MacDynamicIsland") + ".weather"
    }

    static func load() -> QWeatherCredentials? {
        guard let apiKey = read(account: "qweather-api-key"),
              !apiKey.isEmpty else { return nil }
        let host = loadPreferredHost()
        return QWeatherCredentials(host: host, apiKey: apiKey)
    }

    static func loadPreferredHost() -> String {
        if let preferredHost = UserDefaults.standard.string(forKey: preferredHostDefaultsKey),
           let normalizedHost = try? QWeatherHostValidator.normalizedHost(preferredHost) {
            return normalizedHost
        }

        if let legacyHost = read(account: "qweather-api-host"),
           let normalizedHost = try? QWeatherHostValidator.normalizedHost(legacyHost) {
            savePreferredHost(normalizedHost)
            return normalizedHost
        }

        return defaultHost
    }

    static func savePreferredHost(_ host: String) {
        UserDefaults.standard.set(host, forKey: preferredHostDefaultsKey)
    }

    static func save(host: String, apiKey: String) throws {
        savePreferredHost(host)
        try write(host, account: "qweather-api-host")
        do {
            try write(apiKey, account: "qweather-api-key")
        } catch {
            delete(account: "qweather-api-host")
            throw error
        }
    }

    static func deleteAPIKey() {
        delete(account: "qweather-api-key")
    }

    private static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw WeatherManagerError.keychain(updateStatus)
        }
        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WeatherManagerError.keychain(addStatus)
        }
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
