import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var timeToEmpty: Int = 0
    @Published private(set) var controllerTimeToEmpty: Int = 0
    @Published private(set) var predictionSnapshot: BatteryPredictionSnapshot = .unavailable
    @Published private(set) var statusText: String = ""

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?
    private var predictionRefreshTask: Task<Void, Never>?
    private var predictionEngine = PersonalBatteryPredictionEngine(
        persistedData: UserDefaults.standard.data(
            forKey: PersonalBatteryPredictionPreferences.learningStateKey
        )
    )
    private var lastPersistedPredictionSampleCount = 0
    private var lastUsageCategory: BatteryUsageCategory = .general

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
        startPredictionRefresh()
    }

    /// Sets up the initial power status by fetching battery information.
    private func setupPowerStatus() {
        updateBatteryInfo(managerBattery.initializeBatteryInfo())
    }

    /// Refreshes every battery field from one IOKit snapshot. Call this before
    /// presenting detailed information so a newly connected charger does not
    /// show the stale zero-minute value still waiting in the event queue.
    func refreshBatteryInfo() {
        updateBatteryInfo(managerBattery.currentBatteryInfo())
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            withAnimation(AppMotion.status) {
                self.isPluggedIn = isPluggedIn
                self.updateStatusText()
                self.notifyImportanChangeStatus()
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation(AppMotion.status) {
                self.levelBattery = level
                self.updateStatusText()
            }

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            self.notifyImportanChangeStatus()
            withAnimation(AppMotion.status) {
                self.isInLowPowerMode = isEnabled
                self.updateStatusText()
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            self.notifyImportanChangeStatus()
            withAnimation(AppMotion.status) {
                self.isCharging = isCharging
                self.updateStatusText()
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation(AppMotion.status) {
                self.timeToFullCharge = time
            }

        case .timeToEmptyChanged(let time):
            print("🕒 Time to empty: \(time) minutes")
            withAnimation(AppMotion.status) {
                self.controllerTimeToEmpty = time
                if !PersonalBatteryPredictionPreferences.isEnabled {
                    self.timeToEmpty = time
                }
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation(AppMotion.status) {
                self.maxCapacity = capacity
                self.updateStatusText()
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        let predictedTimeToEmpty = updatePersonalPrediction(from: batteryInfo)
        withAnimation(AppMotion.status) {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.controllerTimeToEmpty = batteryInfo.timeToEmpty
            self.timeToEmpty = predictedTimeToEmpty
            self.maxCapacity = batteryInfo.maxCapacity
            self.updateStatusText()
        }
    }

    func setPersonalPredictionEnabled(_ enabled: Bool) {
        PersonalBatteryPredictionPreferences.isEnabled = enabled
        refreshBatteryInfo()
    }

    func resetPersonalPredictionHistory() {
        predictionEngine.reset()
        UserDefaults.standard.removeObject(
            forKey: PersonalBatteryPredictionPreferences.learningStateKey
        )
        lastPersistedPredictionSampleCount = 0
        predictionSnapshot = BatteryPredictionSnapshot(
            predictedMinutes: controllerTimeToEmpty,
            lowerBoundMinutes: controllerTimeToEmpty,
            upperBoundMinutes: controllerTimeToEmpty,
            controllerMinutes: controllerTimeToEmpty,
            confidence: 0,
            sampleCount: 0,
            learningDays: 0,
            usageCategory: lastUsageCategory,
            isPersonalized: false
        )
        timeToEmpty = controllerTimeToEmpty
    }

    private func updatePersonalPrediction(from batteryInfo: BatteryInfo) -> Int {
        let usageCategory = currentUsageCategory()
        let controllerMinutes = batteryInfo.timeToEmpty

        guard PersonalBatteryPredictionPreferences.isEnabled else {
            predictionSnapshot = BatteryPredictionSnapshot(
                predictedMinutes: controllerMinutes,
                lowerBoundMinutes: controllerMinutes,
                upperBoundMinutes: controllerMinutes,
                controllerMinutes: controllerMinutes,
                confidence: predictionSnapshot.confidence,
                sampleCount: predictionEngine.sampleCount,
                learningDays: predictionEngine.learningDays,
                usageCategory: usageCategory,
                isPersonalized: false
            )
            return controllerMinutes
        }

        let telemetry = batteryInfo.telemetry
        let input = BatteryPredictionInput(
            timestamp: Date(),
            isOnBattery: !batteryInfo.isPluggedIn && !batteryInfo.isCharging,
            controllerMinutes: controllerMinutes,
            remainingCapacityMilliampHours: telemetry?.remainingCapacityMilliampHours ?? 0,
            dischargeCurrentMilliamps: telemetry?.dischargeCurrentMilliamps ?? 0,
            usageCategory: usageCategory,
            isLowPowerMode: batteryInfo.isInLowPowerMode,
            displayCount: max(1, NSScreen.screens.count)
        )
        let snapshot = predictionEngine.predictAndLearn(from: input)
        predictionSnapshot = snapshot
        persistPredictionLearningIfNeeded(sampleCount: snapshot.sampleCount)
        return snapshot.predictedMinutes > 0 ? snapshot.predictedMinutes : controllerMinutes
    }

    private func currentUsageCategory() -> BatteryUsageCategory {
        let identifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if identifier != Bundle.main.bundleIdentifier {
            lastUsageCategory = BatteryUsageCategory.classify(bundleIdentifier: identifier)
        }
        return lastUsageCategory
    }

    private func persistPredictionLearningIfNeeded(sampleCount: Int) {
        guard sampleCount != lastPersistedPredictionSampleCount,
              sampleCount == 1 || sampleCount.isMultiple(of: 5),
              let data = predictionEngine.persistedData() else { return }
        UserDefaults.standard.set(
            data,
            forKey: PersonalBatteryPredictionPreferences.learningStateKey
        )
        lastPersistedPredictionSampleCount = sampleCount
    }

    private func startPredictionRefresh() {
        predictionRefreshTask?.cancel()
        predictionRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                self.refreshBatteryInfo()
            }
        }
    }

    /// Keeps the compact notch message independent from transient IOKit event order.
    private func updateStatusText() {
        if maxCapacity > 0, levelBattery >= maxCapacity {
            statusText = String(localized: "Fully Charged")
        } else if isPluggedIn {
            statusText = String(localized: "Charged")
        } else {
            statusText = String(localized: "Power Disconnected")
        }
    }

    /// Notifies important changes in the battery status with an optional delay
    /// - Parameter delay: The delay before notifying the change, default is 0.0
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        predictionRefreshTask?.cancel()
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
