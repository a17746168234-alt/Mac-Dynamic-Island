import Foundation

enum PersonalBatteryPredictionPreferences {
    static let enabledKey = "personalBatteryPredictionEnabled"
    static let learningStateKey = "personalBatteryPredictionLearningState.v1"

    static var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }
}

enum BatteryUsageCategory: String, Codable, CaseIterable {
    case development
    case browsing
    case communication
    case office
    case media
    case creative
    case gaming
    case general

    var displayName: String {
        switch self {
        case .development: "开发工作"
        case .browsing: "网页浏览"
        case .communication: "沟通会议"
        case .office: "办公文档"
        case .media: "影音播放"
        case .creative: "创作处理"
        case .gaming: "游戏娱乐"
        case .general: "日常使用"
        }
    }

    static func classify(bundleIdentifier: String?) -> BatteryUsageCategory {
        guard let identifier = bundleIdentifier?.lowercased(), !identifier.isEmpty else {
            return .general
        }

        if containsAny(identifier, ["xcode", "jetbrains", "visual-studio-code", "vscode", "zed", "sublime", "terminal", "iterm", "warp", "cursor", "qoder", "codex", "chatgpt"]) {
            return .development
        }
        if containsAny(identifier, ["safari", "chrome", "firefox", "arc", "edge", "opera", "brave"]) {
            return .browsing
        }
        if containsAny(identifier, ["wechat", "weixin", "slack", "zoom", "teams", "telegram", "discord", "dingtalk", "feishu", "lark"]) {
            return .communication
        }
        if containsAny(identifier, ["microsoft.word", "microsoft.excel", "microsoft.powerpoint", "pages", "numbers", "keynote", "notion", "obsidian"]) {
            return .office
        }
        if containsAny(identifier, ["music", "spotify", "vlc", "iina", "quicktime", "podcasts", "netflix", "infuse"]) {
            return .media
        }
        if containsAny(identifier, ["adobe", "affinity", "finalcut", "davinci", "blender", "logic", "garageband", "captureone", "pixelmator"]) {
            return .creative
        }
        if containsAny(identifier, ["steam", "epicgames", "battle.net", "minecraft", "riot", "unity"]) {
            return .gaming
        }
        return .general
    }

    private static func containsAny(_ identifier: String, _ fragments: [String]) -> Bool {
        fragments.contains { identifier.contains($0) }
    }
}

struct BatteryPredictionInput {
    let timestamp: Date
    let isOnBattery: Bool
    let controllerMinutes: Int
    let remainingCapacityMilliampHours: Int
    let dischargeCurrentMilliamps: Int
    let usageCategory: BatteryUsageCategory
    let isLowPowerMode: Bool
    let displayCount: Int
}

struct BatteryPredictionSnapshot: Equatable {
    let predictedMinutes: Int
    let lowerBoundMinutes: Int
    let upperBoundMinutes: Int
    let controllerMinutes: Int
    let confidence: Double
    let sampleCount: Int
    let learningDays: Int
    let usageCategory: BatteryUsageCategory
    let isPersonalized: Bool

    static let unavailable = BatteryPredictionSnapshot(
        predictedMinutes: 0,
        lowerBoundMinutes: 0,
        upperBoundMinutes: 0,
        controllerMinutes: 0,
        confidence: 0,
        sampleCount: 0,
        learningDays: 0,
        usageCategory: .general,
        isPersonalized: false
    )
}

private struct BatteryRunningProfile: Codable, Equatable {
    private static let maximumEffectiveSamples = 1_440

    var sampleCount = 0
    var meanMilliamps = 0.0
    var squaredDifferenceSum = 0.0

    mutating func record(_ milliamps: Double) {
        if sampleCount >= Self.maximumEffectiveSamples {
            squaredDifferenceSum *= Double(Self.maximumEffectiveSamples - 1)
                / Double(Self.maximumEffectiveSamples)
            sampleCount = Self.maximumEffectiveSamples - 1
        }
        sampleCount += 1
        let delta = milliamps - meanMilliamps
        meanMilliamps += delta / Double(sampleCount)
        let nextDelta = milliamps - meanMilliamps
        squaredDifferenceSum += delta * nextDelta
    }

    var standardDeviation: Double {
        guard sampleCount > 1 else { return 0 }
        return sqrt(max(0, squaredDifferenceSum / Double(sampleCount - 1)))
    }
}

private struct BatteryPredictionLearningState: Codable, Equatable {
    var schemaVersion = 1
    var totalSamples = 0
    var activeDayKeys: [String] = []
    var lastSampleDate: Date?
    var globalProfile = BatteryRunningProfile()
    var contextProfiles: [String: BatteryRunningProfile] = [:]
    var periodProfiles: [String: BatteryRunningProfile] = [:]
}

struct PersonalBatteryPredictionEngine {
    private static let minimumSampleInterval: TimeInterval = 45
    private static let minimumDischargeCurrent = 80
    private static let maximumDischargeCurrent = 12_000
    private static let maximumMinutes = 48 * 60

