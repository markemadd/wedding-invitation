// ReceiptProbe — dev-only macOS harness (not part of the app).
//
// Runs the SAME Vision configuration the app's ReceiptOCRService uses on a
// folder of receipt images and writes one JSON dump per image:
//   [{"text": …, "h": …, "top": …, "left": …}, …]
// The dumps become test fixtures for the OCR heuristics, so the amount/
// merchant/date/currency rules are tuned and regression-tested against
// REAL receipts rather than synthetic strings.
//
// Usage:  swiftc -O Tools/ReceiptProbe.swift -o /tmp/receiptprobe \
//             -framework Vision -framework ImageIO
//         /tmp/receiptprobe <input-folder> <output-folder>

import Foundation
import Vision
import ImageIO

struct DumpLine: Codable {
    let text: String
    let h: Double
    let top: Double
    let left: Double
    let w: Double
}

guard CommandLine.arguments.count == 3 else {
    fatalError("usage: receiptprobe <input-folder> <output-folder>")
}
let inputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDir = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let imageExtensions = Set(["heic", "jpg", "jpeg", "png"])
let files = try FileManager.default.contentsOfDirectory(at: inputDir, includingPropertiesForKeys: nil)
    .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

for file in files {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("SKIP (unreadable): \(file.lastPathComponent)")
        continue
    }
    // EXIF orientation — iPhone photos store pixels unrotated plus a flag;
    // Vision needs the flag or every bounding box comes back sideways.
    var orientation = CGImagePropertyOrientation.up
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
       let parsed = CGImagePropertyOrientation(rawValue: rawValue) {
        orientation = parsed
    }

    // Must mirror ReceiptOCRService exactly, or the fixtures lie.
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en", "ar", "fr", "es"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
    try handler.perform([request])

    let lines: [DumpLine] = (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let box = observation.boundingBox
        return DumpLine(text: text, h: box.height, top: 1 - box.maxY, left: box.minX, w: box.width)
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let outURL = outputDir.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".json")
    try encoder.encode(lines).write(to: outURL)
    print("OK: \(file.lastPathComponent) → \(lines.count) lines")
}
