# Mac灵动岛天气与电池界面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Mac灵动岛加入安全的和风天气模块、动态主页宽度和紧凑黑色电池弹窗。

**Architecture:** 纯 Foundation 天气模型负责解析、缓存时效和主页布局计算；`WeatherManager` 封装 Core Location、URLSession 与 Keychain；SwiftUI 天气卡片和设置页只消费管理器状态。API 凭据仅保存在 macOS 钥匙串。

**Tech Stack:** Swift 5、SwiftUI、Combine、CoreLocation、Security、URLSession、Defaults、xcodebuild

**Spec:** `docs/superpowers/specs/2026-08-22-weather-and-battery.md`

## Global Constraints

- macOS 最低版本保持 14.0。
- 不引入新的第三方依赖。
- 不修改、提交或推送现有 GitHub 工作流清理、`recovery/` 和 `安装包/`。
- API Host 与 API KEY 不得出现在源代码、Git 差异、测试夹具或日志中。
- 天气刷新间隔为 30 分钟，主页天气卡片宽 165、高 120。

---

### Task 1: 天气核心模型与主页尺寸计算

**Files:**
- Create: `MacDynamicIsland/components/Weather/WeatherModels.swift`
- Create: `Tests/WeatherCoreTests.swift`

**Interfaces:**
- Produces: `WeatherSnapshot`, `QWeatherNowResponse`, `QWeatherLocationResponse`, `WeatherCachePolicy`, `NotchHomeLayout`。

- [ ] **Step 1: 写失败测试**

测试使用官方响应形状的字面 JSON，验证 `temp`、`humidity`、`icon`、`text` 解析；验证 30 分钟缓存边界；验证零至三个侧栏的播放器宽度和三项全开宽度大于 640。

- [ ] **Step 2: 确认测试因类型尚不存在而失败**

Run: `swiftc MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests`

Expected: FAIL，提示天气类型不存在或源文件不存在。

- [ ] **Step 3: 实现最小核心类型**

`WeatherSnapshot` 保存地区、温度、湿度、天气文字、图标代码和观测时间；`WeatherCachePolicy.isFresh` 以 1800 秒为边界；`NotchHomeLayout` 根据开关计算侧栏、播放器与展开宽度。

- [ ] **Step 4: 运行测试并确认通过**

Run: `swiftc MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: PASS，并输出 `WeatherCoreTests: PASS`。

### Task 2: 定位、网络、缓存与钥匙串

**Files:**
- Create: `MacDynamicIsland/components/Weather/WeatherManager.swift`
- Modify: `MacDynamicIsland/MacDynamicIsland.entitlements`
- Modify: `MacDynamicIsland.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WeatherSnapshot`, `QWeatherNowResponse`, `QWeatherLocationResponse`, `WeatherCachePolicy`。
- Produces: `WeatherManager.shared`, `saveCredentials(apiHost:apiKey:)`, `clearCredentials()`, `requestLocationAndRefresh(force:)`。

- [ ] **Step 1: 增加接口请求构造失败测试**

在核心测试中验证 API Host 标准化拒绝带路径或非和风域名，并验证天气 URL 使用 HTTPS、`/v7/weather/now`、经纬度最多两位小数和 `lang=zh`。

- [ ] **Step 2: 确认新增测试失败**

Run: `swiftc MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: FAIL，提示请求构造接口不存在。

- [ ] **Step 3: 实现 WeatherManager**

使用 `CLLocationManager` 请求当前位置；以 `X-QW-Api-Key` 请求头调用城市搜索和实时天气；成功数据编码到 `UserDefaults` 缓存；API Host 与 API KEY 通过 Security.framework 保存到当前 App 的 Keychain service。

- [ ] **Step 4: 增加定位权限**

在 entitlement 中加入 `com.apple.security.personal-information.location`；Debug 和 Release 配置加入 `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "用于显示当前位置的天气、温度和湿度"`。

- [ ] **Step 5: 运行核心测试**

Run: `swiftc MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: PASS。

### Task 3: 天气卡片与设置页

**Files:**
- Create: `MacDynamicIsland/components/Weather/WeatherView.swift`
- Modify: `MacDynamicIsland/components/Settings/SettingsView.swift`
- Modify: `MacDynamicIsland/models/Constants.swift`
- Modify: `MacDynamicIsland.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `WeatherManager.shared` 和 `.showWeather` Defaults key。
- Produces: `WeatherView` 与 `WeatherSettings`。

- [ ] **Step 1: 增加天气开关**

定义 `showWeather`，默认关闭；设置侧栏增加“天气”，设置页包含显示开关、定位授权、API Host、API KEY、安全保存、清除和手动刷新入口。

- [ ] **Step 2: 实现天气卡片**

卡片宽 165、高 120；成功时显示地区、天气图标、温度、湿度和“和风天气”；未配置、定位失败、加载和缓存状态均有紧凑占位。

- [ ] **Step 3: 在项目文件中加入新 Swift 文件**

将三个 Weather Swift 文件加入 Weather 分组和 app target Sources，不改变现有文件引用。

- [ ] **Step 4: 编译验证类型连接**

Run: `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -configuration Debug -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO`

Expected: BUILD SUCCEEDED。

### Task 4: 主页动态宽度与电池弹窗

**Files:**
- Modify: `MacDynamicIsland/components/Notch/NotchHomeView.swift`
- Modify: `MacDynamicIsland/models/BoringViewModel.swift`
- Modify: `MacDynamicIsland/components/Live activities/BoringBattery.swift`

**Interfaces:**
- Consumes: `NotchHomeLayout`, `.showWeather`, `WeatherView`。

- [ ] **Step 1: 接入天气侧栏**

播放器工具栏的侧栏判断包含天气；主页按待办、日历、天气顺序显示，每项前保留分隔线，天气与日历同宽。

- [ ] **Step 2: 接入动态尺寸**

监听三个 Defaults 开关；主页尺寸使用 `NotchHomeLayout`，三项全开时宽度大于 640，关闭任意项立即收窄。

- [ ] **Step 3: 收紧电池弹窗**

将弹窗改为约 248 宽、12 点内边距、黑色背景、白色主文字、灰色辅助文字和深色分隔线；保留所有状态和系统设置按钮。

- [ ] **Step 4: 运行 Debug 构建**

Run: `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -configuration Debug -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO`

Expected: BUILD SUCCEEDED。

### Task 5: 完整验证与交付

**Files:**
- Verify only; no credential files are created.

**Interfaces:**
- Consumes: 完整 app target。

- [ ] **Step 1: 运行核心测试**

Run: `swiftc MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests`

Expected: PASS。

- [ ] **Step 2: 运行 Debug 和 Release 构建**

Run: `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -configuration Debug -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO`

Run: `xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -configuration Release -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO`

Expected: 两次均 BUILD SUCCEEDED。

- [ ] **Step 3: 检查敏感信息和改动范围**

Run: `git diff --check && git status --short && git diff -- boringNotch MacDynamicIsland.xcodeproj Tests docs/superpowers`

Expected: 无 API KEY；现有 workflow 删除、`recovery/`、`安装包/` 保持原状。

- [ ] **Step 4: 启动新构建并确认进程**

打开本地 Debug 构建，确认进程保持运行；告知用户进入“设置 → 天气”粘贴 API Host 和 API KEY，再授权定位并启用天气。