    private var learningState: BatteryPredictionLearningState
    private var recentDischargeRates: [Double] = []

    init(persistedData: Data? = nil) {
        if let persistedData,
           let decoded = try? JSONDecoder().decode(BatteryPredictionLearningState.self, from: persistedData),
           decoded.schemaVersion == 1 {
            learningState = decoded
        } else {
            learningState = BatteryPredictionLearningState()
        }
    }

    var sampleCount: Int { learningState.totalSamples }
    var learningDays: Int { learningState.activeDayKeys.count }

    mutating func predictAndLearn(from input: BatteryPredictionInput) -> BatteryPredictionSnapshot {
        guard input.isOnBattery else {
            return snapshotWithoutPrediction(for: input)
        }

        let hasUsableTelemetry = input.remainingCapacityMilliampHours > 0
            && (Self.minimumDischargeCurrent...Self.maximumDischargeCurrent)
                .contains(input.dischargeCurrentMilliamps)

        if hasUsableTelemetry, shouldRecordSample(at: input.timestamp) {
            recordSample(from: input)
        }

        let controllerMinutes = reasonableMinutes(input.controllerMinutes) ?? 0
        let currentRate = hasUsableTelemetry ? Double(input.dischargeCurrentMilliamps) : nil
        let remainingCapacity = Double(input.remainingCapacityMilliampHours)
        let controllerRate: Double? = controllerMinutes > 0 && remainingCapacity > 0
            ? remainingCapacity * 60 / Double(controllerMinutes)
            : nil
        let recentRate = median(recentDischargeRates)

        guard let shortTermRate = blendedRate(
            primary: controllerRate,
            secondary: recentRate ?? currentRate,
            primaryWeight: 0.68
        ), shortTermRate > 0, remainingCapacity > 0 else {
            return BatteryPredictionSnapshot(
                predictedMinutes: controllerMinutes,
                lowerBoundMinutes: controllerMinutes,
                upperBoundMinutes: controllerMinutes,
                controllerMinutes: controllerMinutes,
                confidence: 0,
                sampleCount: learningState.totalSamples,
                learningDays: learningState.activeDayKeys.count,
                usageCategory: input.usageCategory,
                isPersonalized: false
            )
        }

        let contextKey = contextKey(for: input)
        let periodKey = periodKey(for: input.timestamp)
        let historicalRate = combinedHistoricalRate(contextKey: contextKey, periodKey: periodKey)
        let confidence = learningConfidence(contextKey: contextKey, periodKey: periodKey)
        let isPersonalized = historicalRate != nil && confidence >= 0.12

        if !isPersonalized, controllerMinutes > 0 {
            let uncertainty = 0.22
            return BatteryPredictionSnapshot(
                predictedMinutes: controllerMinutes,
                lowerBoundMinutes: clampMinutes(
                    Int((Double(controllerMinutes) * (1 - uncertainty)).rounded())
                ),
                upperBoundMinutes: clampMinutes(
                    Int((Double(controllerMinutes) * (1 + uncertainty)).rounded())
                ),
                controllerMinutes: controllerMinutes,
                confidence: confidence,
                sampleCount: learningState.totalSamples,
                learningDays: learningState.activeDayKeys.count,
                usageCategory: input.usageCategory,
                isPersonalized: false
            )
        }

        let personalInfluence = historicalRate == nil ? 0 : 0.45 * confidence
        let expectedRate = shortTermRate * (1 - personalInfluence)
            + (historicalRate ?? shortTermRate) * personalInfluence
        let predictedMinutes = clampMinutes(Int((remainingCapacity * 60 / expectedRate).rounded()))
        let profileVariation = historicalVariation(contextKey: contextKey)
        let uncertainty = min(0.30, max(0.10, 0.22 - 0.10 * confidence + profileVariation * 0.18))
        let lowerBound = clampMinutes(Int((Double(predictedMinutes) * (1 - uncertainty)).rounded()))
        let upperBound = clampMinutes(Int((Double(predictedMinutes) * (1 + uncertainty)).rounded()))

        return BatteryPredictionSnapshot(
            predictedMinutes: predictedMinutes,
            lowerBoundMinutes: min(lowerBound, predictedMinutes),
            upperBoundMinutes: max(upperBound, predictedMinutes),
            controllerMinutes: controllerMinutes,
            confidence: confidence,
            sampleCount: learningState.totalSamples,
            learningDays: learningState.activeDayKeys.count,
            usageCategory: input.usageCategory,
            isPersonalized: isPersonalized
        )
    }

    func persistedData() -> Data? {
        try? JSONEncoder().encode(learningState)
    }

    mutating func reset() {
        learningState = BatteryPredictionLearningState()
        recentDischargeRates.removeAll()
    }

