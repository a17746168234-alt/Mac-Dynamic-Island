import AppKit
import CryptoKit
import Foundation

enum ClipboardHistoryContent: Codable, Equatable {
    case text(String)
    case image(Data)
    case files([String])

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case files
    }

    private enum ContentType: String, Codable {
        case text
        case image
        case files
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(ContentType.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(try container.decode(Data.self, forKey: .data))
        case .files:
            self = .files(try container.decode([String].self, forKey: .files))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(data, forKey: .data)
        case .files(let paths):
            try container.encode(ContentType.files, forKey: .type)
            try container.encode(paths, forKey: .files)
        }
    }
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let content: ClipboardHistoryContent
    let fingerprint: String

    var iconName: String {
        switch content {
        case .text: "text.alignleft"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }

    var previewText: String {
        switch content {
        case .text(let text):
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .image:
            String(localized: "Image")
        case .files(let paths):
            paths.count == 1
                ? URL(fileURLWithPath: paths[0]).lastPathComponent
                : String(localized: "\(paths.count) files")
        }
    }
}

@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    private static let enabledKey = "clipboardHistoryEnabled"
    private static let storageKey = "clipboardHistoryItems"
    private static let maximumItemCount = 30
    private static let maximumImageSize = 5 * 1_024 * 1_024

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    private init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        lastChangeCount = pasteboard.changeCount
        restore()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.capturePasteboardIfNeeded()
            }
        }
    }

    deinit {
        timer?.invalidate()
    }

    func copy(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()
        switch item.content {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        case .files(let paths):
            pasteboard.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
        }
        lastChangeCount = pasteboard.changeCount
    }

    func remove(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clear() {
        items.removeAll()
        persist()
    }

    private func capturePasteboardIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard isEnabled, !containsSensitiveOrTransientData else { return }

        let content: ClipboardHistoryContent?
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            content = .files(urls.filter(\.isFileURL).map(\.path))
        } else if let imageData = imageDataFromPasteboard(), imageData.count <= Self.maximumImageSize {
            content = .image(imageData)
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            content = .text(text)
        } else {
            content = nil
        }

        guard let content else { return }
        let fingerprint = fingerprint(for: content)
        items.removeAll { $0.fingerprint == fingerprint }
        items.insert(
            ClipboardHistoryItem(
                id: UUID(),
                createdAt: Date(),
                content: content,
                fingerprint: fingerprint
            ),
            at: 0
        )
        if items.count > Self.maximumItemCount {
            items.removeLast(items.count - Self.maximumItemCount)
        }
        persist()
    }

    private var containsSensitiveOrTransientData: Bool {
        let excludedTypes = [
            "org.nspasteboard.TransientType",
            "org.nspasteboard.ConcealedType",
            "com.agilebits.onepassword",
            "com.typeit4me.clipping"
        ]
        if pasteboard.types?.contains(where: { excludedTypes.contains($0.rawValue) }) == true {
            return true
        }

        let sensitiveBundleIdentifiers = [
            "com.1password.1password",
            "com.bitwarden.desktop",
            "com.keepassium.keepassium",
            "org.keepassxc.keepassxc",
            "com.markmcguill.strongbox"
        ]
        guard let activeBundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased()
        else { return false }
        return sensitiveBundleIdentifiers.contains { activeBundleIdentifier.hasPrefix($0) }
    }

    private func imageDataFromPasteboard() -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        guard let tiff = pasteboard.data(forType: .tiff),
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func fingerprint(for content: ClipboardHistoryContent) -> String {
        let data: Data
        switch content {
        case .text(let text):
            data = Data("text:\(text)".utf8)
        case .image(let imageData):
            data = Data("image:".utf8) + imageData
        case .files(let paths):
            data = Data("files:\(paths.joined(separator: "\u{0}"))".utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let storedItems = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        else { return }
        items = Array(storedItems.prefix(Self.maximumItemCount))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
