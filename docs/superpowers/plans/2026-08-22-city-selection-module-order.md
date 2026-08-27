# 城市选择与主页模块排序 Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 让用户可在天气卡片中搜索并切换中国城市或回到当前位置；在不改变模块宽度与灵动岛总宽度的前提下，用 Command + 长按拖动交换播放器、待办、日历、天气的横向顺序，并在高级设置提供中文说明。

**Architecture:** 将可持久化的天气位置选择与主页模块顺序抽成可测试的纯模型/策略；WeatherManager 根据位置来源走手动坐标或高精度 Core Location；WeatherView 用 MapKit 搜索弹窗选择城市；NotchHomeView 从固定 HStack 改为由保存顺序驱动的 ForEach，并用受限的拖放协议实现“仅换序”。

**Tech Stack:** Swift 5、SwiftUI、AppKit、MapKit、CoreLocation、Defaults、URLSession、Xcode、独立 Swift/Python 回归测试。

**Spec:** `docs/superpowers/specs/2026-08-22-city-selection-module-order-design.md`

## Global Constraints

- 仅改城市选择、天气显示来源、主页模块横向排序与高级说明；不引入第三方天气密钥或服务。
- 天气仍使用 Open-Meteo；保留合规的数据来源链接，但删除卡片底部裸露的 “Open-Meteo” 文本。
- 手动城市与当前位置都必须真实生效，不能是视觉按钮。
- 拖动只能改变四个主页模块的相对顺序；不能改变模块宽度、灵动岛总宽度、纵向位置，也不能覆盖现有按钮和输入操作。
- 隐藏模块仍保留其排序位置；重新显示时恢复原相对顺序。
- 所有新增用户可见文字使用中文。
- 保留已有脏工作区与 `recovery/`、`安装包/` 中无关内容；不执行 git commit、push、reset 或覆盖用户文件。
- 发布后使用新版本 `1.1.5 (286)`；构建、签名、DMG、安装、启动和旧安装包移除均须有验证证据。

---

### Task 1: 添加可测试的天气位置与模块排序领域模型

**Files:**
- Modify: `MacDynamicIsland/components/Weather/WeatherModels.swift`
- Modify: `MacDynamicIsland/Constants.swift`
- Modify: `Tests/WeatherCoreTests.swift`

**Step 1: 先写失败测试。**

在 `WeatherCoreTests.swift` 增加下列断言：

```swift
func testManualLocationSelectionRoundTrip() throws {
    let location = WeatherManualLocation(displayName: "路南区 · 唐山市", latitude: 39.63, longitude: 118.15)
    let selection = WeatherLocationSelection.manual(location)
    let restored = try JSONDecoder().decode(WeatherLocationSelection.self,
                                            from: JSONEncoder().encode(selection))
    try expect(restored == selection, "手动位置应可持久化往返")
    try expect(restored.cacheIdentity == "manual:39.630000,118.150000", "缓存身份应绑定坐标")
}

func testHomeModuleOrderNormalizationAndMove() throws {
    let normalized = HomeModuleOrderPolicy.normalized([.weather, .player, .weather])
    try expect(normalized == [.weather, .player, .todo, .calendar], "缺失/重复顺序应被修复")
    try expect(HomeModuleOrderPolicy.moving([.player, .todo, .calendar, .weather],
                                             .weather, before: .todo)
               == [.player, .weather, .todo, .calendar], "拖放仅应交换横向顺序")
}
```

再覆盖隐藏模块过滤和“未按 Command 不可启动拖动”的策略断言。

**Step 2: 运行测试确认失败。**

Run:
```bash
swiftc -module-cache-path /tmp/mac_notch_swift_module_cache \
  MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift \
  -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests
```

Expected: 因 `WeatherManualLocation`、`WeatherLocationSelection`、`HomeModule`、`HomeModuleOrderPolicy` 不存在而编译失败。

**Step 3: 实现最小模型和 Defaults 键。**

在 `WeatherModels.swift` 增加：