    private mutating func recordSample(from input: BatteryPredictionInput) {
        let rate = Double(input.dischargeCurrentMilliamps)
        learningState.totalSamples += 1
        learningState.lastSampleDate = input.timestamp

        let dayKey = String(Int(input.timestamp.timeIntervalSince1970 / 86_400))
        if !learningState.activeDayKeys.contains(dayKey) {
            learningState.activeDayKeys.append(dayKey)
            if learningState.activeDayKeys.count > 45 {
                learningState.activeDayKeys.removeFirst(learningState.activeDayKeys.count - 45)
            }
        }

        learningState.globalProfile.record(rate)

        let context = contextKey(for: input)
        var contextProfile = learningState.contextProfiles[context] ?? BatteryRunningProfile()
        contextProfile.record(rate)
        learningState.contextProfiles[context] = contextProfile

        let period = periodKey(for: input.timestamp)
        var periodProfile = learningState.periodProfiles[period] ?? BatteryRunningProfile()
        periodProfile.record(rate)
        learningState.periodProfiles[period] = periodProfile

        recentDischargeRates.append(rate)
        if recentDischargeRates.count > 12 {
            recentDischargeRates.removeFirst(recentDischargeRates.count - 12)
        }
    }

    private func shouldRecordSample(at date: Date) -> Bool {
        guard let lastSampleDate = learningState.lastSampleDate else { return true }
        return date.timeIntervalSince(lastSampleDate) >= Self.minimumSampleInterval
    }

    private func contextKey(for input: BatteryPredictionInput) -> String {
        let powerMode = input.isLowPowerMode ? "low-power" : "normal"
        let displayMode = input.displayCount > 1 ? "multi-display" : "single-display"
        return "\(input.usageCategory.rawValue)|\(powerMode)|\(displayMode)"
    }

    private func periodKey(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date)
        let dayType = weekday == 1 || weekday == 7 ? "weekend" : "weekday"
        let period: String
        switch hour {
        case 5..<11: period = "morning"
        case 11..<17: period = "daytime"
        case 17..<23: period = "evening"
        default: period = "night"
        }
        return "\(dayType)|\(period)"
    }

    private func combinedHistoricalRate(contextKey: String, periodKey: String) -> Double? {
        let candidates: [(BatteryRunningProfile?, Double)] = [
            (learningState.contextProfiles[contextKey], 0.55),
            (learningState.periodProfiles[periodKey], 0.25),
            (learningState.globalProfile, 0.20),
        ]

        var weightedRate = 0.0
        var totalWeight = 0.0
        for (profile, weight) in candidates {
            guard let profile, profile.sampleCount >= 18, profile.meanMilliamps > 0 else { continue }
            weightedRate += profile.meanMilliamps * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return weightedRate / totalWeight
    }

    private func learningConfidence(contextKey: String, periodKey: String) -> Double {
        let days = learningState.activeDayKeys.count
        guard days >= 2 else { return 0 }

        let sampleFactor = min(1, Double(learningState.totalSamples) / 720)
        let dayFactor = min(1, Double(days - 1) / 6)
        let contextSamples = learningState.contextProfiles[contextKey]?.sampleCount ?? 0
        let periodSamples = learningState.periodProfiles[periodKey]?.sampleCount ?? 0
        let contextFactor = min(1, Double(contextSamples) / 240)
        let periodFactor = min(1, Double(periodSamples) / 300)
        return min(1, 0.45 * sqrt(sampleFactor * dayFactor) + 0.35 * contextFactor + 0.20 * periodFactor)
    }

    private func historicalVariation(contextKey: String) -> Double {
        guard let profile = learningState.contextProfiles[contextKey],
              profile.sampleCount >= 18,
              profile.meanMilliamps > 0 else { return 0.12 }
        return min(0.60, profile.standardDeviation / profile.meanMilliamps)
    }

    private func snapshotWithoutPrediction(for input: BatteryPredictionInput) -> BatteryPredictionSnapshot {
        BatteryPredictionSnapshot(
            predictedMinutes: 0,
            lowerBoundMinutes: 0,
            upperBoundMinutes: 0,
            controllerMinutes: max(0, input.controllerMinutes),
            confidence: learningConfidence(
                contextKey: contextKey(for: input),
                periodKey: periodKey(for: input.timestamp)
            ),
            sampleCount: learningState.totalSamples,
            learningDays: learningState.activeDayKeys.count,
            usageCategory: input.usageCategory,
            isPersonalized: false
        )
    }

    private func reasonableMinutes(_ minutes: Int) -> Int? {
        guard (1...Self.maximumMinutes).contains(minutes) else { return nil }
        return minutes
    }

    private func clampMinutes(_ minutes: Int) -> Int {
        min(Self.maximumMinutes, max(1, minutes))
    }

    private func blendedRate(primary: Double?, secondary: Double?, primaryWeight: Double) -> Double? {
        switch (primary, secondary) {
        case let (primary?, secondary?):
            return primary * primaryWeight + secondary * (1 - primaryWeight)
        case let (primary?, nil): return primary
        case let (nil, secondary?): return secondary
        case (nil, nil): return nil
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
