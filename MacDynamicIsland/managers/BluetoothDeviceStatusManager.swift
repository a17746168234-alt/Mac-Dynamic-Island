import Defaults
import Foundation
import IOBluetooth
import IOKit
import SwiftUI

@MainActor
final class BluetoothDeviceStatusManager: NSObject, ObservableObject {
    static let shared = BluetoothDeviceStatusManager()

    @Published private(set) var connectedDevices: [BluetoothDeviceStatus] = []
    @Published private(set) var transientDevice: BluetoothDeviceStatus?

    private var transientDeviceTask: Task<Void, Never>?
    private var delayedRefreshTask: Task<Void, Never>?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var pendingConnectionIDs: Set<String> = []
    private var hasCompletedInitialRefresh = false

    private override init() {
        super.init()
        setEnabled(Defaults[.showBluetoothBatteryNotifications])
    }

    deinit {
        transientDeviceTask?.cancel()
        delayedRefreshTask?.cancel()
        connectNotification?.unregister()
        disconnectNotifications.values.forEach { $0.unregister() }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard connectNotification == nil else { return }
        hasCompletedInitialRefresh = false
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(_:device:))
        )
        refresh()
    }

    private func stopMonitoring() {
        transientDeviceTask?.cancel()
        transientDeviceTask = nil
        delayedRefreshTask?.cancel()
        delayedRefreshTask = nil
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        pendingConnectionIDs.removeAll()
        hasCompletedInitialRefresh = false
        if !connectedDevices.isEmpty {
            connectedDevices = []
        }
        if transientDevice != nil {
            transientDevice = nil
        }
    }

    func refresh() {
        guard Defaults[.showBluetoothBatteryNotifications] else { return }
        let batteryRecords = readBatteryRecords()
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }

        let refreshedDevices = devices.map { device in
            let name = device.nameOrAddress ?? device.addressString ?? String(localized: "Bluetooth Device")
            let record = batteryRecords.first { record in
                namesLikelyMatch(record.name, name)
            }
            return BluetoothDeviceStatus(
                id: device.addressString ?? name,
                name: name,
                battery: record?.battery,
                leftBattery: record?.leftBattery,
                rightBattery: record?.rightBattery,
                caseBattery: record?.caseBattery
            )
        }
        .sorted { lhs, rhs in
            if lhs.isAirPods != rhs.isAirPods { return lhs.isAirPods }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        let previousIDs = Set(connectedDevices.map(\.id))
        let refreshedIDs = Set(refreshedDevices.map(\.id))
        if hasCompletedInitialRefresh {
            pendingConnectionIDs.formUnion(refreshedIDs.subtracting(previousIDs))
        }

        if connectedDevices != refreshedDevices {
            connectedDevices = refreshedDevices
        }
        updateDisconnectNotifications(for: devices)
        pendingConnectionIDs.formIntersection(refreshedIDs)

        if Defaults[.showBluetoothBatteryNotifications],
           let candidate = BluetoothBatteryNotificationPolicy.candidate(
                pendingConnectionIDs: pendingConnectionIDs,
                connectedDevices: refreshedDevices
           ) {
            pendingConnectionIDs.remove(candidate.id)
            showTransientDevice(candidate)
        }

        hasCompletedInitialRefresh = true
    }

    @objc private func bluetoothDeviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        if let id = device.addressString ?? device.nameOrAddress {
            pendingConnectionIDs.insert(id)
        }
        refresh()
        scheduleDelayedRefresh()
    }

    @objc private func bluetoothDeviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        if let id = device.addressString ?? device.nameOrAddress {
            pendingConnectionIDs.remove(id)
            disconnectNotifications[id]?.unregister()
            disconnectNotifications[id] = nil
        }
        refresh()
    }

    private func updateDisconnectNotifications(for devices: [IOBluetoothDevice]) {
        let connectedIDs = Set(devices.compactMap { $0.addressString ?? $0.nameOrAddress })

        let staleIDs = disconnectNotifications.keys.filter { !connectedIDs.contains($0) }
        for id in staleIDs {
            disconnectNotifications[id]?.unregister()
            disconnectNotifications[id] = nil
        }

        for device in devices {
            guard let id = device.addressString ?? device.nameOrAddress,
                  disconnectNotifications[id] == nil
            else { continue }
            disconnectNotifications[id] = device.register(
                forDisconnectNotification: self,
                selector: #selector(bluetoothDeviceDisconnected(_:device:))
            )
        }
    }

    private func scheduleDelayedRefresh() {
        delayedRefreshTask?.cancel()
        delayedRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    private func showTransientDevice(_ device: BluetoothDeviceStatus) {
        transientDeviceTask?.cancel()
        withAnimation(AppMotion.status) {
            transientDevice = device
        }
        transientDeviceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(AppMotion.status) {
                self?.transientDevice = nil
            }
        }
    }

    private struct BatteryRecord {
        let name: String
        let battery: Int?
        let leftBattery: Int?
        let rightBattery: Int?
        let caseBattery: Int?
    }

    private func readBatteryRecords() -> [BatteryRecord] {
        var iterator: io_iterator_t = 0
        guard IORegistryCreateIterator(
            kIOMainPortDefault,
            kIOServicePlane,
            IOOptionBits(kIORegistryIterateRecursively),
            &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var records: [BatteryRecord] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let values = properties?.takeRetainedValue() as? [String: Any],
                  let name = stringValue(in: values, keys: ["Product", "ProductName", "DeviceName"]),
                  let record = batteryRecord(name: name, values: values)
            else { continue }
            records.append(record)
        }
        return records
    }

    private func batteryRecord(name: String, values: [String: Any]) -> BatteryRecord? {
        let battery = integerValue(in: values, keys: ["BatteryPercent", "BatteryPercentSingle"])
        let left = integerValue(in: values, keys: ["BatteryPercentLeft", "LeftBattery", "BatteryPercentLeftBud"])
        let right = integerValue(in: values, keys: ["BatteryPercentRight", "RightBattery", "BatteryPercentRightBud"])
        let caseBattery = integerValue(in: values, keys: ["BatteryPercentCase", "CaseBattery"])
        guard battery != nil || left != nil || right != nil || caseBattery != nil else { return nil }
        return BatteryRecord(name: name, battery: battery, leftBattery: left, rightBattery: right, caseBattery: caseBattery)
    }

    private func integerValue(in values: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let number = values[key] as? NSNumber { return number.intValue }
            if let string = values[key] as? String {
                return Int(string.trimmingCharacters(in: CharacterSet(charactersIn: "%")))
            }
        }
        return nil
    }

    private func stringValue(in values: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = values[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func namesLikelyMatch(_ lhs: String, _ rhs: String) -> Bool {
        let normalize: (String) -> String = {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }
        let left = normalize(lhs)
        let right = normalize(rhs)
        return left == right || left.contains(right) || right.contains(left)
    }
}
