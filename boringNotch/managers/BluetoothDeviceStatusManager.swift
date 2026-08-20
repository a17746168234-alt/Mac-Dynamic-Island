import Foundation
import IOBluetooth
import IOKit

struct BluetoothDeviceStatus: Identifiable, Equatable {
    let id: String
    let name: String
    let battery: Int?
    let leftBattery: Int?
    let rightBattery: Int?
    let caseBattery: Int?

    var isAirPods: Bool {
        name.localizedCaseInsensitiveContains("AirPods")
    }

    var batteryDescription: String? {
        if let leftBattery, let rightBattery {
            var values = [
                String(localized: "Left \(leftBattery)%"),
                String(localized: "Right \(rightBattery)%")
            ]
            if let caseBattery {
                values.append(String(localized: "Case \(caseBattery)%"))
            }
            return values.joined(separator: " · ")
        }
        if let battery {
            return "\(battery)%"
        }
        return nil
    }
}

@MainActor
final class BluetoothDeviceStatusManager: ObservableObject {
    static let shared = BluetoothDeviceStatusManager()

    @Published private(set) var connectedDevices: [BluetoothDeviceStatus] = []
    private var timer: Timer?

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let batteryRecords = readBatteryRecords()
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .filter { $0.isConnected() }

        connectedDevices = devices.map { device in
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
