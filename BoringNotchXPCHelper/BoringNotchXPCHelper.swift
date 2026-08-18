//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import AppKit
import ApplicationServices
import IOKit
import CoreGraphics
import SystemConfiguration
import Darwin

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Clash Verge system proxy

    @objc func setClashVergeSystemProxyEnabled(
        _ enabled: Bool,
        with reply: @escaping (Bool, String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard Self.updateClashVergePreference(enabled: enabled) else {
                reply(false, "preferenceUpdateFailed")
                return
            }
            guard Self.updateSystemProxy(enabled: enabled) else {
                reply(false, "systemProxyFailed")
                return
            }
            if let refreshURL = URL(string: "verge://refresh-verge-config") {
                DispatchQueue.main.async { NSWorkspace.shared.open(refreshURL) }
            }
            reply(true, nil)
        }
    }

    @objc func fetchClashVergeProxyOverview(with reply: @escaping (String?, String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let response = Self.mihomoRequest(method: "GET", path: "/proxies"),
                  (200..<300).contains(response.status),
                  let json = String(data: response.body, encoding: .utf8)
            else {
                reply(nil, "mihomoUnavailable")
                return
            }
            reply(json, nil)
        }
    }

    @objc func selectClashVergeNode(
        _ node: String,
        forGroup group: String,
        with reply: @escaping (Bool, String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let body = try? JSONSerialization.data(withJSONObject: ["name": node]),
                  let response = Self.mihomoRequest(
                    method: "PUT",
                    path: "/proxies/\(Self.urlPathComponent(group))",
                    body: body
                  ),
                  (200..<300).contains(response.status)
            else {
                reply(false, "nodeSelectionFailed")
                return
            }
            reply(true, nil)
        }
    }

    @objc func testClashVergeNodeDelay(
        _ node: String,
        with reply: @escaping (NSNumber?, String?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let testURL = "https://www.gstatic.com/generate_204"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let path = "/proxies/\(Self.urlPathComponent(node))/delay?timeout=5000&url=\(testURL)"
            guard let response = Self.mihomoRequest(method: "GET", path: path),
                  (200..<300).contains(response.status),
                  let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any],
                  let delay = object["delay"] as? NSNumber
            else {
                reply(nil, "delayTestFailed")
                return
            }
            reply(delay, nil)
        }
    }

    // MARK: - Application launcher

    @objc func terminateApplication(
        _ bundleIdentifier: String,
        with reply: @escaping (Bool) -> Void
    ) {
        DispatchQueue.main.async {
            let applications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            guard !applications.isEmpty else { reply(false); return }
            reply(applications.reduce(false) { $1.terminate() || $0 })
        }
    }

    private static func updateSystemProxy(enabled: Bool) -> Bool {
        guard let preferences = SCPreferencesCreate(nil, "MacDynamicIsland" as CFString, nil),
              let services = SCNetworkServiceCopyAll(preferences) as? [SCNetworkService]
        else { return false }
        var changed = false
        for service in services {
            guard SCNetworkServiceGetEnabled(service),
                  let protocolRef = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies)
            else { continue }
            var config = (SCNetworkProtocolGetConfiguration(protocolRef) as? [String: Any]) ?? [:]
            config[kSCPropNetProxiesHTTPEnable as String] = enabled ? 1 : 0
            config[kSCPropNetProxiesHTTPSEnable as String] = enabled ? 1 : 0
            config[kSCPropNetProxiesSOCKSEnable as String] = enabled ? 1 : 0
            if enabled {
                config[kSCPropNetProxiesHTTPProxy as String] = "127.0.0.1"
                config[kSCPropNetProxiesHTTPPort as String] = 7897
                config[kSCPropNetProxiesHTTPSProxy as String] = "127.0.0.1"
                config[kSCPropNetProxiesHTTPSPort as String] = 7897
                config[kSCPropNetProxiesSOCKSProxy as String] = "127.0.0.1"
                config[kSCPropNetProxiesSOCKSPort as String] = 7897
            }
            changed = SCNetworkProtocolSetConfiguration(protocolRef, config as CFDictionary) || changed
        }
        guard changed else { return false }
        return SCPreferencesCommitChanges(preferences) && SCPreferencesApplyChanges(preferences)
    }

    private static func updateClashVergePreference(enabled: Bool) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/verge.yaml")
        guard var contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let replacement = "enable_system_proxy: \(enabled ? "true" : "false")"
        if let range = contents.range(of: #"(?m)^enable_system_proxy:\s*(true|false)\s*$"#, options: .regularExpression) {
            contents.replaceSubrange(range, with: replacement)
        } else {
            contents += "\n\(replacement)\n"
        }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }

    private struct HTTPResponse { let status: Int; let body: Data }

    private static func mihomoRequest(method: String, path: String, body: Data? = nil) -> HTTPResponse? {
        let socketPath = "/tmp/verge/verge-mihomo.sock"
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard socketPath.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in socketPath.utf8.enumerated() { buffer[index] = byte }
        }
        let length = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, length) }
        }
        guard connected == 0 else { return nil }
        var headers = "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n"
        if let body { headers += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n" }
        headers += "\r\n"
        var request = Data(headers.utf8)
        if let body { request.append(body) }
        guard request.withUnsafeBytes({ bytes in
            guard let base = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count <= 0 { return false }
                offset += count
            }
            return true
        }) else { return nil }
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 { break }
            response.append(buffer, count: count)
        }
        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              let headerText = String(data: response[..<separator.lowerBound], encoding: .utf8),
              let statusText = headerText.split(separator: "\r\n").first?.split(separator: " ").dropFirst().first,
              let status = Int(statusText)
        else { return nil }
        let rawBody = Data(response[separator.upperBound...])
        let chunked = headerText.range(of: "transfer-encoding: chunked", options: .caseInsensitive) != nil
        return HTTPResponse(status: status, body: chunked ? decodeChunked(rawBody) ?? rawBody : rawBody)
    }

    private static func decodeChunked(_ data: Data) -> Data? {
        var cursor = data.startIndex
        var output = Data()
        while cursor < data.endIndex {
            guard let lineEnd = data[cursor...].range(of: Data("\r\n".utf8)),
                  let sizeText = String(data: data[cursor..<lineEnd.lowerBound], encoding: .utf8),
                  let size = Int(sizeText.split(separator: ";").first ?? "", radix: 16)
            else { return nil }
            cursor = lineEnd.upperBound
            if size == 0 { return output }
            guard data.distance(from: cursor, to: data.endIndex) >= size + 2 else { return nil }
            output.append(data[cursor..<data.index(cursor, offsetBy: size)])
            cursor = data.index(cursor, offsetBy: size + 2)
        }
        return output
    }

    private static func urlPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