```swift
struct WeatherManualLocation: Codable, Equatable {
    let displayName: String
    let latitude: Double
    let longitude: Double
}

enum WeatherLocationSelection: Codable, Equatable {
    case automatic
    case manual(WeatherManualLocation)
    var cacheIdentity: String { /* automatic 或稳定的六位坐标 */ }
}

enum HomeModule: String, CaseIterable, Codable, Identifiable {
    case player, todo, calendar, weather
    var id: String { rawValue }
}

enum HomeModuleOrderPolicy {
    static let defaultOrder: [HomeModule] = [.player, .todo, .calendar, .weather]
    static func normalized(_ order: [HomeModule]) -> [HomeModule] { /* 去重后补齐 */ }
    static func visibleOrder(order: [HomeModule], showTodo: Bool, showCalendar: Bool, showWeather: Bool) -> [HomeModule]
    static func moving(_ order: [HomeModule], _ source: HomeModule, before destination: HomeModule) -> [HomeModule]
    static func canStartDrag(commandPressed: Bool, longPressCompleted: Bool) -> Bool
}
```

在 `Constants.swift` 增加 Codable Defaults 键：天气位置选择、模块顺序；读取模块顺序时始终经过 `normalized`，兼容旧的/损坏的偏好值。

**Step 4: 再运行测试确认通过。**

Run: 同 Step 2。

Expected: 所有现有测试与新增模型测试通过。

### Task 2: 让 WeatherManager 按当前位置或手动城市实际刷新

**Files:**
- Modify: `MacDynamicIsland/components/Weather/WeatherManager.swift`
- Modify: `MacDynamicIsland/components/Weather/WeatherModels.swift`
- Modify: `Tests/WeatherCoreTests.swift`

**Step 1: 扩展失败测试。**

新增 `WeatherLocationSelection` 的缓存身份测试，以及在手动坐标切换后缓存不能复用为另一城市数据的测试。测试使用纯 `WeatherCachePolicy` 输入，不触网、不请求系统定位。

**Step 2: 运行 WeatherCoreTests，确认失败。**

Expected: 新缓存来源 API 不存在或旧缓存策略错误。

**Step 3: 最小实现。**

- 将天气快照缓存升级为 v4，并在 `WeatherSnapshot` 中写入 `locationIdentity`；旧 v1/v2/v3 缓存一律当作不可用，避免把路北区快照显示给路南区或手动城市。
- 新增 `@Published private(set) var locationSelection`，从 Defaults 还原。
- 提供：

```swift
func selectManualLocation(_ location: WeatherManualLocation)
func useCurrentLocation()
func refreshCurrentSelection(force: Bool)
```

- `selectManualLocation` 立即保存选择、使不匹配缓存失效，并以指定经纬度请求天气和反向地理编码。
- `useCurrentLocation` 保存 `.automatic`、清除手动来源缓存，并请求当前定位；使用既有 `WeatherLocationPolicy.desiredAccuracy` 的最佳精度。
- 自动模式仅在授权允许时请求定位；权限不足时保持已有天气并显示现有中文错误状态，不伪造定位成功。

**Step 4: 回归测试。**

Run: 同 Task 1。

Expected: v4 缓存只接受相同 `locationIdentity`；自动/手动模式逻辑测试通过。

### Task 3: 加入 MapKit 城市搜索与天气卡片操作

**Files:**
- Create: `MacDynamicIsland/components/Weather/WeatherLocationSearchService.swift`
- Modify: `MacDynamicIsland/components/Weather/WeatherView.swift`
- Modify: `Tests/WeatherInterfaceTests.py`

**Step 1: 写源代码界面回归测试。**

新增 Python 测试，断言 `WeatherView.swift` 包含：`切换城市`、`当前位置`、`数据来源`，且不再包含独立 `Link("Open-Meteo"` 底栏；所有加载/空结果/权限错误文字为中文。

**Step 2: 运行测试确认失败。**

