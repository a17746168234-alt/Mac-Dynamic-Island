import Foundation

enum BatteryChargeEstimate {
    private static let maximumReasonableMinutes = 48 * 60

    static func minutes(from value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    /// Chooses the estimate closest to the battery hardware. IOPowerSources can
    /// retain an older, workload-based value for several minutes, while
    /// AppleSmartBattery exposes the controller's filtered estimate directly.
    static func preferredMinutesToEmpty(
        powerSourceMinutes: Int,
        controllerTimeRemaining: Int,
        controllerAverageMinutes: Int
    ) -> Int {
        if let controllerEstimate = reasonableMinutes(controllerTimeRemaining) {
            return controllerEstimate
        }
        if let controllerAverage = reasonableMinutes(controllerAverageMinutes) {
            return controllerAverage
        }
        return reasonableMinutes(powerSourceMinutes) ?? 0
    }

    static func text(
        isPluggedIn: Bool,
        isCharging: Bool,
        minutesToFullCharge: Int,
        minutesToEmpty: Int,
        levelPercent: Int
    ) -> String {
        if !isPluggedIn {
            guard minutesToEmpty > 0 else {
                return "正在估算剩余续航…"
            }
            return "预计剩余 \(durationText(minutes: minutesToEmpty))续航"
        }

        if levelPercent >= 100 {
            return "电池已充满"
        }
        guard minutesToFullCharge > 0 else {
            return isCharging ? "正在估算充满时间…" : "已连接电源，暂未充电"
        }
        return "预计还需 \(durationText(minutes: minutesToFullCharge))充满"
    }

    private static func durationText(minutes totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        if hours > 0 {
            return "\(hours)小时"
        }
        return "\(minutes)分钟"
    }

    private static func reasonableMinutes(_ minutes: Int) -> Int? {
        guard (1...maximumReasonableMinutes).contains(minutes) else { return nil }
        return minutes
    }
}
