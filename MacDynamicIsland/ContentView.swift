//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?
    @State private var presentedView: NotchViews = .home
    @State private var viewTransitionTask: Task<Void, Never>?
    @State private var settingsHoverMonitorTask: Task<Void, Never>?
    @State private var settingsPointerWasInside = false

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    private let extendedHoverPadding: CGFloat = 30

    private let settingsMountDelay: Duration = .milliseconds(180)
    private let settingsUnmountDelay: Duration = .milliseconds(80)

    private var motionProfile: NotchMotionProfile {
        NotchMotionPolicy.profile(
            isLowPowerMode: batteryModel.isInLowPowerMode,
            reduceMotion: accessibilityReduceMotion
        )
    }

    private var animationSpring: Animation {
        notchAnimation(.gesture, profile: motionProfile)
    }

    private var resizeAnimation: Animation {
        notchAnimation(.resizing, profile: motionProfile)
    }

    private var settingsContentAnimation: Animation {
        notchAnimation(.content, profile: motionProfile)
    }

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var shellShapeHorizontalInset: CGFloat {
        if vm.notchState == .open {
            return NotchShellLayout.shapeHorizontalInset(
                cornerRadiusScaling: Defaults[.cornerRadiusScaling]
            )
        }
        return cornerRadiusInsets.closed.bottom
    }

    private var shellAdditionalHorizontalInset: CGFloat {
        vm.notchState == .open ? NotchShellLayout.additionalHorizontalInset : 0
    }

    private var notchContentHorizontalInset: CGFloat {
        shellShapeHorizontalInset + shellAdditionalHorizontalInset
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(.horizontal, shellShapeHorizontalInset)
                    .padding([.horizontal, .bottom], shellAdditionalHorizontalInset)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(
                        width: vm.presentationPhase != .closed ? vm.notchSize.width : nil,
                        height: vm.presentationPhase != .closed ? vm.notchSize.height : nil,
                        alignment: .top
                    )
                    // The lightweight outer shell owns the closing spring. Large
                    // launcher/settings views can unmount without being relaid out
                    // at every intermediate spring size.
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .conditionalModifier(true) { view in
                        return view
                            .animation(animationSpring, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures] && !coordinator.currentView.usesLargeNotch) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures] && !coordinator.currentView.usesLargeNotch) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        scheduleAutomaticClose()
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation(AppMotion.status) {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.hasActivePopover) { _, isActive in
                        if isActive {
                            hoverTask?.cancel()
                        } else {
                            scheduleAutomaticClose()
                        }
                    }
                    .onChange(of: vm.interactionLocks) { _, locks in
                        if locks.isEmpty {
                            scheduleAutomaticClose()
                        } else {
                            hoverTask?.cancel()
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            coordinator.currentView = .settings
                            if vm.notchState == .closed { vm.open() }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(animationSpring, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onAppear {
            if coordinator.currentView == .settings {
                beginSettingsHoverMonitoring()
            }
        }
        .onDisappear {
            endSettingsHoverMonitoring()
        }
        .onChange(of: coordinator.currentView) { oldView, newView in
            viewTransitionTask?.cancel()
            if newView == .settings {
                beginSettingsHoverMonitoring()
                withAnimation(resizeAnimation) { vm.updateSizeForCurrentView() }
                if oldView.usesLargeNotch {
                    withAnimation(AppMotion.pageEnter) { presentedView = .settings }
                } else {
                    viewTransitionTask = Task {
                        try? await Task.sleep(for: settingsMountDelay)
                        guard !Task.isCancelled else { return }
                        await MainActor.run { withAnimation(AppMotion.pageEnter) { presentedView = .settings } }
                    }
                }
            } else if oldView == .settings || presentedView == .settings {
                endSettingsHoverMonitoring()
                withAnimation(AppMotion.pageExit) { presentedView = newView }
                if newView.usesLargeNotch {
                    vm.updateSizeForCurrentView()
                } else {
                    viewTransitionTask = Task {
                        try? await Task.sleep(for: settingsUnmountDelay)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(resizeAnimation) { vm.updateSizeForCurrentView() }
                        }
                    }
                }
            } else {
                withAnimation(AppMotion.pageEnter) {
                    presentedView = newView
                }
                withAnimation(resizeAnimation) {
                    vm.updateSizeForCurrentView()
                }
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if NotchInteractionPolicy.shouldCloseAfterDrop(
                    isSharing: SharingStateManager.shared.preventNotchClose,
                    activeLocks: vm.interactionLocks
                ) {
                    scheduleAutomaticClose(delayMilliseconds: 0)
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    maxCapacity: batteryModel.maxCapacity,
                                    timeToFullCharge: batteryModel.timeToFullCharge,
                                    timeToEmpty: batteryModel.timeToEmpty,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 84, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(
                                   width: max(
                                       0,
                                       vm.notchSize.width - (2 * notchContentHorizontalInset)
                                   ),
                                   height: max(24, vm.effectiveClosedNotchHeight),
                                   alignment: .topTrailing
                               )
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch presentedView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    case .tools:
                        UtilityDashboardView()
                    case .launcher:
                        ApplicationLauncherView()
                    case .settings:
                        SettingsView()
                    }
                }
                .id(presentedView)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.99, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.995, anchor: .top))
                ))
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures(
                    animationsEnabled: !batteryModel.isInLowPowerMode && !accessibilityReduceMotion
                )
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(
                                isPlaying: musicManager.isPlaying
                                    && !batteryModel.isInLowPowerMode
                                    && !accessibilityReduceMotion
                            )
                                .frame(width: 16, height: 12)
                        }
                } else {
                    if batteryModel.isInLowPowerMode || accessibilityReduceMotion {
                        Image(systemName: "waveform")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LottieAnimationContainer()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data, .image], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        hoverTask?.cancel()
        vm.open()
    }

    // MARK: - Hover Management

    private func beginSettingsHoverMonitoring() {
        settingsHoverMonitorTask?.cancel()
        settingsPointerWasInside = false
        vm.setInteractionLock(.settingsInteraction, active: true)

        settingsHoverMonitorTask = Task { @MainActor in
            while !Task.isCancelled,
                  coordinator.currentView == .settings,
                  vm.notchState == .open || vm.presentationPhase == .opening
            {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }

                let pointerInsideSettings = vm.isMouseHovering(
                    gracePadding: extendedHoverPadding
                )
                if pointerInsideSettings {
                    settingsPointerWasInside = true
                    continue
                }

                // Switching to Settings can briefly report an outside pointer
                // while SwiftUI replaces and resizes the large view. Do not let
                // that transient event close the island before the pointer has
                // actually been observed inside the Settings surface once.
                guard settingsPointerWasInside else { continue }

                vm.setInteractionLock(.settingsInteraction, active: false)
                withAnimation(animationSpring) {
                    isHovering = false
                }
                if vm.canAutomaticallyClose(
                    isHovering: false,
                    pointerInsideGraceArea: false
                ) {
                    vm.close()
                }
                settingsHoverMonitorTask = nil
                return
            }
            settingsHoverMonitorTask = nil
        }
    }

    private func endSettingsHoverMonitoring() {
        settingsHoverMonitorTask?.cancel()
        settingsHoverMonitorTask = nil
        settingsPointerWasInside = false
        vm.setInteractionLock(.settingsInteraction, active: false)
    }

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            if coordinator.currentView == .settings {
                settingsPointerWasInside = true
                vm.setInteractionLock(.settingsInteraction, active: true)
            }
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            scheduleAutomaticClose()
        }
    }

    private func scheduleAutomaticClose(
        delayMilliseconds: Int = NotchInteractionPolicy.autoCloseDelayMilliseconds
    ) {
        hoverTask?.cancel()
        guard vm.notchState == .open else { return }

        hoverTask = Task {
            try? await Task.sleep(for: .milliseconds(Int64(delayMilliseconds)))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                let pointerInsideGraceArea = self.vm.isMouseHovering(
                    gracePadding: self.extendedHoverPadding
                )
                if self.coordinator.currentView == .settings {
                    if pointerInsideGraceArea {
                        self.settingsPointerWasInside = true
                    } else if !self.settingsPointerWasInside {
                        self.vm.setInteractionLock(.settingsInteraction, active: true)
                        return
                    }
                    self.vm.setInteractionLock(
                        .settingsInteraction,
                        active: pointerInsideGraceArea
                    )
                }
                if pointerInsideGraceArea {
                    withAnimation(self.animationSpring) {
                        self.isHovering = true
                    }
                    self.scheduleAutomaticClose(
                        delayMilliseconds: NotchInteractionPolicy.graceAreaRecheckDelayMilliseconds
                    )
                    return
                }

                withAnimation(self.animationSpring) {
                    self.isHovering = false
                }

                if self.vm.canAutomaticallyClose(
                    isHovering: false,
                    pointerInsideGraceArea: false
                ) {
                    self.vm.close()
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        let gestureEnded = phase == .ended || phase == .cancelled
        vm.setInteractionLock(.gesture, active: !gestureEnded)
        guard vm.notchState == .closed else {
            if gestureEnded { vm.setInteractionLock(.gesture, active: false) }
            return
        }

        if gestureEnded {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            vm.setInteractionLock(.gesture, active: false)
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        let gestureEnded = phase == .ended || phase == .cancelled
        vm.setInteractionLock(.gesture, active: !gestureEnded)
        guard vm.notchState == .open,
              !coordinator.currentView.usesLargeNotch,
              !vm.isHoveringCalendar
        else {
            if gestureEnded { vm.setInteractionLock(.gesture, active: false) }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if gestureEnded {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.setInteractionLock(.gesture, active: false)
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
