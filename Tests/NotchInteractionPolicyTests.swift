import Foundation

private enum PolicyTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw PolicyTestFailure.assertion(message) }
}

@main
struct NotchInteractionPolicyTests {
    static func main() throws {
        try expect(
            NotchInteractionPolicy.autoCloseDelayMilliseconds == 150,
            "鼠标离开后的自动收回等待必须保持轻快"
        )
        try expect(
            NotchInteractionPolicy.graceAreaRecheckDelayMilliseconds == 150,
            "鼠标离开缓冲区后的再次判断不能产生明显拖延"
        )
        try expect(
            !NotchInteractionPolicy.canOpen(isFirstLaunch: true),
            "首次启动引导期间不得打开灵动岛"
        )
        try expect(
            NotchInteractionPolicy.canOpen(isFirstLaunch: false),
            "完成引导后必须允许打开灵动岛"
        )
        try expect(
            !NotchInteractionPolicy.shouldCloseNotch(
                isOpen: true,
                isHovering: false,
                activeLocks: [.popover],
                isSharing: false
            ),
            "天气或电池弹窗打开时鼠标离开不得关闭灵动岛"
        )
        try expect(
            NotchInteractionPolicy.shouldCloseNotch(
                isOpen: true,
                isHovering: false,
                activeLocks: [],
                isSharing: false
            ),
            "没有弹窗、分享或悬停时必须允许自动关闭"
        )
        try expect(
            !NotchInteractionPolicy.shouldCloseNotch(
                isOpen: true,
                isHovering: false,
                activeLocks: [.homeModuleReordering],
                isSharing: false,
            ),
            "模块排序期间拖动造成的短暂鼠标离开不得关闭灵动岛"
        )
        try expect(
            !NotchInteractionPolicy.shouldCloseAfterDrop(
                isSharing: false,
                activeLocks: [.homeModuleReordering]
            ),
            "设置内的模块排序拖放不得被外层拖放检测器关闭"
        )
        try expect(
            !NotchInteractionPolicy.shouldCloseNotch(
                isOpen: true,
                isHovering: false,
                activeLocks: [.settingsInteraction],
                isSharing: false
            ),
            "设置控件刷新造成的短暂悬停丢失不得关闭灵动岛"
        )
        try expect(
            NotchInteractionPolicy.shouldCloseAfterDrop(
                isSharing: false,
                activeLocks: []
            ),
            "普通页面拖放结束后必须保持原有自动收回行为"
        )
        try expect(
            NotchInteractionPolicy.shouldCloseNotch(
                isOpen: true,
                isHovering: false,
                activeLocks: [],
                isSharing: false
            ),
            "设置页未排序时鼠标离开必须允许正常收回"
        )
        try expect(
            !NotchInteractionPolicy.shouldCloseNotch(
                isOpen: true,
                isHovering: false,
                activeLocks: [],
                isSharing: false,
                pointerInsideGraceArea: true
            ),
            "鼠标仍在扩展缓冲区时不得自动收回"
        )
        try expect(
            NotchMotionPolicy.profile(isLowPowerMode: true, reduceMotion: true) == .reducedMotion,
            "系统减少动态效果必须优先于低电量动画配置"
        )
        try expect(
            NotchMotionPolicy.profile(isLowPowerMode: true, reduceMotion: false) == .lowPower,
            "低电量模式必须使用轻量动画配置"
        )
        try expect(
            NotchMotionPolicy.settleDuration(for: .opening, profile: .reducedMotion)
                < NotchMotionPolicy.settleDuration(for: .opening, profile: .standard),
            "减少动态效果时开合动画必须更短"
        )
        try expect(
            NotchMotionPolicy.settleDuration(for: .opening, profile: .standard) == 0.34,
            "普通模式开启动画必须保持在 340ms"
        )
        try expect(
            NotchMotionPolicy.settleDuration(for: .closing, profile: .standard) == 0.3,
            "普通模式关闭动画必须保持在 300ms"
        )
        try expect(
            NotchInteractionPolicy.autoCloseDelayMilliseconds == 150,
            "调整开合动画时不得改变鼠标离开后的 150ms 自动收回等待"
        )
        print("NotchInteractionPolicyTests: PASS")
    }
}
