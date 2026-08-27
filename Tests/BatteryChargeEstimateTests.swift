import Foundation

private enum BatteryEstimateTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw BatteryEstimateTestFailure.assertion(message) }
}

@main
struct BatteryChargeEstimateTests {
    static func main() throws {
        try expect(
            BatteryChargeEstimate.minutes(from: NSNumber(value: 82)) == 82,
            "IOKit 以 NSNumber 提供充满时间时必须保留分钟数"
        )
        try expect(
            BatteryChargeEstimate.minutes(from: NSNumber(value: 0)) == 0,
            "系统没有预计时间时必须保留 0，供优化充电提示使用"
        )
        try expect(
            BatteryChargeEstimate.preferredMinutesToEmpty(
                powerSourceMinutes: 668,
                controllerTimeRemaining: 283,
                controllerAverageMinutes: 283
            ) == 283,
            "上层续航缓存偏高时必须优先使用电池控制器的实时过滤估算"
        )
        try expect(
            BatteryChargeEstimate.preferredMinutesToEmpty(
                powerSourceMinutes: 668,
                controllerTimeRemaining: 65_535,
                controllerAverageMinutes: 0
            ) == 668,
            "控制器返回未知哨兵值时必须回退到系统续航估算"
        )
        try expect(
            BatteryChargeEstimate.preferredMinutesToEmpty(
                powerSourceMinutes: 0,
                controllerTimeRemaining: 0,
                controllerAverageMinutes: 241
            ) == 241,
            "控制器即时值不可用时必须使用其平均续航估算"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: true,
                isCharging: true,
                minutesToFullCharge: 68,
                minutesToEmpty: 0,
                levelPercent: 80
            )
                == "预计还需 1小时8分钟充满",
            "一小时以上必须同时显示小时和分钟"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: true,
                isCharging: true,
                minutesToFullCharge: 45,
                minutesToEmpty: 0,
                levelPercent: 80
            )
                == "预计还需 45分钟充满",
            "不足一小时只显示分钟"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: false,
                isCharging: false,
                minutesToFullCharge: 0,
                minutesToEmpty: 221,
                levelPercent: 80
            ) == "预计剩余 3小时41分钟续航",
            "未连接电源时必须显示系统提供的剩余续航时间"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: true,
                isCharging: true,
                minutesToFullCharge: 0,
                minutesToEmpty: 0,
                levelPercent: 80
            ) == "正在估算充满时间…",
            "正在充电但系统尚未给出时间时不得误报优化充电"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: true,
                isCharging: false,
                minutesToFullCharge: 0,
                minutesToEmpty: 0,
                levelPercent: 80
            ) == "已连接电源，暂未充电",
            "连接电源但暂停充电时必须显示准确状态"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: true,
                isCharging: false,
                minutesToFullCharge: 0,
                minutesToEmpty: 0,
                levelPercent: 100
            ) == "电池已充满",
            "已经充满时必须显示明确状态"
        )
        try expect(
            BatteryChargeEstimate.text(
                isPluggedIn: false,
                isCharging: false,
                minutesToFullCharge: 0,
                minutesToEmpty: 0,
                levelPercent: 74
            ) == "正在估算剩余续航…",
            "未插电但系统尚未给出时间时必须显示估算状态"
        )
        print("BatteryChargeEstimateTests: PASS")
    }
}