Run:
```bash
python3 Tests/WeatherInterfaceTests.py
```

Expected: 当前 WeatherView 缺少城市操作，并仍包含旧的来源底栏。

**Step 3: 实现搜索服务。**

实现 `@MainActor final class WeatherLocationSearchService: NSObject, ObservableObject, MKLocalSearchCompleterDelegate`：

```swift
struct WeatherLocationSearchSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
}

func updateQuery(_ query: String)
func resolve(_ suggestion: WeatherLocationSearchSuggestion) async throws -> WeatherManualLocation
```

- 搜索限地址/地点结果，接受城市、区县、拼音或中文。
- 使用 `MKLocalSearchCompleter` 提供建议，并用 `MKLocalSearch` 把选择解析为真实坐标。
- 空输入、无结果、解析失败统一给出简短中文状态；不清空当前天气。

**Step 4: 实现 WeatherView。**

- 在天气模块的底部保留原有高度，使用两项紧凑按钮：`切换城市` 和 `当前位置`；当前来源对应按钮为蓝色。
- `切换城市` 显示锚定弹窗，包含搜索框、中文状态、可点击的建议列表；选择成功调用 `weatherManager.selectManualLocation` 并关闭弹窗。
- `当前位置` 调用 `weatherManager.useCurrentLocation()`，回到系统定位天气。
- 删除底部 `Open-Meteo` 裸文本；在城市文本旁保留小型可点 `ⓘ`，弹出/跳转到数据来源链接，满足 Open-Meteo 署名要求。
- 所有 popover 控件必须是真实 `TextField`/`Button`，不覆盖或吞掉天气卡片外的点击。

**Step 5: 运行界面和领域测试。**

Run:
```bash
python3 Tests/WeatherInterfaceTests.py
swiftc -module-cache-path /tmp/mac_notch_swift_module_cache \
  MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift \
  -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests
```

Expected: 两组测试通过。

### Task 4: 将固定主页 HStack 改为持久化横向模块排序

**Files:**
- Create: `MacDynamicIsland/components/Notch/HomeModuleReorderSupport.swift`
- Modify: `MacDynamicIsland/components/Notch/NotchHomeView.swift`
- Modify: `MacDynamicIsland/BoringViewModel.swift`
- Modify: `Tests/WeatherCoreTests.swift`

**Step 1: 增加失败测试。**

覆盖 `visibleOrder`：例如天气关闭后其位置不被删除，重新打开时仍按保存顺序返回；覆盖 `moving` 在同一项或无效项时保持规范化顺序。

**Step 2: 运行并确认失败。**

Expected: 新可见顺序/移动边界尚未实现或不符合要求。

**Step 3: 实现重排支撑层。**

创建 `HomeModuleReorderSupport.swift`，包含：

```swift
@MainActor final class HomeModuleOrderStore: ObservableObject {
    @Published private(set) var order: [HomeModule]
    func move(_ source: HomeModule, before destination: HomeModule)
}

struct HomeModuleDragHandle: View { /* Command + 0.35 秒长按后才启用本地拖放 */ }
```

- 拖放 type 仅限本应用私有 `UTType`；不会接收文件、URL 或剪贴板拖放。
- 拖动手势位于每个模块顶部的非交互空白条带，避免抢占播放器、待办输入框、日历或天气按钮。
- 未按 Command 时不启动拖动，所有原有交互保持原样。
- 被拖模块显示蓝色边框/轻微缩放，目标位置显示插入提示；放手即保存 Defaults。

**Step 4: 改写 NotchHomeView。**

从硬编码的四段 HStack 改为：

```swift
let modules = HomeModuleOrderPolicy.visibleOrder(...)
ForEach(modules) { module in
    if module != modules.first { Divider() }
    homeModuleView(module, layout: layout)
        .homeModuleReorderable(module, store: orderStore)
}
```

