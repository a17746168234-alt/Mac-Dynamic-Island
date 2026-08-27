import AppKit
import Foundation
import UniformTypeIdentifiers

private enum DragDetectorTypePolicyTestFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw DragDetectorTypePolicyTestFailure.assertion(message)
    }
}

@main
struct DragDetectorTypePolicyTests {
    static func main() throws {
        try expect(
            ShelfDropTypePolicy.supports([UTType.fileURL.identifier]),
            "Finder 文件拖拽必须被识别"
        )
        try expect(
            ShelfDropTypePolicy.supports([UTType.jpeg.identifier]),
            "照片应用提供的 JPEG 图像拖拽必须被识别"
        )
        try expect(
            ShelfDropTypePolicy.supports([UTType.heic.identifier]),
            "iCloud 照片常见的 HEIC 图像拖拽必须被识别"
        )
        try expect(
            ShelfDropTypePolicy.supports(NSFilePromiseReceiver.readableDraggedTypes),
            "macOS 文件承诺拖拽必须被识别"
        )
        try expect(
            !ShelfDropTypePolicy.supports(["com.example.unsupported-private-type"]),
            "不支持的私有类型不应触发暂存台"
        )
        print("DragDetectorTypePolicyTests: PASS")
    }
}
