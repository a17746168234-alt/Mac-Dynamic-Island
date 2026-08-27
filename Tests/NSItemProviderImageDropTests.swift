import AppKit
import Foundation
import UniformTypeIdentifiers

// Minimal test double required by NSItemProvider+LoadHelpers.swift. The image
// representation path under test does not create or resolve bookmarks.
struct Bookmark {
    init(data: Data) {}
    func resolveURL() -> URL? { nil }
}

private enum ImageDropTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw ImageDropTestFailure.assertion(message) }
}

@main
struct NSItemProviderImageDropTests {
    static func main() async throws {
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let provider = NSItemProvider()
        provider.suggestedName = "iCloud Photo"
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            visibility: .all
        ) { completion in
            completion(jpegBytes, nil)
            return nil
        }

        guard let loaded = await provider.loadImageRepresentation() else {
            throw ImageDropTestFailure.assertion("public.jpeg 数据必须能从照片拖放提供器中读取")
        }

        try expect(loaded.data == jpegBytes, "JPEG 字节必须完整保留")
        try expect(
            loaded.suggestedName.lowercased().hasSuffix(".jpeg"),
            "没有扩展名的 iCloud 照片必须补全 .jpeg"
        )

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDynamicIsland-drop-test-\(UUID().uuidString).txt")
        try Data("drop".utf8).write(to: temporaryURL)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let fileProvider = NSItemProvider(contentsOf: temporaryURL),
              let extractedURL = await fileProvider.extractFileURL() else {
            throw ImageDropTestFailure.assertion("Finder 文件 URL 必须能被暂存器和隔空投送读取")
        }
        try expect(
            extractedURL.standardizedFileURL == temporaryURL.standardizedFileURL,
            "Finder 文件拖放必须保留原始 URL"
        )
        print("NSItemProviderImageDropTests: PASS")
    }
}
