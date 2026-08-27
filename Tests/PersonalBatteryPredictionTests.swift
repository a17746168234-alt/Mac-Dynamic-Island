import Foundation

private enum PersonalBatteryPredictionTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw PersonalBatteryPredictionTestFailure.assertion(message)
    }
}

@main
struct PersonalBatteryPredictionTests {
    static func main() throws {
        try keepsControllerEstimateDuringColdStart()
        try learnsMultiDayUsageWithoutFollowingAStaleControllerValue()
        try adaptsWhenRecentHabitsChange()
        try ignoresInvalidTelemetryAndPersistsOnlyAggregateLearning()
        try classifiesUsageWithoutSavingApplicationNames()
        print("PersonalBatteryPredictionTests: PASS")
    }

    private static func adaptsWhenRecentHabitsChange() throws {
        var engine = PersonalBatteryPredictionEngine()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var earlier = BatteryPredictionSnapshot.unavailable
        var later = BatteryPredictionSnapshot.unavailable

        for sample in 0..<1_440 {
            earlier = engine.predictAndLearn(from: BatteryPredictionInput(
                timestamp: start.addingTimeInterval(Double(sample * 60)),
                isOnBattery: true,
                controllerMinutes: 400,
                remainingCapacityMilliampHours: 4_000,
                dischargeCurrentMilliamps: 700,
                usageCategory: .general,
                isLowPowerMode: false,
                displayCount: 1
            ))
        }
        for sample in 1_440..<2_880 {
            later = engine.predictAndLearn(from: BatteryPredictionInput(
                timestamp: start.addingTimeInterval(Double(sample * 60)),
                isOnBattery: true,
                controllerMinutes: 400,
                remainingCapacityMilliampHours: 4_000,
                dischargeCurrentMilliamps: 1_500,
                usageCategory: .general,
                isLowPowerMode: false,
                displayCount: 1
            ))
        }

        try expect(earlier.isPersonalized, "稳定历史建立后必须启用个性化预测")
        try expect(later.predictedMinutes < earlier.predictedMinutes - 35, "近期使用习惯变重后模型必须逐步降低预测，而不是永久受旧历史支配")
    }

    private static func keepsControllerEstimateDuringColdStart() throws {
        var engine = PersonalBatteryPredictionEngine()
        let snapshot = engine.predictAndLearn(from: BatteryPredictionInput(
            timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            isOnBattery: true,
            controllerMinutes: 240,
            remainingCapacityMilliampHours: 4_000,
            dischargeCurrentMilliamps: 1_500,
            usageCategory: .development,
            isLowPowerMode: false,
            displayCount: 1
        ))

        try expect(snapshot.predictedMinutes == 240, "冷启动时不得擅自偏离可靠的控制器估算")
        try expect(!snapshot.isPersonalized, "仅一个样本时不得宣称已经完成个性化")
        try expect(snapshot.learningDays == 1, "首个有效放电样本必须计入第一天")
    }

    private static func learnsMultiDayUsageWithoutFollowingAStaleControllerValue() throws {
        var engine = PersonalBatteryPredictionEngine()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var snapshot = BatteryPredictionSnapshot.unavailable

        for day in 0..<7 {
            for sample in 0..<120 {
                snapshot = engine.predictAndLearn(from: BatteryPredictionInput(
                    timestamp: start.addingTimeInterval(
                        Double(day * 86_400 + sample * 60)
                    ),
                    isOnBattery: true,
                    controllerMinutes: 480,
                    remainingCapacityMilliampHours: 4_000,
                    dischargeCurrentMilliamps: sample.isMultiple(of: 5) ? 1_100 : 1_250,
                    usageCategory: .development,
                    isLowPowerMode: false,
                    displayCount: 1
                ))
            }
        }

        try expect(snapshot.learningDays == 7, "跨七天的有效使用必须被识别为七个学习日")
        try expect(snapshot.sampleCount == 840, "每分钟有效样本必须去重后完整累计")
        try expect(snapshot.isPersonalized, "跨多天且样本充分时必须启用个人模型")
        try expect(snapshot.confidence > 0.85, "稳定的多日使用模式应达到高可信度")
        try expect(snapshot.predictedMinutes < 360, "个人高负载历史必须修正明显偏高的控制器值")
        try expect(snapshot.lowerBoundMinutes < snapshot.predictedMinutes, "预测必须提供保守下界")
        try expect(snapshot.upperBoundMinutes > snapshot.predictedMinutes, "预测必须提供宽松上界")
    }

    private static func ignoresInvalidTelemetryAndPersistsOnlyAggregateLearning() throws {
        var engine = PersonalBatteryPredictionEngine()
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        _ = engine.predictAndLearn(from: BatteryPredictionInput(
            timestamp: start,
            isOnBattery: true,
            controllerMinutes: 300,
            remainingCapacityMilliampHours: 4_000,
            dischargeCurrentMilliamps: 0,
            usageCategory: .general,
            isLowPowerMode: false,
            displayCount: 1
        ))
        try expect(engine.sampleCount == 0, "零电流或无效遥测不得污染个人历史")

        _ = engine.predictAndLearn(from: BatteryPredictionInput(
            timestamp: start.addingTimeInterval(60),
            isOnBattery: true,
            controllerMinutes: 300,
            remainingCapacityMilliampHours: 4_000,
            dischargeCurrentMilliamps: 900,
            usageCategory: .office,
            isLowPowerMode: true,
            displayCount: 2
        ))
        let data = try require(engine.persistedData(), "聚合学习状态必须可编码")
        let encodedText = String(decoding: data, as: UTF8.self)
        try expect(!encodedText.contains("com."), "持久化数据不得包含应用包名")

        let restored = PersonalBatteryPredictionEngine(persistedData: data)
        try expect(restored.sampleCount == 1, "重新启动后必须恢复有效样本数量")
        try expect(restored.learningDays == 1, "重新启动后必须恢复学习天数")

        var resetEngine = restored
        resetEngine.reset()
        try expect(resetEngine.sampleCount == 0, "清除学习记录必须完全重置聚合状态")
    }

    private static func classifiesUsageWithoutSavingApplicationNames() throws {
        try expect(
            BatteryUsageCategory.classify(bundleIdentifier: "com.apple.dt.Xcode") == .development,
            "Xcode 必须归入开发工作"
        )
        try expect(
            BatteryUsageCategory.classify(bundleIdentifier: "com.apple.Safari") == .browsing,
            "Safari 必须归入网页浏览"
        )
        try expect(
            BatteryUsageCategory.classify(bundleIdentifier: "com.tencent.xinWeChat") == .communication,
            "微信必须归入沟通会议"
        )
        try expect(
            BatteryUsageCategory.classify(bundleIdentifier: "unknown.application") == .general,
            "未知应用必须安全回退为日常使用"
        )
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw PersonalBatteryPredictionTestFailure.assertion(message)
        }
        return value
    }
}
