# Mac灵动岛无密钥天气 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Open-Meteo 替换和风天气，使中国地区无需 API Key 即可显示天气，并移除定位后的凭据阻塞。

**Architecture:** `WeatherModels.swift` 定义 Open-Meteo 响应、URL 构造、WMO 映射与可测试权限策略；`WeatherManager.swift` 只负责定位、无认证网络请求、反向地理编码和缓存；`WeatherView.swift` 保留现有卡片尺寸，设置页只保留开关、定位和刷新。首次启动迁移版本时以固定 service/account 删除旧钥匙串项。

**Tech Stack:** Swift 5、SwiftUI、CoreLocation、URLSession、Security、Defaults、xcodebuild

**Spec:** `docs/superpowers/specs/2026-08-22-open-meteo-migration.md`

## Global Constraints

- macOS 最低版本保持 14.0，不引入第三方依赖。
- 不读取、打印或传输旧和风天气凭据。
- 不修改天气模块以外的现有业务布局。
- 缓存时效保持 30 分钟，天气卡片保持 165 × 120。
- 不提交或推送用户现有未提交改动。

---

### Task 1: Open-Meteo 核心契约

**Files:**
- Modify: `Tests/WeatherCoreTests.swift`
- Modify: `MacDynamicIsland/components/Weather/WeatherModels.swift`

**Interfaces:**
- Produces: `OpenMeteoCurrentResponse`, `OpenMeteoRequestBuilder.weatherURL(longitude:latitude:)`, `WMOWeatherMapper.description(for:)`。
- Preserves: `WeatherSnapshot`, `WeatherCachePolicy`, `WeatherIconMapper`, `NotchHomeLayout`。

- [ ] **Step 1: 写失败测试**

加入官方响应形状的字面 JSON，断言温度四舍五入为 30、湿度为 65、WMO 代码 1 显示“晴间多云”；断言 URL 的 host 为 `api.open-meteo.com`、path 为 `/v1/forecast`、含经纬度、`timezone=auto` 与规定的 current 字段；断言 macOS 的 `authorizedAlways` 无需凭据即可返回刷新动作。

- [ ] **Step 2: 确认测试按预期失败**

Run: `swiftc -module-cache-path /tmp/mac_notch_swift_module_cache MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: FAIL，缺少 `OpenMeteoCurrentResponse` 或 `OpenMeteoRequestBuilder`。

- [ ] **Step 3: 实现最小核心类型**

响应字段使用以下接口：

```swift
struct OpenMeteoCurrentResponse: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature2m: Double
        let relativeHumidity2m: Int
        let isDay: Int
        let weatherCode: Int
    }
    let current: Current
}
```

URL 只构造 `https://api.open-meteo.com/v1/forecast`，current 值固定为 `temperature_2m,relative_humidity_2m,is_day,weather_code`。权限策略在 `.authorizedAlways` 时直接允许刷新，不再依赖凭据。

- [ ] **Step 4: 运行核心测试确认通过**

Run: `swiftc -module-cache-path /tmp/mac_notch_swift_module_cache MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: `WeatherCoreTests: PASS`。

### Task 2: 无密钥定位和网络请求

**Files:**
- Modify: `MacDynamicIsland/components/Weather/WeatherManager.swift`

**Interfaces:**
- Consumes: `OpenMeteoRequestBuilder`, `OpenMeteoCurrentResponse`, `WeatherSnapshot`。
- Produces: 无凭据依赖的 `requestLocationAndRefresh(force:)` 和一次性 `deleteLegacyQWeatherCredentials()`。

- [ ] **Step 1: 移除凭据前置条件**

删除 `hasCredentials`、`hasAPIKey`、保存 Host/Key 接口和 QWeather 请求头；请求定位不再检查钥匙串。

- [ ] **Step 2: 修复授权状态**

所有权限 switch 与授权变化回调在 macOS 授权状态下直接处理：

```swift
case .authorizedAlways:
    isLoading = true
    locationManager.requestLocation()
```

- [ ] **Step 3: 接入 Open-Meteo 与地区名**

对 Open-Meteo URL 发起 15 秒 GET 请求，不设置授权头；解码后以 `CLGeocoder.reverseGeocodeLocation` 获取地区名，失败时使用“当前位置”；成功后保存缓存，失败时保留已有快照并显示中文错误。

- [ ] **Step 4: 删除旧凭据**

初始化时针对 bundle service 加 `.weather`，分别 `SecItemDelete` 固定账户 `qweather-api-host` 和 `qweather-api-key`，不调用读取接口。

- [ ] **Step 5: 运行核心测试**

Run: `swiftc -module-cache-path /tmp/mac_notch_swift_module_cache MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: `WeatherCoreTests: PASS`。

### Task 3: 精简天气界面

**Files:**
- Modify: `MacDynamicIsland/components/Weather/WeatherView.swift`

**Interfaces:**
- Consumes: `WeatherManager.shared`、`.showWeather`。
- Produces: 不含凭据输入的 `WeatherSettings`。

- [ ] **Step 1: 替换来源和空状态**

卡片来源改为 `https://open-meteo.com/` 与“Open-Meteo”；无数据时统一使用定位图标，不再显示密钥图标。

- [ ] **Step 2: 删除凭据 UI**

删除 Host、Key、保存、更新、清除凭据和键盘焦点状态；设置仅保留首页开关、权限状态、授权/刷新/打开系统设置按钮。

- [ ] **Step 3: 编译验证**

Run: `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -configuration Debug -derivedDataPath /tmp/MacNotchDerivedData build CODE_SIGNING_ALLOWED=NO`

Expected: `BUILD SUCCEEDED`。

### Task 4: 版本、发布与实机验收

**Files:**
- Modify: `MacDynamicIsland.xcodeproj/project.pbxproj`
- Create: `安装包/Mac灵动岛-1.1.3.dmg`
- Create: `recovery/2026-08-22-v1.1.3/Mac灵动岛-v1.1.3-source.tar.gz`

**Interfaces:**
- Produces: 已安装并运行的 1.1.3。

- [ ] **Step 1: 版本升级**

将营销版本从 1.1.2 升到 1.1.3，并递增构建号。

- [ ] **Step 2: 完整验证**

运行核心测试、Debug 构建、Release 构建、`git diff --check`，检查产物版本和签名。

- [ ] **Step 3: 删除本机旧钥匙串项**

只删除 service `theboringteam.boringnotch.weather` 下账户 `qweather-api-host` 与 `qweather-api-key`，随后用不返回值的查询确认不存在。

- [ ] **Step 4: 打包、安装并打开**

生成恢复包与 DMG；退出旧进程，用新构建替换 `/Applications/Mac灵动岛.app` 并打开，验证运行进程与 1.1.3 版本。

- [ ] **Step 5: 清理旧安装包**

将旧版 DMG 移到废纸篓并报告可恢复位置；保留新 DMG。
