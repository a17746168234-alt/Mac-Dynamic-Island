//
//  DragDetector.swift
//  boringNotch
//
//  Created by Alexander on 2025-11-20.
//

import Cocoa
import UniformTypeIdentifiers

enum ShelfDropTypePolicy {
    private static let knownImageTypeIdentifiers: Set<String> = [
        UTType.image.identifier,
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.heic.identifier,
        "public.heif",
        UTType.tiff.identifier,
        UTType.gif.identifier,
        "com.microsoft.bmp",
        "org.webmproject.webp",
        "public.camera-raw-image",
        "public.svg-image",
    ]

    static func isImage(_ identifier: String) -> Bool {
        if knownImageTypeIdentifiers.contains(identifier) {
            return true
        }
        return UTType(identifier)?.conforms(to: .image) == true
    }

    static func supports(_ typeIdentifiers: [String]) -> Bool {
        let promisedFileTypes = Set(NSFilePromiseReceiver.readableDraggedTypes)

        return typeIdentifiers.contains { identifier in
            if promisedFileTypes.contains(identifier) {
                return true
            }

            if isImage(identifier) {
                return true
            }

            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .fileURL)
                || type.conforms(to: .url)
                || type.conforms(to: .text)
                || type.conforms(to: .image)
                || type.conforms(to: .data)
        }
    }
}

final class DragDetector {

    // MARK: - Callbacks

    typealias VoidCallback = () -> Void
    typealias PositionCallback = (_ globalPoint: CGPoint) -> Void

    var onDragEntersNotchRegion: VoidCallback?
    var onDragExitsNotchRegion: VoidCallback?
    var onDragMove: PositionCallback?
    var onDragEnded: PositionCallback?


    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var pasteboardChangeCount: Int = -1
    private var isDragging: Bool = false
    private var isContentDragging: Bool = false
    private var hasEnteredNotchRegion: Bool = false
    private var didEnterNotchRegion: Bool = false

    private let notchRegion: CGRect
    private let dragPasteboard = NSPasteboard(name: .drag)

    init(notchRegion: CGRect) {
        self.notchRegion = notchRegion
    }

    // MARK: - Private Helpers
    
    /// Checks if the drag pasteboard contains valid content types that can be dropped on the shelf
    private func hasValidDragContent() -> Bool {
        ShelfDropTypePolicy.supports(dragPasteboard.types?.map(\.rawValue) ?? [])
    }

    func startMonitoring() {
        stopMonitoring()

        // Track pasteboard to detect content drag
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.pasteboardChangeCount = self.dragPasteboard.changeCount
            self.isDragging = true
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.didEnterNotchRegion = false
        }

        // Track drag movement and notch region intersection
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self = self else { return }
            guard self.isDragging else { return }

            let newContent = self.dragPasteboard.changeCount != self.pasteboardChangeCount
            
            // Detect if actual content is being dragged AND it's valid content
            if newContent && !self.isContentDragging && self.hasValidDragContent() {
                self.isContentDragging = true
            }

            // Only process position when content is being dragged
            if self.isContentDragging {
                let mouseLocation = NSEvent.mouseLocation
                self.onDragMove?(mouseLocation)
                
                // Track notch region entry/exit
                let containsMouse = self.notchRegion.contains(mouseLocation)
                if containsMouse && !self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = true
                    self.didEnterNotchRegion = true
                    self.onDragEntersNotchRegion?()
                } else if !containsMouse && self.hasEnteredNotchRegion {
                    self.hasEnteredNotchRegion = false
                    self.onDragExitsNotchRegion?()
                }
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            guard self.isDragging else { return }

            if self.isContentDragging && self.didEnterNotchRegion {
                self.onDragEnded?(NSEvent.mouseLocation)
            }

            self.isDragging = false
            self.isContentDragging = false
            self.hasEnteredNotchRegion = false
            self.didEnterNotchRegion = false
            self.pasteboardChangeCount = -1
        }
    }

    func stopMonitoring() {
        [mouseDownMonitor, mouseDraggedMonitor, mouseUpMonitor].forEach { monitor in
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        mouseDownMonitor = nil
        mouseDraggedMonitor = nil
        mouseUpMonitor = nil
        isDragging = false
        isContentDragging = false
        hasEnteredNotchRegion = false
        didEnterNotchRegion = false
    }

    deinit {
        stopMonitoring()
    }
}