- `homeModuleView` 复用现有播放器、待办、日历、天气视图与每项已有 frame 宽度。
- 不改 `NotchHomeLayout` 的宽度计算；只改变子视图出现顺序。
- 相机和工具栏留在既有位置，不参与排序。
- 在 `BoringViewModel` 订阅顺序 Defaults，变更后刷新主页布局/窗口但不改变宽度。

**Step 5: 回归测试。**

Run: Task 3 的两条命令。

Expected: 顺序策略测试、天气界面检查和现有测试全部通过。

### Task 5: 高级设置说明与中文界面检查

**Files:**
- Modify: `MacDynamicIsland/components/Settings/SettingsView.swift`
- Modify: `Tests/WeatherInterfaceTests.py`

**Step 1: 写失败断言。**

测试 `SettingsView.swift` 含以下用户可见文字：

```
主页模块排序
展开灵动岛后，按住 Command 键，再长按播放器、待办、日历或天气模块并横向拖动，即可交换位置。松开后顺序会自动保存。
```

**Step 2: 运行确认失败。**

Run: `python3 Tests/WeatherInterfaceTests.py`

**Step 3: 实现最小设置项。**

在“高级”添加静态说明 Section（无无效开关、无假按钮），与已有设置样式一致。说明只描述已实现的横向换序和保存行为。

**Step 4: 运行测试。**

Expected: 中文文案和旧 Open-Meteo 底栏检查通过。

### Task 5.5: 修复接通电源后充满预计时间未显示

**Files:**
- Modify: `MacDynamicIsland/managers/BatteryActivityManager.swift`
- Modify: `MacDynamicIsland/models/BatteryStatusViewModel.swift`
- Modify: `MacDynamicIsland/components/Live activities/BoringBattery.swift`
- Modify: `Tests/BatteryChargeEstimateTests.swift`

**Root-cause evidence:** 2026-08-22 本机 `pmset -g batt` 显示 `1:26 remaining`，IOKit `Time to Full Charge` 字段为 `NSNumber(82)`；原应用将多个电池变更事件每个延迟一秒排队转发。接电后的菜单可在“充电状态”已更新、剩余时间事件尚未送达时读取旧值 `0`。

**Step 1: 写失败测试。**

为充电估算增加“有有效剩余分钟时优先显示预计充满、未提供预计分钟时才显示优化充电”的断言；并为 IOKit 数值归一化增加 `NSNumber` 与 `Int` 都能保留分钟数的纯函数断言。

**Step 2: 运行失败测试。**

Run:
```bash
swiftc MacDynamicIsland/models/BatteryChargeEstimate.swift Tests/BatteryChargeEstimateTests.swift \
  -o /tmp/mac_notch_battery_estimate_tests && /tmp/mac_notch_battery_estimate_tests
```

Expected: 新的数值归一化/刷新接口尚不存在，测试编译或断言失败。

**Step 3: 实现单一根因修复。**

- 在 `BatteryActivityManager` 将可选的 IOKit 数值通过 `NSNumber.intValue` 归一化，避免桥接差异吞掉 `Time to Full Charge`。
- 暴露无副作用的即时快照读取方法；不再依赖慢速通知队列才能得到预计分钟。
- `BatteryStatusViewModel.refreshBatteryInfo()` 在主线程立刻更新完整快照。
- 电池弹窗打开前调用该刷新方法，使点击后一定读取本次 IOKit 状态；保留原有后台通知作为后续更新机制。
- 不更改未接电、满电、优化充电的既有文案规则。

**Step 4: 回归。**

Run: Step 2 命令，以及全量构建前的电池界面源检查。

Expected: 有效分钟数显示“预计还需 … 充满”；系统确实未提供分钟数时才显示“已开启优化充电”。

### Task 5.6: 固定展开灵动岛顶部电池的右侧对齐

**Files:**
- Modify: `MacDynamicIsland/ContentView.swift`
- Modify: `MacDynamicIsland/components/Notch/BoringHeader.swift`

