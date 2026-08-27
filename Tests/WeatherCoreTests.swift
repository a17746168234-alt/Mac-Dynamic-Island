import AppKit
import CoreLocation
import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure.assertion(message) }
}

@main
@MainActor
struct WeatherCoreTests {
    static func main() throws {
        try parsesOpenMeteoCurrentResponse()
        try parsesQWeatherCurrentResponse()
        try enforcesFifteenMinuteCacheBoundary()
        try invalidatesCacheFromTheCoarseLocationVersion()
        try calculatesHomeLayoutForEverySidebarCount()
        try buildsOpenMeteoWeatherURL()
        try validatesQWeatherHostsAndBuildsWeatherURL()
        try choosesWeatherProvidersAndBindsCacheToPreference()
        try requestsBestAvailableLocationAccuracy()
        try mapsWMOConditionsToChineseAndSystemSymbols()
        try mapsQWeatherConditionsToSystemSymbols()
        try allowsLocationPermission()
        try refreshesForAuthorizedLocationWithoutCredentials()
        try routesDeniedLocationToSystemSettings()
        try activatesWeatherSettingsWindowForKeyboardInput()
        try keepsWeatherFocusBridgeOutOfHitTesting()
        try alignsMusicControlsWithoutShrinkingThePlayer()
        try persistsManualWeatherLocationAndBindsItsCache()
        try normalizesAndMovesHomeModuleOrder()
        try keepsHiddenModulePositionForLaterRestore()
        try reordersModulesInHorizontalSettings()
        try showsLyricsOnlyForThePlayerOnlyLayout()
        try keepsHeaderEdgeInsetsSymmetricForEveryModuleCount()
        try keepsUtilityControlSpacingEqualToThePrimaryButtons()
        try keepsHundredPercentBatteryTextInsideItsReservedWidth()
        try keepsHomeContentAndHeaderOnTheSameHorizontalGuides()
        try keepsAdvancedModuleCardsInsideTheAvailableWidth()
        try requestsLocationPermissionWithoutAnIndefiniteWaitingState()
        try keepsWeatherLocationControlsInsideTheModuleWidth()
        try usesTheTrailingWeatherSlotForSourceAndStatus()
        try sizesCityPickerAsALargePanel()
        try expiresCurrentLocationSuccessFeedbackAfterEightSeconds()
        try choosesTheFreshestHighQualityLocation()
        print("WeatherCoreTests: PASS")
    }

