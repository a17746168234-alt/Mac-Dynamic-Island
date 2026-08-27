//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Clash Verge integration (performed by the unsandboxed helper)
    func setClashVergeSystemProxyEnabled(_ enabled: Bool, with reply: @escaping (Bool, String?) -> Void)
    func fetchClashVergeProxyOverview(with reply: @escaping (String?, String?) -> Void)
    func selectClashVergeNode(_ node: String, forGroup group: String, with reply: @escaping (Bool, String?) -> Void)
    func testClashVergeNodeDelay(_ node: String, with reply: @escaping (NSNumber?, String?) -> Void)
    // Application launcher integration (performed by the unsandboxed helper)
    func terminateApplication(_ bundleIdentifier: String, with reply: @escaping (Bool) -> Void)
}
