import Foundation

private enum BluetoothBatteryTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw BluetoothBatteryTestFailure.assertion(message) }
}

@main
struct BluetoothBatteryModelsTests {
    static func main() throws {
        let airPods = BluetoothDeviceStatus(
            id: "airpods",
            name: "AirPods Pro",
            battery: nil,
            leftBattery: 82,
            rightBattery: 76,
            caseBattery: 61
        )
        let keyboardWithoutBattery = BluetoothDeviceStatus(
            id: "keyboard",
            name: "Keyboard",
            battery: nil,
            leftBattery: nil,
            rightBattery: nil,
            caseBattery: nil
        )

        try expect(
            airPods.batteryDescription == "左 82% · 右 76% · 盒 61%",
            "AirPods 电量必须同时显示左耳、右耳和充电盒"
        )
        try expect(
            BluetoothBatteryNotificationPolicy.candidate(
                pendingConnectionIDs: ["keyboard", "airpods"],
                connectedDevices: [keyboardWithoutBattery, airPods]
            ) == airPods,
            "临时提示必须跳过无法读取电量的设备"
        )
        try expect(
            BluetoothBatteryNotificationPolicy.candidate(
                pendingConnectionIDs: ["keyboard"],
                connectedDevices: [keyboardWithoutBattery]
            ) == nil,
            "没有可用电量时不得弹出空提示"
        )

        print("BluetoothBatteryModelsTests: PASS")
    }
}
