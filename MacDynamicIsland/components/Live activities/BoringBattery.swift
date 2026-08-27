import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || Defaults[.showPowerStatusIcons]) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17,
                            height: 17
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

struct BluetoothDeviceBatteryNotificationView: View {
    let device: BluetoothDeviceStatus
    let closedNotchWidth: CGFloat

    private var deviceIcon: String {
        device.isAirPods ? "airpodspro" : "headphones"
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: deviceIcon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("已连接")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 174, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: closedNotchWidth + 10)

            HStack(spacing: 6) {
                Image(systemName: "battery.100")
                    .foregroundStyle(.green)
                Text(device.batteryDescription ?? "电量暂不可用")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 174, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .foregroundStyle(.white)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(AppMotion.press, value: configuration.isPressed)
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var timeToEmpty: Int

    private var batteryStatus: String {
        if maxCapacity > 0, levelBattery >= maxCapacity {
            return String(localized: "Fully Charged")
        }
        return isPluggedIn ? String(localized: "Charged") : String(localized: "Power Disconnected")
    }

    private var powerSource: String {
        isPluggedIn ? String(localized: "Power Adapter") : String(localized: "Battery Power")
    }

    private var estimateTitle: String {
        if !isPluggedIn { return "剩余续航" }
        if Int(levelBattery) >= 100 { return "电池状态" }
        return isCharging || timeToFullCharge > 0 ? "充满时间" : "充电状态"
    }

    private var estimateText: String {
        BatteryChargeEstimate.text(
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            minutesToFullCharge: timeToFullCharge,
            minutesToEmpty: timeToEmpty,
            levelPercent: Int(levelBattery)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Battery")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(Int(levelBattery))%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Text("Power:")
                Text(powerSource)
                    .foregroundStyle(Color.white.opacity(0.58))
            }
            .font(.callout)

            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 12) {
                Image(systemName: isPluggedIn ? "bolt.fill" : "clock.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isPluggedIn ? .green : Color.white.opacity(0.68))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(estimateTitle)
                        .font(.body.weight(.medium))
                    Text(estimateText)
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 248)
        .foregroundStyle(Color.white.opacity(0.92))
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
    }

}

/// A view that displays the battery status and allows interaction to show detailed information.
struct BoringBatteryView: View {
    
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    var timeToEmpty: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        Button(action: {
            BatteryStatusViewModel.shared.refreshBatteryInfo()
            withAnimation(AppMotion.selection) {
                showPopupMenu.toggle()
            }
        }) {
            HStack(spacing: 4) {
                if Defaults[.showBatteryPercentage] {
                    Text("\(Int32(levelBattery))%")
                        .font(.callout)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(
                            minWidth: BoringHeaderLayout.batteryPercentageMinimumWidth,
                            // Keep 5%/52% beside the battery icon. The unused
                            // leading room is reserved for the third digit in 100%.
                            alignment: .trailing
                        )
                        .foregroundStyle(.white)
                }
                BatteryView(
                    levelBattery: levelBattery,
                    isPluggedIn: isPluggedIn,
                    isCharging: isCharging,
                    isInLowPowerMode: isInLowPowerMode,
                    batteryWidth: batteryWidth,
                    isForNotification: isForNotification
                )
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .top) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                timeToEmpty: timeToEmpty
            )
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) {
            vm.isBatteryPopoverActive = showPopupMenu
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(AppMotion.selection) { showPopupMenu = false } }
        }
    }
}

#Preview {
    BoringBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        timeToEmpty: 0,
        isForNotification: false
    ).frame(width: 200, height: 200)
}
