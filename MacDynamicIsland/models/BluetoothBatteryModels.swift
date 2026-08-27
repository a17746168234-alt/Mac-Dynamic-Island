import Foundation

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
                "左 \(leftBattery)%",
                "右 \(rightBattery)%"
            ]
            if let caseBattery {
                values.append("盒 \(caseBattery)%")
            }
            return values.joined(separator: " · ")
        }
        if let battery {
            return "\(battery)%"
        }
        return nil
    }
}

enum BluetoothBatteryNotificationPolicy {
    static func candidate(
        pendingConnectionIDs: Set<String>,
        connectedDevices: [BluetoothDeviceStatus]
    ) -> BluetoothDeviceStatus? {
        connectedDevices.first { device in
            pendingConnectionIDs.contains(device.id) && device.batteryDescription != nil
        }
    }
}
