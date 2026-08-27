//
//  MacDynamicIslandApp.swift
//  MacDynamicIsland
//
//  Created by Harsh Vardhan  Goswami  on 02/08/24.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@main
struct MacDynamicIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    init() {
        Defaults[.showMirror] = false
    }

    var body: some Scene {
        MenuBarExtra("Mac灵动岛", systemImage: "sparkle", isInserted: $showMenuBarIcon) {
            Button("Open Tools") {
                appDelegate.openTools()
            }
            Button("Settings") {
                appDelegate.openSettings()
            }
            .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
            Divider()
            Button("重新启动 Mac灵动岛") {
                ApplicationRelauncher.restart()
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }
}

/// AppKit owns the cross-application drag session for the transparent notch
/// panel. SwiftUI drop destinations remain in place for their visual state and
/// for in-app drags, while this root receiver provides a reliable Finder/Photos
/// fallback without turning the rest of the transparent 1200x760 window into a
/// drop target.
@MainActor
private final class NotchDropHostingView<Content: View>: NSHostingView<Content> {
    private enum DropTarget {
        case shelf
        case quickShare
    }

    private weak var viewModel: BoringViewModel?
    private let coordinator = BoringViewCoordinator.shared
    private var activeDropTarget: DropTarget?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerNativeDropTypes()
    }

    convenience init(rootView: Content, viewModel: BoringViewModel) {
        self.init(rootView: rootView)
        self.viewModel = viewModel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // SwiftUI updates its own drop destinations while mounting the root
        // view. Register again after attachment so the native fallback remains
        // the outermost destination.
        registerNativeDropTypes()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return updateDragTarget(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDragTarget(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        clearDropTargeting()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        activeDropTarget != nil && !itemProviders(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let providers = itemProviders(from: sender.draggingPasteboard)
        guard let viewModel,
              let target = activeDropTarget ?? dropTarget(at: convert(sender.draggingLocation, from: nil)),
              !ShelfSelectionModel.shared.isDragging,
              !providers.isEmpty
        else {
            clearDropTargeting()
            return false
        }

        viewModel.dropEvent = true

        switch target {
        case .shelf:
            ShelfStateViewModel.shared.load(providers)
        case .quickShare:
            let service = QuickShareService.shared
            let configuredID = Defaults[.quickShareProvider]
            let provider = service.availableProviders.first(where: { $0.id == configuredID })
                ?? service.availableProviders.first
                ?? QuickShareProvider(
                    id: "System Share Menu",
                    imageData: nil,
                    supportsRawText: true
                )
            Task {
                await service.shareDroppedFiles(providers, using: provider, from: self)
            }
        }

        clearDropTargeting()
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        clearDropTargeting()
    }

    private func updateDragTarget(for sender: NSDraggingInfo) -> NSDragOperation {
        guard Defaults[.boringShelf],
              ShelfDropTypePolicy.supports(
                sender.draggingPasteboard.types?.map(\.rawValue) ?? []
              ),
              let viewModel
        else {
            clearDropTargeting()
            return []
        }

        let point = convert(sender.draggingLocation, from: nil)
        guard shelfActivationRect.contains(point) else {
            clearDropTargeting()
            return []
        }

        if viewModel.notchState == .closed || coordinator.currentView != .shelf {
            coordinator.currentView = .shelf
            viewModel.open()
            viewModel.updateSizeForCurrentView()
        }

        let target = dropTarget(at: point) ?? .shelf
        activeDropTarget = target
        viewModel.dragDetectorTargeting = target == .shelf
        viewModel.dropZoneTargeting = target == .quickShare
        return .copy
    }

    private var shelfActivationRect: NSRect {
        NSRect(
            x: (bounds.width - shelfNotchSize.width) / 2,
            y: bounds.height - shelfNotchSize.height,
            width: shelfNotchSize.width,
            height: shelfNotchSize.height
        )
    }

    private func dropTarget(at point: NSPoint) -> DropTarget? {
        let rect = shelfActivationRect
        guard rect.contains(point) else { return nil }

        // The first 170 points contain the 142-point quick-share card and its
        // spacing. Keep the header itself routed to the shelf so a drop near the
        // top controls never starts sharing unexpectedly.
        let isBelowHeader = point.y < rect.maxY - 42
        if isBelowHeader && point.x < rect.minX + 170 {
            return .quickShare
        }
        return .shelf
    }

    private func clearDropTargeting() {
        activeDropTarget = nil
        viewModel?.dragDetectorTargeting = false
        viewModel?.dropZoneTargeting = false
    }

    private func registerNativeDropTypes() {
        let promisedFileTypes = NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }
        registerForDraggedTypes(
            [.fileURL, .URL, .string, .png, .tiff] + promisedFileTypes
        )
    }

    private func itemProviders(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: fileURLReadingOptions
        )?.compactMap { ($0 as? URL)?.standardizedFileURL } ?? []

        if !fileURLs.isEmpty {
            return fileURLs.compactMap(NSItemProvider.init(contentsOf:))
        }

        if let rawURL = pasteboard.string(forType: .URL),
           let url = URL(string: rawURL),
           let provider = NSItemProvider(contentsOf: url) {
            return [provider]
        }

        if let image = NSImage(pasteboard: pasteboard),
           let data = image.tiffRepresentation {
            return [NSItemProvider(item: data as NSData, typeIdentifier: UTType.tiff.identifier)]
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return [NSItemProvider(object: text as NSString)]
        }

        return []
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [String: NSWindow] = [:] // UUID -> NSWindow
    var viewModels: [String: BoringViewModel] = [:] // UUID -> BoringViewModel
    var window: NSWindow?
    let vm: BoringViewModel = .init()
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    var quickShareService = QuickShareService.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    var closeNotchTask: Task<Void, Never>?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var screenLockedObserver: Any?
    private var screenUnlockedObserver: Any?
    private var isScreenLocked: Bool = false
    private var windowScreenDidChangeObserver: Any?
    private var dragDetectors: [String: DragDetector] = [:] // UUID -> DragDetector
    private var pendingSettingsWindowRefresh = false
    private var pendingSettingsDisplayModeRebuild = false
    private var pendingSettingsAutomaticDisplayRefresh = false

    @MainActor
    func openTools() {
        openNotch(view: .tools)
    }

    @MainActor
    func openSettings() {
        openNotch(view: .settings)
    }

    @MainActor
    private func openNotch(view: NotchViews) {
        coordinator.currentView = view
        let mouseLocation = NSEvent.mouseLocation

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
                if let uuid = screen.displayUUID, let viewModel = viewModels[uuid] {
                    viewModel.open()
                    return
                }
            }
        }
        vm.open()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        Task { @MainActor [weak self] in
            self?.openNotch(view: .home)
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        if let observer = screenLockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenLockedObserver = nil
        }
        if let observer = screenUnlockedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            screenUnlockedObserver = nil
        }
        MusicManager.shared.destroy()
        cleanupDragDetectors()
        cleanupWindows()
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }

    @MainActor
    func onScreenLocked(_ notification: Notification) {
        isScreenLocked = true
        if !Defaults[.showOnLockScreen] {
            cleanupWindows()
        } else {
            enableSkyLightOnAllWindows()
        }
    }

    @MainActor
    func onScreenUnlocked(_ notification: Notification) {
        isScreenLocked = false
        if !Defaults[.showOnLockScreen] {
            adjustWindowPosition(changeAlpha: true)
        } else {
            disableSkyLightOnAllWindows()
        }
    }
    
    @MainActor
    private func enableSkyLightOnAllWindows() {
        if Defaults[.showOnAllDisplays] {
            windows.values.forEach { window in
                if let skyWindow = window as? BoringNotchSkyLightWindow {
                    skyWindow.enableSkyLight()
                }
            }
        } else {
            if let skyWindow = window as? BoringNotchSkyLightWindow {
                skyWindow.enableSkyLight()
            }
        }
    }
    
    @MainActor
    private func disableSkyLightOnAllWindows() {
        // Delay disabling SkyLight to avoid flicker during unlock transition
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            await MainActor.run {
                if Defaults[.showOnAllDisplays] {
                    self.windows.values.forEach { window in
                        if let skyWindow = window as? BoringNotchSkyLightWindow {
                            skyWindow.disableSkyLight()
                        }
                    }
                } else {
                    if let skyWindow = self.window as? BoringNotchSkyLightWindow {
                        skyWindow.disableSkyLight()
                    }
                }
            }
        }
    }

    private func cleanupWindows(shouldInvert: Bool = false) {
        let shouldCleanupMulti = shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays]
        
        if shouldCleanupMulti {
            windows.values.forEach { window in
                window.close()
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            window.close()
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            if let obs = windowScreenDidChangeObserver {
                NotificationCenter.default.removeObserver(obs)
                windowScreenDidChangeObserver = nil
            }
            self.window = nil
        }
    }

    private func cleanupDragDetectors() {
        dragDetectors.values.forEach { detector in
            detector.stopMonitoring()
        }
        dragDetectors.removeAll()
    }

    private func setupDragDetectors() {
        cleanupDragDetectors()

        guard Defaults[.expandedDragDetection] else { return }

        if Defaults[.showOnAllDisplays] {
            for screen in NSScreen.screens {
                setupDragDetectorForScreen(screen)
            }
        } else {
            let preferredScreen: NSScreen? = window?.screen
                ?? NSScreen.screen(withUUID: coordinator.selectedScreenUUID)
                ?? NSScreen.main

            if let screen = preferredScreen {
                setupDragDetectorForScreen(screen)
            }
        }
    }

    private func setupDragDetectorForScreen(_ screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        let screenFrame = screen.frame
        let notchHeight = openNotchSize.height
        let notchWidth = openNotchSize.width
        
        // Create notch region at the top-center of the screen where an open notch would occupy
        let notchRegion = CGRect(
            x: screenFrame.midX - notchWidth / 2,
            y: screenFrame.maxY - notchHeight,
            width: notchWidth,
            height: notchHeight
        )
        
        let detector = DragDetector(notchRegion: notchRegion)
        
        detector.onDragEntersNotchRegion = { [weak self] in
            Task { @MainActor in
                self?.handleDragEntersNotchRegion(onScreen: screen)
            }
        }

        detector.onDragEnded = { [weak self] screenPoint in
            Task { @MainActor in
                self?.handleFileDragEnded(onScreen: screen, at: screenPoint)
            }
        }
        
        dragDetectors[uuid] = detector
        detector.startMonitoring()
    }

    private func handleDragEntersNotchRegion(onScreen screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        
        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.open()
            coordinator.currentView = .shelf
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen, screen == windowScreen {
            vm.open()
            coordinator.currentView = .shelf
        }
    }

    private func handleFileDragEnded(onScreen screen: NSScreen, at screenPoint: NSPoint) {
        guard let uuid = screen.displayUUID else { return }

        if Defaults[.showOnAllDisplays], let viewModel = viewModels[uuid] {
            viewModel.finishFileDrag(at: screenPoint)
        } else if !Defaults[.showOnAllDisplays], let windowScreen = window?.screen,
                  screen == windowScreen {
            vm.finishFileDrag(at: screenPoint)
        }
    }

    private func createBoringNotchWindow(for screen: NSScreen, with viewModel: BoringViewModel) -> NSWindow {
        let rect = NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height)
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]
        
        let window = BoringNotchSkyLightWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
        
        // Enable SkyLight only when screen is locked
        if isScreenLocked {
            window.enableSkyLight()
        } else {
            window.disableSkyLight()
        }

        window.contentView = NotchDropHostingView(
            rootView: ContentView()
                .environmentObject(viewModel),
            viewModel: viewModel
        )

        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)

        // Observe when the window's screen changes so we can update drag detectors
        windowScreenDidChangeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setupDragDetectors()
                }
        }
        return window
    }

    @MainActor
    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false) {
        if changeAlpha {
            window.alphaValue = 0
        }

        let screenFrame = screen.frame
        window.setFrameOrigin(
            NSPoint(
                x: screenFrame.origin.x + (screenFrame.width / 2) - window.frame.width / 2,
                y: screenFrame.origin.y + screenFrame.height - window.frame.height
            ))
        window.alphaValue = 1
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.deferWindowChangesWhileEditingSettings() {
                    self.pendingSettingsWindowRefresh = true
                    return
                }
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.deferWindowChangesWhileEditingSettings() {
                    self.pendingSettingsWindowRefresh = true
                    return
                }
                self.adjustWindowPosition()
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.deferWindowChangesWhileEditingSettings() {
                    self.pendingSettingsAutomaticDisplayRefresh = true
                    return
                }
                guard let window = self.window else { return }
                window.alphaValue = self.coordinator.selectedScreenUUID == self.coordinator.preferredScreenUUID ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.deferWindowChangesWhileEditingSettings() {
                    self.pendingSettingsDisplayModeRebuild = true
                    return
                }
                self.cleanupWindows(shouldInvert: true)
                self.adjustWindowPosition(changeAlpha: true)
                self.setupDragDetectors()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .notchDidClose, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyPendingSettingsWindowChanges()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.expandedDragDetectionChanged, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.setupDragDetectors()
            }
        }

        // Use closure-based observers for DistributedNotificationCenter and keep tokens for removal
        screenLockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenLocked(notification)
                }
        }

        screenUnlockedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    self?.onScreenUnlocked(notification)
                }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            if Defaults[.sneakPeekStyles] == .inline {
                let newStatus = !self.coordinator.expandingView.show
                self.coordinator.toggleExpandingView(status: newStatus, type: .music)
            } else {
                self.coordinator.toggleSneakPeek(
                    status: !self.coordinator.sneakPeek.show,
                    type: .music,
                    duration: 3.0
                )
            }
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            Task { [weak self] in
                guard let self = self else { return }

                let mouseLocation = NSEvent.mouseLocation

                var viewModel = self.vm

                if Defaults[.showOnAllDisplays] {
                    for screen in NSScreen.screens {
                        if screen.frame.contains(mouseLocation) {
                            if let uuid = screen.displayUUID, let screenViewModel = self.viewModels[uuid] {
                                viewModel = screenViewModel
                                break
                            }
                        }
                    }
                }

                self.closeNotchTask?.cancel()
                self.closeNotchTask = nil

                switch viewModel.notchState {
                case .closed:
                    await MainActor.run {
                        viewModel.open()
                    }

                    let task = Task { [weak viewModel] in
                        do {
                            try await Task.sleep(for: .seconds(3))
                            await MainActor.run {
                                viewModel?.closeAutomatically()
                            }
                        } catch { }
                    }
                    self.closeNotchTask = task
                case .open:
                    await MainActor.run {
                        viewModel.close()
                    }
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .clipboardHistoryPanel) { [weak self] in
            Task { @MainActor in
                self?.openTools()
            }
        }

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createBoringNotchWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }

        setupDragDetectors()

        if coordinator.firstLaunch {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        } else if MusicManager.shared.isNowPlayingDeprecated
            && Defaults[.mediaController] == .nowPlaying
        {
            DispatchQueue.main.async {
                self.showOnboardingWindow(step: .musicPermission)
            }
        }

        previousScreens = NSScreen.screens
    }

    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "boring", fileExtension: "m4a")
    }

    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }

    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.compactMap { $0.displayUUID })
                != Set(previousScreens?.compactMap { $0.displayUUID } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens

        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
                self?.setupDragDetectors()
            }
        }
    }

    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreenUUIDs = Set(NSScreen.screens.compactMap { $0.displayUUID })

            // Remove windows for screens that no longer exist
            for uuid in windows.keys where !currentScreenUUIDs.contains(uuid) {
                if let window = windows[uuid] {
                    window.close()
                    NotchSpaceManager.shared.notchSpace.windows.remove(window)
                    windows.removeValue(forKey: uuid)
                    viewModels.removeValue(forKey: uuid)
                }
            }

            // Create or update windows for all screens
            for screen in NSScreen.screens {
                guard let uuid = screen.displayUUID else { continue }
                
                if windows[uuid] == nil {
                    let viewModel = BoringViewModel(screenUUID: uuid)
                    let window = createBoringNotchWindow(for: screen, with: viewModel)

                    windows[uuid] = window
                    viewModels[uuid] = viewModel
                }

                if let window = windows[uuid], let viewModel = viewModels[uuid] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)

                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screen(withUUID: coordinator.preferredScreenUUID ?? "") {
                coordinator.selectedScreenUUID = coordinator.preferredScreenUUID ?? ""
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main,
                      let mainUUID = mainScreen.displayUUID {
                coordinator.selectedScreenUUID = mainUUID
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }

            vm.screenUUID = selectedScreen.displayUUID
            // Settings are persisted immediately, but an expanded settings panel
            // must keep its current geometry until the pointer actually leaves.
            // The new closed/open sizes are picked up naturally by close()/open().
            if vm.notchState == .closed {
                vm.notchSize = getClosedNotchSize(screenUUID: selectedScreen.displayUUID)
                vm.closedNotchSize = vm.notchSize
            }

            if window == nil {
                window = createBoringNotchWindow(for: selectedScreen, with: vm)
            }

            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }
    }

    @MainActor
    private func deferWindowChangesWhileEditingSettings() -> Bool {
        guard coordinator.currentView == .settings else { return false }
        if vm.notchState == .open || vm.presentationPhase == .opening {
            return true
        }
        return viewModels.values.contains {
            $0.notchState == .open || $0.presentationPhase == .opening
        }
    }

    @MainActor
    private func applyPendingSettingsWindowChanges() {
        guard !deferWindowChangesWhileEditingSettings() else { return }

        if pendingSettingsDisplayModeRebuild {
            pendingSettingsDisplayModeRebuild = false
            pendingSettingsWindowRefresh = false
            pendingSettingsAutomaticDisplayRefresh = false
            cleanupWindows(shouldInvert: true)
            adjustWindowPosition(changeAlpha: true)
            setupDragDetectors()
            return
        }

        if pendingSettingsWindowRefresh {
            pendingSettingsWindowRefresh = false
            adjustWindowPosition(changeAlpha: true)
            setupDragDetectors()
        }

        if pendingSettingsAutomaticDisplayRefresh {
            pendingSettingsAutomaticDisplayRefresh = false
            window?.alphaValue = coordinator.selectedScreenUUID == coordinator.preferredScreenUUID ? 1 : 0
        }
    }

    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }

    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(self)
    }

    private func showOnboardingWindow(step: OnboardingStep = .welcome) {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = String(localized: "Onboarding")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(
                rootView: OnboardingView(
                    step: step,
                    onFinish: {
                        window.orderOut(nil)
//                        NSApp.setActivationPolicy(.accessory)
                        window.close()
                        NSApp.deactivate()
                    },
                    onOpenSettings: {
                        window.close()
                        Task { @MainActor in
                            self.openSettings()
                        }
                    }
                ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            onboardingWindowController = NSWindowController(window: window)
        }

//        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    static let notchDidClose = Notification.Name("notchDidClose")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}
