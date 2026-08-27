import Foundation

enum NotchPresentationPhase: Equatable {
    case closed
    case opening
    case open
    case closing
}

enum NotchInteractionLock: Hashable {
    case popover
    case homeModuleReordering
    case dropTarget
    case gesture
    case settingsInteraction
}

enum NotchMotionProfile: Equatable {
    case standard
    case lowPower
    case reducedMotion
}

enum NotchMotionKind: Equatable {
    case opening
    case closing
    case resizing
    case content
    case gesture
}

enum NotchMotionPolicy {
    static func profile(isLowPowerMode: Bool, reduceMotion: Bool) -> NotchMotionProfile {
        if reduceMotion { return .reducedMotion }
        if isLowPowerMode { return .lowPower }
        return .standard
    }

    static func settleDuration(
        for kind: NotchMotionKind,
        profile: NotchMotionProfile
    ) -> TimeInterval {
        switch profile {
        case .reducedMotion:
            return kind == .content ? 0.08 : 0.1
        case .lowPower:
            return switch kind {
            case .opening: 0.22
            case .closing: 0.18
            case .resizing: 0.2
            case .content: 0.16
            case .gesture: 0.18
            }
        case .standard:
            return switch kind {
            case .opening: 0.34
            case .closing: 0.3
            case .resizing: 0.42
            case .content: 0.3
            case .gesture: 0.36
            }
        }
    }
}

enum NotchInteractionPolicy {
    static let autoCloseDelayMilliseconds = 150
    static let graceAreaRecheckDelayMilliseconds = 150

    static func canOpen(isFirstLaunch: Bool) -> Bool {
        !isFirstLaunch
    }

    static func shouldCloseNotch(
        isOpen: Bool,
        isHovering: Bool,
        activeLocks: Set<NotchInteractionLock>,
        isSharing: Bool,
        pointerInsideGraceArea: Bool = false
    ) -> Bool {
        isOpen
            && !isHovering
            && !pointerInsideGraceArea
            && activeLocks.isEmpty
            && !isSharing
    }

    static func shouldCloseAfterDrop(
        isSharing: Bool,
        activeLocks: Set<NotchInteractionLock>
    ) -> Bool {
        !isSharing && activeLocks.isEmpty
    }
}