**Root-cause evidence:** 展开态 `ContentView.NotchLayout` 只给 `BoringHeader` 指定高度，未给宽度；其内部 `HStack` 因此按内容的固有宽度排版。主菜单模块增多时，顶部工具栏不会获得展开灵动岛的完整宽度，电池就停在中间而不是右边缘。

**Step 1: 最小布局修复。**

- 在展开态为 `BoringHeader` 提供整个灵动岛的可用宽度，并要求顶栏在该宽度内右对齐。
- 在 `BoringHeader` 右侧加入固定、很小的安全边距，使 100% 电量时仍不触及圆角边缘；左侧标签、右侧工具按钮与电池保持同一行。
- 不改电池图标或百分比的尺寸，不改 `NotchHomeLayout` 的模块宽度。

**Step 2: 人工回归。**

- 分别只显示播放器+一个模块、显示三个模块、显示四个模块，确认电池右缘始终与灵动岛右缘保持同一安全间距。
- 确认 100% 电量文字不会与电池图标或圆角重叠。

### Task 6: 全量构建、版本、打包、安装与运行验证

**Files:**
- Modify: `VERSIONING.md`
- Modify: 项目版本配置（通过 `scripts/bump_version.py`）
- Create: `recovery/2026-08-22-v1.1.5/` 下的源码快照
- Create: `安装包/Mac灵动岛-1.1.5.dmg`

**Step 1: 运行所有回归测试。**

Run:
```bash
python3 Tests/WeatherInterfaceTests.py
python3 Tests/TodoChineseTests.py
swiftc -module-cache-path /tmp/mac_notch_swift_module_cache \
  MacDynamicIsland/components/Weather/WeatherModels.swift Tests/WeatherCoreTests.swift \
  -o /tmp/mac_notch_weather_tests && /tmp/mac_notch_weather_tests
```

Expected: 所有命令退出码 0。

**Step 2: 仅在测试通过后升级版本。**

Run:
```bash
python3 scripts/bump_version.py 1.1.5 286
```

Expected: `MARKETING_VERSION=1.1.5`、`CURRENT_PROJECT_VERSION=286`，并同步更新版本说明。

**Step 3: Release 构建。**

Run:
```bash
xcodebuild -project MacDynamicIsland.xcodeproj -scheme MacDynamicIsland -configuration Release \
  -derivedDataPath /tmp/MacNotchDerivedData-1.1.5 build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`。

**Step 4: 签名并制作 DMG。**

- 将 Release `.app` 暂存、`codesign --force --deep --sign -`，并用 `codesign --verify --deep --strict --verbose=2` 验证。
- 创建 `安装包/Mac灵动岛-1.1.5.dmg`，用 `hdiutil verify` 验证镜像。
- 在 `recovery/2026-08-22-v1.1.5/` 保存对应源码/版本快照，不触碰旧恢复包。

**Step 5: 安装、清理旧版、启动、验证。**

- 先读取 `/Applications/Mac灵动岛.app/Contents/Info.plist` 确认旧版为 1.1.4/285。
- 精确退出运行中的旧 app；把旧 `.app` 与旧 `安装包/Mac灵动岛-1.1.4.dmg` 移到废纸篓（可恢复），再安装新 `.app`。
- 用 `open -n /Applications/Mac灵动岛.app` 启动。
- 验证已安装 Info.plist 为 1.1.5/286、签名有效、DMG 有效且 `ps` 显示从 `/Applications/Mac灵动岛.app` 运行。

**Step 6: 最终人工核验。**

- 打开天气卡片：确认“切换城市 / 当前位置”可点击、搜索弹窗能输入，手动结果可变更天气；回到当前位置生效。
- 展开主页：确认按住 Command、长按顶部空白后可把模块互换，松开重开后顺序仍在；不按 Command 时播放器/待办/天气控制保持可点击。
- 检查没有英文 “Open-Meteo” 底栏、没有无效设置按钮、模块间 divider 与宽度稳定。

**Step 7: 交付。**

报告新 DMG 路径、安装/运行版本和通过的测试。不要执行 git commit 或 push。
