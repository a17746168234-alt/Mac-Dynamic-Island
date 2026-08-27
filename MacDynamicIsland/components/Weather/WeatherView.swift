import AppKit
import CoreLocation
import Defaults
import SwiftUI

struct WeatherView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var manager = WeatherManager.shared
    @StateObject private var citySearch = WeatherLocationSearchService()
    @State private var isCityPickerPresented = false
    @State private var cityQuery = ""
    @State private var isResolvingCity = false
    @State private var citySelectionError: String?
    @FocusState private var isCitySearchFocused: Bool

    var body: some View {
        Group {
            if let snapshot = manager.snapshot {
                weatherContent(snapshot)
            } else {
                emptyContent
            }
        }
        .frame(width: 165, height: 120, alignment: .topLeading)
        .onAppear {
            manager.requestLocationAndRefresh()
        }
        .popover(isPresented: $isCityPickerPresented, arrowEdge: .trailing) {
            cityPicker
        }
        .onChange(of: isCityPickerPresented) { _, isPresented in
            vm.isWeatherPopoverActive = isPresented
        }
        .onDisappear {
            vm.isWeatherPopoverActive = false
        }
    }

    private func weatherContent(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: WeatherIconMapper.systemSymbol(
                    for: snapshot.iconCode,
                    source: snapshot.source
                ))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 26, weight: .medium))
                Spacer(minLength: 2)
                Text("\(snapshot.temperatureCelsius)°")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }

            Text(snapshot.locationName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                Text(snapshot.conditionText)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Label("\(snapshot.humidityPercent)%", systemImage: "humidity.fill")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(white: 0.7))

            Spacer(minLength: 0)

            locationControls
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "location.circle")
                .font(.system(size: 24))
                .foregroundStyle(Color(white: 0.65))
            Text(manager.statusMessage ?? "正在准备天气…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 145)
            Spacer(minLength: 0)
            locationControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var locationControls: some View {
        let layout = WeatherLocationControlsLayout()
        return HStack(spacing: layout.spacing) {
            locationControlButton(
                title: "切换城市",
                systemImage: "magnifyingglass",
                isSelected: isManualLocation
            ) {
                citySelectionError = nil
                vm.isWeatherPopoverActive = true
                isCityPickerPresented = true
            }

            locationControlButton(
                title: "当前位置",
                systemImage: "location.fill",
                isSelected: manager.isCurrentLocationFeedbackHighlighted
            ) {
                manager.useCurrentLocation()
            }

            switch WeatherTrailingAccessoryPolicy.accessory(
                isLoading: manager.isLoading,
                isResolvingCity: isResolvingCity,
                statusMessage: manager.statusMessage
            ) {
            case .progress:
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: layout.statusIconSize, height: layout.statusIconSize)
                    .help(manager.statusMessage ?? "正在更新天气")
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                    .frame(width: layout.statusIconSize, height: layout.statusIconSize)
                    .help(manager.statusMessage ?? "天气更新失败")
            case .source:
                Link(destination: displayedSource.attributionURL) {
                    Image(systemName: "info.circle")
                }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.32))
                    .frame(width: layout.statusIconSize, height: layout.statusIconSize)
                    .help("数据来源：\(displayedSource.displayName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func locationControlButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let layout = WeatherLocationControlsLayout()
        return Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.vertical, layout.verticalPadding)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue.opacity(0.18) : Color.white.opacity(0.07))
                )
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 0.6)
                }
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(isSelected ? .blue : Color(white: 0.76))
    }

    private var isManualLocation: Bool {
        manager.locationSelection.mode == .manual
    }

    private var displayedSource: WeatherDataSource {
        manager.snapshot?.source ?? .openMeteo
    }

    private var cityPicker: some View {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_200, height: 900)
        return VStack(alignment: .leading, spacing: 10) {
            Text("切换天气城市")
                .font(.headline)

            TextField("搜索城市或区县", text: $cityQuery)
                .textFieldStyle(.roundedBorder)
                .focused($isCitySearchFocused)
                .onChange(of: cityQuery) { _, query in
                    citySearch.updateQuery(query)
                }
                .onSubmit {
                    citySearch.updateQuery(cityQuery)
                }

            Group {
                if isResolvingCity {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("正在切换天气城市…")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let citySelectionError {
                    Text(citySelectionError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let statusMessage = citySearch.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if citySearch.suggestions.isEmpty {
                    Text("输入城市、区县或地点名称开始搜索")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(citySearch.suggestions) { suggestion in
                                Button {
                                    select(suggestion)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.title)
                                            .foregroundStyle(.primary)
                                        if !suggestion.subtitle.isEmpty {
                                            Text(suggestion.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 7)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            Button("使用当前位置") {
                manager.useCurrentLocation()
                isCityPickerPresented = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(18)
        .frame(width: WeatherCityPickerLayout.width(
            visibleScreenWidth: visibleFrame.width
        ), height: WeatherCityPickerLayout.height(
            visibleScreenHeight: visibleFrame.height
        ), alignment: .topLeading)
        .background(
            WeatherSettingsWindowFocusBridge()
                .frame(width: 0, height: 0)
        )
        .onAppear {
            Task { @MainActor in
                isCitySearchFocused = true
            }
        }
    }

    private func select(_ suggestion: WeatherLocationSearchSuggestion) {
        isResolvingCity = true
        citySelectionError = nil
        Task {
            do {
                let location = try await citySearch.resolve(suggestion)
                manager.selectManualLocation(location)
                isResolvingCity = false
                isCityPickerPresented = false
            } catch {
                isResolvingCity = false
                citySelectionError = "无法切换到这个城市，请换一个结果重试"
            }
        }
    }
}

struct WeatherSettings: View {
    @Default(.showWeather) private var showWeather
    @ObservedObject private var manager = WeatherManager.shared
    @State private var qWeatherHost = ""
    @State private var qWeatherAPIKey = ""

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showWeather) {
                    Text("在首页显示天气")
                }
            } header: {
                Text("显示")
            } footer: {
                Text("天气模块与日历同宽；与日历、待办同时开启时，灵动岛会自动增宽。")
            }

            Section {
                Picker("天气引擎", selection: providerBinding) {
                    ForEach(WeatherProviderPreference.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                HStack {
                    Text("当前实际来源")
                    Spacer()
                    Text(manager.snapshot?.source.displayName ?? "尚未获取")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("数据来源")
            } footer: {
                Text(providerFooter)
            }

            if manager.providerPreference != .openMeteo {
                Section {
                    HStack {
                        TextField("API Host", text: $qWeatherHost)
                            .textContentType(.URL)
                            .onSubmit {
                                saveQWeatherHost()
                            }

                        Button("保存主机名") {
                            saveQWeatherHost()
                        }
                        .disabled(manager.isTestingCredentials)
                    }

                    SecureField("API Key", text: $qWeatherAPIKey)

                    Link(destination: URL(string: "https://console.qweather.com/")!) {
                        Label("打开和风天气控制台", systemImage: "arrow.up.right.square")
                    }
                    .help("前往和风天气控制台创建项目、API Host 和 API Key")

                    HStack {
                        Button(manager.isTestingCredentials ? "正在验证…" : "保存并测试") {
                            manager.saveAndTestQWeatherCredentials(
                                apiHost: qWeatherHost,
                                apiKey: qWeatherAPIKey
                            )
                        }
                        .disabled(manager.isTestingCredentials)

                        Button("清除 API Key", role: .destructive) {
                            manager.clearQWeatherCredentials()
                            qWeatherHost = manager.qWeatherHost
                            qWeatherAPIKey = ""
                        }
                        .disabled(!manager.hasQWeatherCredentials || manager.isTestingCredentials)

                        Spacer()

                        Label(
                            manager.hasQWeatherCredentials ? "已配置" : "未配置",
                            systemImage: manager.hasQWeatherCredentials
                                ? "checkmark.circle.fill"
                                : "exclamationmark.circle"
                        )
                        .foregroundStyle(manager.hasQWeatherCredentials ? .green : .secondary)
                    }

                    if let message = manager.credentialStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("和风天气 QWeather")
                } footer: {
                    Text("Host 独立保存，升级应用或清除 API Key 后仍会保留，也可随时手动修改。API Key 仅保存到 macOS 钥匙串。验证使用固定的北京坐标，不会发送你当前的位置。")
                }
            }

            Section {
                HStack {
                    Text("定位权限")
                    Spacer()
                    Text(authorizationLabel)
                        .foregroundStyle(.secondary)
                }

                switch locationAction {
                case .requestAuthorization:
                    Button("授权定位") {
                        manager.requestLocationAuthorization()
                    }
                case .refreshWeather:
                    Button("刷新天气") {
                        manager.requestLocationAndRefresh(force: true)
                    }
                case .openSystemSettings:
                    Button("打开系统定位设置") {
                        openLocationSettings()
                    }
                case nil:
                    Button(manager.isLoading ? "正在更新…" : "暂时无法刷新") {}
                        .disabled(true)
                }

                if let statusMessage = manager.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("当前位置")
            } footer: {
                Text("定位只用于请求你选择的天气服务和显示地区名称。")
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("天气")
        .onAppear {
            qWeatherHost = manager.qWeatherHost
        }
        .onChange(of: showWeather) { _, isEnabled in
            if isEnabled {
                manager.requestLocationAndRefresh()
            }
        }
    }

    private var providerBinding: Binding<WeatherProviderPreference> {
        Binding(
            get: { manager.providerPreference },
            set: { manager.setProviderPreference($0) }
        )
    }

    private func saveQWeatherHost() {
        manager.saveQWeatherHost(qWeatherHost)
        qWeatherHost = manager.qWeatherHost
    }

    private var providerFooter: String {
        switch manager.providerPreference {
        case .automatic:
            return manager.hasQWeatherCredentials
                ? "优先使用和风天气；服务暂时不可用时自动回退到 Open-Meteo。"
                : "尚未配置和风天气，因此自动使用无需 API Key 的 Open-Meteo。"
        case .qWeather:
            return "只使用和风天气；需要先保存并验证 API Host 与 API Key。"
        case .openMeteo:
            return "只使用 Open-Meteo，无需填写 API Key。"
        }
    }

    private var locationAction: WeatherSettingsLocationAction? {
        WeatherSettingsInteractionPolicy.locationAction(
            authorizationStatus: manager.authorizationStatus,
            isLoading: manager.isLoading
        )
    }

    private var authorizationLabel: String {
        switch manager.authorizationStatus {
        case .notDetermined: "尚未请求"
        case .restricted: "受系统限制"
        case .denied: "已拒绝"
        case .authorizedAlways: "已允许"
        @unknown default: "未知"
        }
    }

    private func openLocationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct WeatherSettingsWindowFocusBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> WeatherSettingsFocusView {
        WeatherSettingsFocusView(frame: .zero)
    }

    func updateNSView(_ nsView: WeatherSettingsFocusView, context: Context) {}
}