    private static func parsesQWeatherCurrentResponse() throws {
        let json = #"""
        {
          "code": "200",
          "updateTime": "2026-08-24T13:00+08:00",
          "now": {
            "obsTime": "2026-08-24T12:55+08:00",
            "temp": "31",
            "icon": "100",
            "text": "晴",
            "humidity": "63"
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(QWeatherNowResponse.self, from: json)
        let snapshot = try WeatherSnapshot(
            response: response,
            locationName: "杭州",
            fetchedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )
        try expect(snapshot.temperatureCelsius == 31, "和风天气字符串温度必须解析为整数")
        try expect(snapshot.humidityPercent == 63, "和风天气湿度必须解析")
        try expect(snapshot.conditionText == "晴", "和风天气中文描述必须保留")
        try expect(snapshot.iconCode == "100", "和风天气图标代码必须保留")
        try expect(snapshot.source == .qWeather, "和风天气快照必须记录实际来源")
    }

    private static func parsesOpenMeteoCurrentResponse() throws {
        let json = #"""
        {
          "latitude": 39.89455,
          "longitude": 116.35983,
          "timezone": "Asia/Shanghai",
          "current": {
            "time": "2026-08-22T12:30",
            "interval": 900,
            "temperature_2m": 29.6,
            "relative_humidity_2m": 65,
            "is_day": 1,
            "weather_code": 1
          }
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenMeteoCurrentResponse.self, from: json)
        let fetchedAt = Date(timeIntervalSince1970: 1_777_000_000)
        let snapshot = WeatherSnapshot(
            response: response,
            locationName: "北京",
            fetchedAt: fetchedAt
        )

        try expect(snapshot.locationName == "北京", "地区名称必须保留")
        try expect(snapshot.temperatureCelsius == 30, "小数温度必须四舍五入")
        try expect(snapshot.humidityPercent == 65, "湿度必须解析")
        try expect(snapshot.conditionText == "晴间多云", "WMO 代码必须转换成中文")
        try expect(snapshot.iconCode == "1", "WMO 天气代码必须保留")
        try expect(snapshot.fetchedAt == fetchedAt, "缓存时间必须使用实际获取时间")
    }

    private static func enforcesFifteenMinuteCacheBoundary() throws {
        let fetchedAt = Date(timeIntervalSince1970: 10_000)
        let snapshot = WeatherSnapshot(
            locationName: "杭州",
            temperatureCelsius: 26,
            humidityPercent: 74,
            conditionText: "多云",
            iconCode: "101",
            observedAt: fetchedAt,
            fetchedAt: fetchedAt
        )

        try expect(
            WeatherCachePolicy.isFresh(snapshot, now: fetchedAt.addingTimeInterval(899)),
            "15分钟内必须复用缓存"
        )
        try expect(
            !WeatherCachePolicy.isFresh(snapshot, now: fetchedAt.addingTimeInterval(900)),
            "到15分钟边界必须允许刷新"
        )
    }

    private static func invalidatesCacheFromTheCoarseLocationVersion() throws {
        try expect(
            WeatherCachePolicy.cacheKey.hasSuffix(".v5"),
            "引入多天气引擎后必须使用独立缓存版本"
        )
        try expect(
            WeatherCachePolicy.legacyCacheKeys.contains("MacDynamicIsland.weather.snapshot.v4"),
            "必须清除不含实际天气来源的旧缓存"
        )

        let fetchedAt = Date(timeIntervalSince1970: 20_000)
        let snapshot = WeatherSnapshot(
            locationName: "路南区 · 唐山市",
            locationIdentity: "manual:39.630000,118.150000",
            temperatureCelsius: 31,
            humidityPercent: 52,
            conditionText: "晴间多云",
            iconCode: "1",
            observedAt: fetchedAt,
            fetchedAt: fetchedAt
        )
        try expect(
            WeatherCachePolicy.isFresh(
                snapshot,
                matching: WeatherLocationSelection.manual(
                    WeatherManualLocation(displayName: "路南区 · 唐山市", latitude: 39.63, longitude: 118.15)
                ),
                now: fetchedAt.addingTimeInterval(60)
            ),
            "同一手动城市应在十五分钟内复用缓存"
        )
        try expect(
            !WeatherCachePolicy.isFresh(
                snapshot,
                matching: WeatherLocationSelection.manual(
                    WeatherManualLocation(displayName: "路北区 · 唐山市", latitude: 39.65, longitude: 118.18)
                ),
                now: fetchedAt.addingTimeInterval(60)
            ),
            "切换城市后不得复用上一城市天气"
        )
    }

    private static func calculatesHomeLayoutForEverySidebarCount() throws {
        let closedWidth: CGFloat = 185
        let none = NotchHomeLayout(
            closedNotchWidth: closedWidth,
            showTodo: false,
            showCalendar: false,
            showWeather: false
        )
        let one = NotchHomeLayout(
            closedNotchWidth: closedWidth,
            showTodo: false,
            showCalendar: true,
            showWeather: false
        )
        let two = NotchHomeLayout(
            closedNotchWidth: closedWidth,
            showTodo: true,
            showCalendar: true,
            showWeather: false
        )
        let three = NotchHomeLayout(
            closedNotchWidth: closedWidth,
            showTodo: true,
            showCalendar: true,
            showWeather: true
        )

        try expect(none.playerWidth == 437, "无侧栏时保持现有播放器宽度")
        try expect(one.playerWidth == 330, "开启侧栏时播放器必须保留可用的最小宽度")
        try expect(two.playerWidth == one.playerWidth, "双侧栏时必须保持播放器最小宽度")
        try expect(three.todoWidth == 145, "多侧栏时待办宽度应为145")
        try expect(one.openWidth == 558, "单侧栏时灵动岛必须随播放器增宽")
        try expect(two.openWidth == 720, "双侧栏时灵动岛必须增宽以避免播放器被挤压")
        try expect(three.openWidth > two.openWidth, "三项全开时灵动岛必须继续增宽")

        let currentCompactUsage = NotchHomeLayout(
            closedNotchWidth: 183,
            showTodo: false,
            showCalendar: false,
            showWeather: false,
            availableScreenWidth: 1470
        )
        try expect(currentCompactUsage.playerWidth == 435, "当前无侧栏主页的播放器宽度不得改变")
        try expect(currentCompactUsage.openWidth == 535, "当前无侧栏主页的总宽度不得改变")

        let constrained = NotchHomeLayout(
            closedNotchWidth: closedWidth,
            showTodo: true,
            showCalendar: true,
            showWeather: true,
            availableScreenWidth: 860
        )
        try expect(constrained.openWidth == 828, "窄屏上的主页不得超出屏幕安全边距")
        try expect(constrained.playerWidth == 256, "极窄屏应只在必要时压缩播放器")
    }

    private static func buildsOpenMeteoWeatherURL() throws {
        let url = try OpenMeteoRequestBuilder.weatherURL(
            longitude: 120.12345,
            latitude: 30.98765
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try expect(components.scheme == "https", "天气请求必须使用HTTPS")
        try expect(components.host == "api.open-meteo.com", "只能请求 Open-Meteo 官方主机")
        try expect(components.path == "/v1/forecast", "必须调用 Open-Meteo 实时天气端点")
        try expect(items["longitude"] == "120.12345", "经度必须保持定位精度")
        try expect(items["latitude"] == "30.98765", "纬度必须保持定位精度")
        try expect(items["timezone"] == "auto", "时区必须由坐标自动确定")
        try expect(
            items["current"] == "temperature_2m,relative_humidity_2m,is_day,weather_code",
            "只请求主页实际使用的实时天气字段"
        )
    }

    private static func validatesQWeatherHostsAndBuildsWeatherURL() throws {
        let officialHost = try QWeatherHostValidator.normalizedHost("https://DEVAPI.QWEATHER.COM/")
        try expect(
            officialHost == "devapi.qweather.com",
            "官方 Host 必须被标准化"
        )
        let customHost = try QWeatherHostValidator.normalizedHost("abc123.qweatherapi.com")
        try expect(
            customHost == "abc123.qweatherapi.com",
            "和风控制台分配的自定义 Host 必须可用"
        )

        for invalid in [
            "http://devapi.qweather.com",
            "https://devapi.qweather.com/v7/weather/now",
            "https://example.com",
            "https://qweatherapi.com",
        ] {
            do {
                _ = try QWeatherHostValidator.normalizedHost(invalid)
                throw TestFailure.assertion("必须拒绝不安全或非官方 Host：\(invalid)")
            } catch is WeatherCoreError {
                // Expected.
            }
        }

        let url = try QWeatherRequestBuilder.weatherURL(
            apiHost: "api.qweather.com",
            longitude: 120.12345,
            latitude: 30.98765
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        try expect(components.scheme == "https", "和风天气请求必须使用 HTTPS")
        try expect(components.host == "api.qweather.com", "和风天气请求必须使用验证后的 Host")
        try expect(components.path == "/v7/weather/now", "必须请求和风实时天气端点")
        try expect(items["location"] == "120.12,30.99", "经纬度必须按和风接口限制保留两位小数")
        try expect(items["lang"] == "zh", "和风天气必须请求中文描述")
        try expect(items["unit"] == "m", "和风天气必须使用公制单位")
    }

    private static func choosesWeatherProvidersAndBindsCacheToPreference() throws {
        try expect(
            WeatherProviderSelectionPolicy.requestOrder(
                preference: .automatic,
                hasQWeatherCredentials: true
            ) == [.qWeather, .openMeteo],
            "自动模式配置和风后必须优先和风并保留 Open-Meteo 回退"
        )
        try expect(
            WeatherProviderSelectionPolicy.requestOrder(
                preference: .automatic,
                hasQWeatherCredentials: false
            ) == [.openMeteo],
            "自动模式未配置和风时必须直接使用 Open-Meteo"
        )
        try expect(
            WeatherProviderSelectionPolicy.requestOrder(
                preference: .qWeather,
                hasQWeatherCredentials: false
            ) == [.qWeather],
            "明确选择和风时不得静默换源"
        )

        let now = Date(timeIntervalSince1970: 50_000)
        let qWeatherSnapshot = WeatherSnapshot(
            locationName: "杭州",
            temperatureCelsius: 30,
            humidityPercent: 60,
            conditionText: "晴",
            iconCode: "100",
            source: .qWeather,
            observedAt: now,
            fetchedAt: now
        )
        try expect(
            WeatherCachePolicy.isFresh(
                qWeatherSnapshot,
                matching: .automatic,
                preference: .automatic,
                now: now.addingTimeInterval(10)
            ),
            "自动模式可以复用任一成功来源"
        )
        try expect(
            !WeatherCachePolicy.isFresh(
                qWeatherSnapshot,
                matching: .automatic,
                preference: .openMeteo,
                now: now.addingTimeInterval(10)
            ),
            "明确选择 Open-Meteo 后不得复用和风缓存"
        )
    }

    private static func requestsBestAvailableLocationAccuracy() throws {
        try expect(
            WeatherLocationPolicy.desiredAccuracy == kCLLocationAccuracyBest,
            "天气定位必须请求系统可提供的最高精度"
        )
    }

    private static func mapsWMOConditionsToChineseAndSystemSymbols() throws {
        try expect(WMOWeatherMapper.description(for: 0) == "晴", "WMO 0 应显示晴")
        try expect(WMOWeatherMapper.description(for: 1) == "晴间多云", "WMO 1 应显示晴间多云")
        try expect(WMOWeatherMapper.description(for: 61) == "小雨", "WMO 61 应显示小雨")
        try expect(WMOWeatherMapper.description(for: 95) == "雷暴", "WMO 95 应显示雷暴")
        try expect(WeatherIconMapper.systemSymbol(for: "0") == "sun.max.fill", "晴天图标应为太阳")
        try expect(WeatherIconMapper.systemSymbol(for: "2") == "cloud.sun.fill", "多云图标应为云和太阳")
        try expect(WeatherIconMapper.systemSymbol(for: "61") == "cloud.rain.fill", "降雨图标应为雨云")
        try expect(WeatherIconMapper.systemSymbol(for: "71") == "cloud.snow.fill", "降雪图标应为雪云")
        try expect(WeatherIconMapper.systemSymbol(for: "45") == "cloud.fog.fill", "雾天图标应为雾")
        try expect(WeatherIconMapper.systemSymbol(for: "999") == "cloud.fill", "未知代码必须安全回退")
    }

    private static func mapsQWeatherConditionsToSystemSymbols() throws {
        try expect(
            WeatherIconMapper.systemSymbol(for: "100", source: .qWeather) == "sun.max.fill",
            "和风晴天代码必须显示太阳"
        )
        try expect(
            WeatherIconMapper.systemSymbol(for: "150", source: .qWeather) == "moon.stars.fill",
            "和风晴夜代码必须显示月亮"
        )
        try expect(
            WeatherIconMapper.systemSymbol(for: "305", source: .qWeather) == "cloud.rain.fill",
            "和风降雨代码必须显示雨云"
        )
        try expect(
            WeatherIconMapper.systemSymbol(for: "400", source: .qWeather) == "cloud.snow.fill",
            "和风降雪代码必须显示雪云"
        )
    }

    private static func allowsLocationPermission() throws {
        let action = WeatherSettingsInteractionPolicy.locationAction(
            authorizationStatus: .notDetermined,
            isLoading: false
        )
        try expect(action == .requestAuthorization, "未决定时必须允许请求定位权限")
    }

    private static func refreshesForAuthorizedLocationWithoutCredentials() throws {
        let action = WeatherSettingsInteractionPolicy.locationAction(
            authorizationStatus: .authorizedAlways,
            isLoading: false
        )
        try expect(action == .refreshWeather, "定位已允许时必须直接刷新，不得再等待天气凭据")
    }

    private static func routesDeniedLocationToSystemSettings() throws {
        let action = WeatherSettingsInteractionPolicy.locationAction(
            authorizationStatus: .denied,
            isLoading: false
        )
        try expect(action == .openSystemSettings, "定位被拒绝后必须提供系统设置入口")
    }

    private static func activatesWeatherSettingsWindowForKeyboardInput() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        let panel = KeyboardTestPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let didActivate = WeatherSettingsWindowFocus.activate(panel)
        try expect(
            didActivate,
            "天气设置必须找到可接收键盘的窗口"
        )
        try expect(panel.isVisible, "焦点请求必须将天气设置窗口置前")
        panel.orderOut(nil)
    }

    private static func keepsWeatherFocusBridgeOutOfHitTesting() throws {
        let focusView = WeatherSettingsFocusView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        try expect(
            focusView.hitTest(NSPoint(x: 20, y: 20)) == nil,
            "天气焦点辅助视图不得拦截输入框和按钮的鼠标事件"
        )
    }

    private static func alignsMusicControlsWithoutShrinkingThePlayer() throws {
        let compact = MusicToolbarLayout(hasSidebar: true)
        let playerOnly = MusicToolbarLayout(hasSidebar: false)

        try expect(compact.verticalOffset < 0, "开启侧栏时播放按钮必须向上靠近进度条")
        try expect(compact.visualScale == 1, "开启侧栏时播放按钮必须保持原始尺寸")
        try expect(compact.spacing == 6, "开启侧栏时播放按钮必须恢复原始间距")
        try expect(compact.usesCenteredCompactGroup, "开启侧栏时播放按钮组必须与进度条居中对齐")
        try expect(playerOnly.verticalOffset == 0, "纯播放器模式不得改变按钮纵向位置")
        try expect(playerOnly.visualScale == 1, "纯播放器模式不得改变按钮尺寸")
        try expect(!playerOnly.usesCenteredCompactGroup, "纯播放器模式必须保留原始布局")
    }

    private static func persistsManualWeatherLocationAndBindsItsCache() throws {
        let location = WeatherManualLocation(
            displayName: "路南区 · 唐山市",
            latitude: 39.63,
            longitude: 118.15
        )
        let selection = WeatherLocationSelection.manual(location)
        let restored = try JSONDecoder().decode(
            WeatherLocationSelection.self,
            from: JSONEncoder().encode(selection)
        )

        try expect(restored == selection, "手动选择的城市必须可持久化恢复")
        try expect(
            restored.cacheIdentity == "manual:39.630000,118.150000",
            "手动城市缓存必须绑定准确坐标"
        )
        try expect(
            WeatherLocationSelection.automatic.cacheIdentity == "automatic",
            "当前位置必须使用独立缓存身份"
        )
    }

    private static func normalizesAndMovesHomeModuleOrder() throws {
        let normalized = HomeModuleOrderPolicy.normalized([.weather, .player, .weather])
        try expect(
            normalized == [.weather, .player, .todo, .calendar],
            "排序偏好出现重复或缺项时必须去重并补齐"
        )
        try expect(
            HomeModuleOrderPolicy.moving(
                [.player, .todo, .calendar, .weather],
                .weather,
                before: .todo
            ) == [.player, .weather, .todo, .calendar],
            "拖放只应改变模块横向相对顺序"
        )
    }

    private static func keepsHiddenModulePositionForLaterRestore() throws {
        let order: [HomeModule] = [.weather, .player, .todo, .calendar]
        let hiddenWeather = HomeModuleOrderPolicy.visibleOrder(
            order: order,
            showTodo: true,
            showCalendar: true,
            showWeather: false
        )
        let restoredWeather = HomeModuleOrderPolicy.visibleOrder(
            order: order,
            showTodo: true,
            showCalendar: true,
            showWeather: true
        )

        try expect(hiddenWeather == [.player, .todo, .calendar], "隐藏模块不能破坏已保存顺序")
        try expect(restoredWeather.first == .weather, "重新显示模块时必须恢复原位置")
    }

    private static func showsLyricsOnlyForThePlayerOnlyLayout() throws {
        try expect(
            HomeModuleOrderPolicy.shouldShowLyrics(
                enableLyrics: true,
                showTodo: false,
                showCalendar: false,
                showWeather: false
            ),
            "开启歌词且主页只有播放器时必须显示实时歌词"
        )
        try expect(
            !HomeModuleOrderPolicy.shouldShowLyrics(
                enableLyrics: true,
                showTodo: true,
                showCalendar: false,
                showWeather: false
            ),
            "加入待办后必须隐藏歌词"
        )
        try expect(
            !HomeModuleOrderPolicy.shouldShowLyrics(
                enableLyrics: true,
                showTodo: false,
                showCalendar: true,
                showWeather: false
            ),
            "加入日历后必须隐藏歌词"
        )
        try expect(
            !HomeModuleOrderPolicy.shouldShowLyrics(
                enableLyrics: true,
                showTodo: false,
                showCalendar: false,
                showWeather: true
            ),
            "加入天气后必须隐藏歌词"
        )
        try expect(
            !HomeModuleOrderPolicy.shouldShowLyrics(
                enableLyrics: false,
                showTodo: false,
                showCalendar: false,
                showWeather: false
            ),
            "用户关闭歌词后纯播放器模式也不得强制显示"
        )
    }

    private static func keepsHeaderEdgeInsetsSymmetricForEveryModuleCount() throws {
        let insets = (0...3).map { BoringHeaderLayout.edgeInsets(sidebarCount: $0) }
        try expect(
            insets.allSatisfy { $0.leading == $0.trailing },
            "无论开启多少主页模块，顶栏左右边距必须始终对称"
        )
        try expect(
            Set(insets.map(\.leading)).count == 1,
            "开关主页模块时不得改变顶栏边距"
        )
    }

    private static func keepsUtilityControlSpacingEqualToThePrimaryButtons() throws {
        try expect(
            BoringHeaderLayout.controlSpacing == 1.5,
            "设置按钮和电量之间必须使用与左侧四个按钮完全相同的 1.5pt 间距"
        )
    }

    private static func keepsHundredPercentBatteryTextInsideItsReservedWidth() throws {
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        let textWidth = ("100%" as NSString).size(withAttributes: [.font: font]).width
        try expect(
            textWidth <= BoringHeaderLayout.batteryPercentageMinimumWidth,
            "100% 电量文字必须完整容纳在预留宽度中，不得与设置按钮重叠"
        )
    }

    private static func keepsHomeContentAndHeaderOnTheSameHorizontalGuides() throws {
        for cornerRadiusScaling in [true, false] {
            let shellPadding = NotchShellLayout.contentHorizontalPadding(
                cornerRadiusScaling: cornerRadiusScaling
            )

            for visibleSidebarCount in 1...3 {
                let layout = NotchHomeLayout(
                    closedNotchWidth: 185,
                    showTodo: visibleSidebarCount >= 1,
                    showCalendar: visibleSidebarCount >= 2,
                    showWeather: visibleSidebarCount >= 3,
                    availableScreenWidth: 1470,
                    contentHorizontalPadding: shellPadding
                )
                try expect(
                    abs((layout.openWidth - shellPadding) - layout.homeModulesContentWidth) <= 1,
                    "开启任意主页模块后，正文和顶栏必须严格共用同一组左右内容边界"
                )
            }
        }
    }

    private static func keepsAdvancedModuleCardsInsideTheAvailableWidth() throws {
        for availableWidth in [320.0, 360.0, 459.0, 520.0] {
            let cardWidth = HomeModuleOrderSettingsLayout.cardWidth(
                availableWidth: availableWidth
            )
            let totalWidth = cardWidth * 4
                + HomeModuleOrderSettingsLayout.cardSpacing * 3
            try expect(
                totalWidth <= availableWidth,
                "高级设置的模块排序卡片不得撑破可用宽度"
            )
        }
    }

    private static func requestsLocationPermissionWithoutAnIndefiniteWaitingState() throws {
        let undecided = WeatherAutomaticLocationPolicy.action(for: .notDetermined)
        try expect(undecided == .requestAuthorization, "尚未决定定位权限时必须主动请求授权")
        try expect(
            WeatherAutomaticLocationPolicy.shouldActivateApplication(for: undecided),
            "请求定位授权前必须激活应用，确保系统授权窗口可以显示"
        )
        try expect(
            WeatherAutomaticLocationPolicy.statusMessage(for: undecided) == "请在系统弹窗中允许定位",
            "不得让用户一直看到含义不明确的等待定位授权"
        )
        try expect(
            WeatherAutomaticLocationPolicy.action(for: .authorizedAlways) == .requestLocation,
            "已有定位权限时必须立即请求当前位置"
        )
        try expect(
            WeatherAutomaticLocationPolicy.action(for: .denied) == .showPermissionHelp,
            "定位被拒绝时必须提示用户打开权限"
        )
    }

    private static func keepsWeatherLocationControlsInsideTheModuleWidth() throws {
        let layout = WeatherLocationControlsLayout()
        try expect(layout.spacing == 5, "两个定位按钮之间必须保留清晰间距")
        try expect(layout.horizontalPadding == 6, "胶囊按钮需要一致的横向内边距")
        try expect(layout.verticalPadding == 4, "胶囊按钮需要一致的纵向内边距")
        try expect(layout.statusIconSize == 12, "状态图标必须与两个按钮视觉对齐")
        try expect(
            layout.estimatedTotalWidth <= 153,
            "切换城市、当前位置和状态图标必须完整放入天气模块"
        )
    }

    private static func usesTheTrailingWeatherSlotForSourceAndStatus() throws {
        try expect(
            WeatherTrailingAccessoryPolicy.accessory(
                isLoading: false,
                isResolvingCity: false,
                statusMessage: nil
            ) == .source,
            "天气正常时当前位置右侧的小角落必须显示低调的数据来源按钮"
        )
        try expect(
            WeatherTrailingAccessoryPolicy.accessory(
                isLoading: true,
                isResolvingCity: false,
                statusMessage: nil
            ) == .progress,
            "天气加载时右侧角落必须优先显示进度"
        )
        try expect(
            WeatherTrailingAccessoryPolicy.accessory(
                isLoading: false,
                isResolvingCity: false,
                statusMessage: "更新失败"
            ) == .error,
            "天气失败时右侧角落必须优先显示感叹号"
        )
    }

    private static func sizesCityPickerAsALargePanel() throws {
        try expect(
            WeatherCityPickerLayout.width(visibleScreenWidth: 1_512) == 378,
            "常见笔记本屏幕上的城市弹窗必须能在天气模块右侧放下"
        )
        try expect(
            WeatherCityPickerLayout.width(visibleScreenWidth: 1_000) == 340,
            "较窄屏幕必须使用紧凑宽度以避免系统把弹窗翻到左侧"
        )
        try expect(
            WeatherCityPickerLayout.height(visibleScreenHeight: 900) == 324,
            "城市输入框下方必须保留充足但不过大的结果区域"
        )
        try expect(
            WeatherCityPickerLayout.height(visibleScreenHeight: 1_200) == 340,
            "高分辨率屏幕上的窗口必须限制最大高度"
        )
        try expect(
            WeatherCityPickerLayout.height(visibleScreenHeight: 600) == 300,
            "较矮屏幕仍需保留可读的最小窗口高度"
        )
    }

    private static func expiresCurrentLocationSuccessFeedbackAfterEightSeconds() throws {
        let refreshedAt = Date(timeIntervalSince1970: 30_000)
        try expect(
            WeatherCurrentLocationFeedbackPolicy.shouldHighlight(
                isAutomaticLocation: true,
                isLoading: false,
                refreshedAt: refreshedAt,
                now: refreshedAt.addingTimeInterval(7.9)
            ),
            "当前位置刷新成功后蓝色反馈必须保留约八秒"
        )
        try expect(
            !WeatherCurrentLocationFeedbackPolicy.shouldHighlight(
                isAutomaticLocation: true,
                isLoading: false,
                refreshedAt: refreshedAt,
                now: refreshedAt.addingTimeInterval(8)
            ),
            "八秒后当前位置按钮必须恢复普通白色样式"
        )
        try expect(
            !WeatherCurrentLocationFeedbackPolicy.shouldHighlight(
                isAutomaticLocation: false,
                isLoading: true,
                refreshedAt: refreshedAt,
                now: refreshedAt
            ),
            "手动城市模式不得高亮当前位置"
        )
    }

    private static func choosesTheFreshestHighQualityLocation() throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let staleButAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.0, longitude: 120.0),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-300)
        )
        let recentCoarse = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.0, longitude: 121.0),
            altitude: 0,
            horizontalAccuracy: 850,
            verticalAccuracy: 20,
            timestamp: now.addingTimeInterval(-2)
        )
        let recentAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 30.25, longitude: 120.16),
            altitude: 0,
            horizontalAccuracy: 35,
            verticalAccuracy: 10,
            timestamp: now.addingTimeInterval(-8)
        )

        let selected = WeatherLocationQualityPolicy.bestLocation(
            from: [staleButAccurate, recentCoarse, recentAccurate],
            now: now
        )
        try expect(selected === recentAccurate, "必须排除旧缓存定位并优先采用近期精度最高的坐标")

        let unusable = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 35.0, longitude: 110.0),
            altitude: 0,
            horizontalAccuracy: 20_000,
            verticalAccuracy: 50,
            timestamp: now
        )
        try expect(
            WeatherLocationQualityPolicy.bestLocation(from: [staleButAccurate, unusable], now: now) == nil,
            "过旧或误差过大的定位不得用于天气请求"
        )
    }

    private static func reordersModulesInHorizontalSettings() throws {
        let initial: [HomeModule] = [.player, .todo, .calendar, .weather]
        try expect(
            HomeModuleOrderPolicy.reordering(initial, moving: .player, to: .weather)
                == [.todo, .calendar, .weather, .player],
            "把播放器拖到最右侧时必须依次收拢中间模块"
        )
        try expect(
            HomeModuleOrderPolicy.reordering(initial, moving: .weather, to: .todo)
                == [.player, .weather, .todo, .calendar],
            "把天气拖到第二个位置时必须保持其他模块的相对顺序"
        )
        try expect(
            HomeModuleOrderPolicy.swapping(initial, .player, with: .weather)
                == [.weather, .todo, .calendar, .player],
            "依次点击两个横向卡片时必须可靠交换位置"
        )
    }

}

private final class KeyboardTestPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private func XCTUnwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw TestFailure.assertion("预期值不能为空") }
    return value
}
