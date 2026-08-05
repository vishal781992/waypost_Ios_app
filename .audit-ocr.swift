import Foundation
import Vision
import AppKit

let path = CommandLine.arguments[1]
guard let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot read image")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
let handler = VNImageRequestHandler(cgImage: cg)
try handler.perform([request])
let rows = (request.results ?? []).compactMap { result -> (Double, Double, String)? in
    guard let text = result.topCandidates(1).first?.string else { return nil }
    return (result.boundingBox.minY, result.boundingBox.minX, text)
}.sorted { lhs, rhs in
    if abs(lhs.0 - rhs.0) > 0.015 { return lhs.0 > rhs.0 }
    return lhs.1 < rhs.1
}
for row in rows { print(String(format: "y=%.3f x=%.3f | %@", row.0, row.1, row.2)) }
