//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed
    @Published private(set) var presentationPhase: NotchPresentationPhase = .closed
    @Published private(set) var interactionLocks: Set<NotchInteractionLock> = []

    @Published var dragDetectorTargeting: Bool = false
    @Published var generalDropTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    @Published private(set) var isHomeModuleReordering: Bool = false
    var cancellables: Set<AnyCancellable> = []

    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isWeatherPopoverActive: Bool = false

    var hasActivePopover: Bool {
        isBatteryPopoverActive || isWeatherPopoverActive
    }

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    private var presentationCompletionTask: Task<Void, Never>?
    private var fileDragCompletionTask: Task<Void, Never>?

    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false

    deinit {
        destroy()
    }

    func destroy() {
        presentationCompletionTask?.cancel()
        presentationCompletionTask = nil
        fileDragCompletionTask?.cancel()
        fileDragCompletionTask = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()

        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        Publishers.CombineLatest3($dropZoneTargeting, $dragDetectorTargeting, $generalDropTargeting)
            .map { shelf, drag, general in
                shelf || drag || general
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isTargeting in
                self?.anyDropZoneTargeting = isTargeting
                self?.setInteractionLock(.dropTarget, active: isTargeting)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest($isBatteryPopoverActive, $isWeatherPopoverActive)
            .map { battery, weather in battery || weather }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isActive in
                self?.setInteractionLock(.popover, active: isActive)
            }
            .store(in: &cancellables)

        setupDetectorObserver()

        Publishers.CombineLatest3(
            Defaults.publisher(.showCalendar).map(\.newValue),
            Defaults.publisher(.showDailyTodo).map(\.newValue),
            Defaults.publisher(.showWeather).map(\.newValue)
        )
        .map { _, _, _ in () }
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refreshHomeLayoutIfNeeded() }
        .store(in: &cancellables)

        Defaults.publisher(.homeModuleOrder)
            .map(\.newValue)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHomeLayoutIfNeeded() }
            .store(in: &cancellables)
    }

    private func refreshHomeLayoutIfNeeded() {
        guard notchState == .open,
              coordinator.currentView == .home
        else { return }
        withAnimation(notchAnimation(.resizing)) {
            updateSizeForCurrentView()
        }
    }

    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(notchAnimation(.content)) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = String(localized: "Camera Access Required")
                alert.informativeText = String(localized: "Please allow camera access in System Settings.")
                alert.addButton(withTitle: String(localized: "Open Settings"))
                alert.addButton(withTitle: String(localized: "Cancel"))

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }

    func isMouseHovering(
        position: NSPoint = NSEvent.mouseLocation,
        gracePadding: CGFloat = 0
    ) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {

            let baseY = frame.maxY - notchSize.height - gracePadding
            let baseX = frame.midX - notchSize.width / 2 - gracePadding

            return position.y >= baseY
                && position.y <= frame.maxY
                && position.x >= baseX
                && position.x <= baseX + notchSize.width + (gracePadding * 2)
        }

        return false
    }

    func open() {
        guard NotchInteractionPolicy.canOpen(isFirstLaunch: coordinator.firstLaunch) else {
            close()
            return
        }
        guard notchState == .closed || presentationPhase == .closing else { return }

        presentationCompletionTask?.cancel()
        presentationPhase = .opening
        let profile = currentNotchMotionProfile()
        withAnimation(notchAnimation(.opening, profile: profile)) {
            self.notchSize = coordinator.currentView.usesLargeNotch
                ? launcherNotchSize(screenUUID: screenUUID)
                : currentOpenSize()
            self.notchState = .open
        }
        schedulePresentationCompletion(
            expectedPhase: .opening,
            finalPhase: .open,
            duration: NotchMotionPolicy.settleDuration(for: .opening, profile: profile)
        )

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func beginHomeModuleReordering() {
        isHomeModuleReordering = true
        setInteractionLock(.homeModuleReordering, active: true)
    }

    func endHomeModuleReordering() {
        isHomeModuleReordering = false
        setInteractionLock(.homeModuleReordering, active: false)
    }

    func setInteractionLock(_ lock: NotchInteractionLock, active: Bool) {
        var updatedLocks = interactionLocks
        if active {
            updatedLocks.insert(lock)
        } else {
            updatedLocks.remove(lock)
        }
        if updatedLocks != interactionLocks {
            interactionLocks = updatedLocks
        }
    }

    func canAutomaticallyClose(isHovering: Bool, pointerInsideGraceArea: Bool = false) -> Bool {
        NotchInteractionPolicy.shouldCloseNotch(
            isOpen: notchState == .open,
            isHovering: isHovering,
            activeLocks: interactionLocks,
            isSharing: SharingStateManager.shared.preventNotchClose,
            pointerInsideGraceArea: pointerInsideGraceArea
        )
    }

    func closeAutomatically(
        at position: NSPoint = NSEvent.mouseLocation,
        gracePadding: CGFloat = 30
    ) {
        let pointerInsideGraceArea = isMouseHovering(
            position: position,
            gracePadding: gracePadding
        )
        guard canAutomaticallyClose(
            isHovering: false,
            pointerInsideGraceArea: pointerInsideGraceArea
        ) else { return }
        close()
    }

    /// AppKit drag sessions can suppress SwiftUI's hover-exit callback. Clear any
    /// stale drop-target state and decide whether to close from the actual drag-end
    /// position instead of waiting for another hover event that may never arrive.
    func finishFileDrag(at position: NSPoint) {
        clearDropInteractionState()
        closeAutomatically(at: position)

        // Cross-application dragging runs a nested AppKit event loop. A queued
        // SwiftUI drop-target update can briefly restore the lock after the source
        // receives its end callback, so re-check once that event loop has unwound.
        fileDragCompletionTask?.cancel()
        fileDragCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            self.clearDropInteractionState()
            self.closeAutomatically()
            self.fileDragCompletionTask = nil
        }
    }

    private func clearDropInteractionState() {
        dropZoneTargeting = false
        dragDetectorTargeting = false
        generalDropTargeting = false
        dropEvent = false
        setInteractionLock(.dropTarget, active: false)
    }

    func updateSizeForCurrentView() {
        guard notchState == .open else { return }
        notchSize = coordinator.currentView.usesLargeNotch
            ? launcherNotchSize(screenUUID: screenUUID)
            : currentOpenSize()
    }

    /// 根据功能开关计算展开尺寸:
    /// 暂存器使用独立高度，工具等非主页视图使用标准尺寸(640);
    /// 主页且关闭任意一项时收窄到紧凑尺寸:宽度刚好容纳
    /// 左图标组 + 空隙 + 刘海 + 空隙 + 右图标组(播放器随此宽度联动)
    private func currentOpenSize() -> CGSize {
        // 两行文件加顶部工具栏需要更高的固定空间，避免工具栏被压缩裁切。
        if coordinator.currentView == .shelf {
            return shelfNotchSize
        }
        if coordinator.currentView == .tools {
            return openNotchSize
        }
        let notchWidth = getClosedNotchSize(screenUUID: self.screenUUID).width
        let layout = NotchHomeLayout(
            closedNotchWidth: notchWidth,
            showTodo: Defaults[.showDailyTodo],
            showCalendar: Defaults[.showCalendar],
            showWeather: Defaults[.showWeather],
            availableScreenWidth: getVisibleScreenFrame(screenUUID)?.width,
            contentHorizontalPadding: NotchShellLayout.contentHorizontalPadding(
                cornerRadiusScaling: Defaults[.cornerRadiusScaling]
            )
        )
        return CGSize(width: layout.openWidth, height: 210)
    }

    func close() {
        guard notchState == .open || presentationPhase == .opening else { return }
        // Do not close while a detached popover, drag, gesture, share picker, or sharing service is active.
        if !interactionLocks.isEmpty || SharingStateManager.shared.preventNotchClose {
            return
        }
        presentationCompletionTask?.cancel()
        presentationPhase = .closing
        let profile = currentNotchMotionProfile()
        withAnimation(notchAnimation(.closing, profile: profile)) {
            self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
            self.closedNotchSize = self.notchSize
            self.notchState = .closed
        }
        schedulePresentationCompletion(
            expectedPhase: .closing,
            finalPhase: .closed,
            duration: NotchMotionPolicy.settleDuration(for: .closing, profile: profile)
        )
        self.isBatteryPopoverActive = false
        self.isWeatherPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false
    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(notchAnimation(.content)) {
                coordinator.helloAnimationRunning = false
            }
            close()
        }
    }

    private func schedulePresentationCompletion(
        expectedPhase: NotchPresentationPhase,
        finalPhase: NotchPresentationPhase,
        duration: TimeInterval
    ) {
        presentationCompletionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled,
                  let self,
                  self.presentationPhase == expectedPhase
            else { return }
            self.presentationPhase = finalPhase
            if finalPhase == .closed {
                self.resetCurrentViewAfterClose()
                NotificationCenter.default.post(name: .notchDidClose, object: self)
            }
            self.presentationCompletionTask = nil
        }
    }

    private func resetCurrentViewAfterClose() {
        // Reset only after the closing spring finishes so large pages are not
        // replaced by the home layout during the visible contraction.
        if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }
}
