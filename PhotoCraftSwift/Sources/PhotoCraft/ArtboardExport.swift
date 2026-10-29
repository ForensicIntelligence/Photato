import AppKit
import CoreGraphics
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

enum ArtboardExport {
  static let formats = ["png", "jpeg", "tiff", "photato", "pdf"]
  static func encode(_ document: CraftDocument, ids: [UUID], format: String) throws -> Data {
    guard !ids.isEmpty, ids.count <= 256, Set(ids).count == ids.count, ids.allSatisfy({ id in document.artboards.contains { $0.id == id } }), formats.contains(format) else { throw CraftError.invalid("Choose distinct artboards and a supported export format.") }
    if format == "pdf" { return try pdf(document, ids: ids) }
    guard ids.count == 1, let encoding = DocumentIO.Format(rawValue: format) else { throw CraftError.invalid("Choose one artboard for an image/native file, or PDF for multiple pages.") }
    let extracted = try document.extractedArtboard(ids[0])
    let result = try DocumentIO.encode(extracted, format: encoding)
    guard result.count <= DocumentIO.maximumDownloadBytes else { throw CraftError.invalid("Artboard export exceeds 128 MiB.") }; return result
  }
  static func pdf(_ document: CraftDocument, ids: [UUID]) throws -> Data {
    let bytes = NSMutableData()
    guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw CraftError.invalid("Could not create PDF.") }
    for id in ids {
      try Task.checkCancellation()
      let extracted = try document.extractedArtboard(id)
      let image = try ColorManagement.image(Renderer.composite(extracted), in: extracted)
      var page = CGRect(x: 0, y: 0, width: extracted.width, height: extracted.height)
      let media = NSData(bytes: &page, length: MemoryLayout<CGRect>.size)
      context.beginPDFPage([kCGPDFContextMediaBox as String: media] as CFDictionary)
      context.draw(image, in: page); context.endPDFPage()
      guard bytes.length <= DocumentIO.maximumDownloadBytes else { throw CraftError.invalid("PDF export exceeds 128 MiB.") }
    }
    context.closePDF()
    guard bytes.length <= DocumentIO.maximumDownloadBytes else { throw CraftError.invalid("PDF export exceeds 128 MiB.") }
    return bytes as Data
  }
  static func writeNew(_ data: Data, to destination: URL) throws {
    let staged = destination.deletingLastPathComponent().appendingPathComponent(".photato-artboard-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: staged) }
    let writer = try AtomicFileWriter(to: staged, maximumBytes: DocumentIO.maximumDownloadBytes)
    try writer.append(data); try writer.commit(); try Task.checkCancellation()
    try FileManager.default.linkItem(at: staged, to: destination)
  }
}
@MainActor extension AppDelegate {
  @objc func exportArtboardFiles() {
    guard let store, store.canEditArtboards, store.document.hasArtboards else { return }
    let snapshot = store.document
    let panel = NSOpenPanel(); panel.title = "Artboards to Files"; panel.prompt = "Export"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
    let choices = NSPopUpButton(frame: .init(x: 0, y: 0, width: 220, height: 26)); choices.addItems(withTitles: ["PNG", "JPEG", "TIFF", "Photato (editable)"]); panel.accessoryView = choices
    panel.begin { response in
      guard response == .OK, let directory = panel.url else { return }
      let format = ["png", "jpeg", "tiff", "photato"][choices.indexOfSelectedItem]
      Task { @MainActor in
        do {
          let count = try await Task.detached(priority: .userInitiated) {
            var completed = 0
            for (index, board) in snapshot.artboards.enumerated() {
              let bytes = try ArtboardExport.encode(snapshot, ids: [board.id], format: format)
              let name = try ActionBatch.outputName(board.name, index: index, suffix: "", format: DocumentIO.Format(rawValue: format)!)
              try ArtboardExport.writeNew(bytes, to: directory.appendingPathComponent(name)); completed += 1
            }
            return completed
          }.value
          store.status = "Exported \(count) artboards"
        } catch { store.error = "Artboard export stopped: \(error.localizedDescription) Files already exported are retained." }
      }
    }
  }
  @objc func exportArtboardPDF() {
    guard let store, store.canEditArtboards, store.document.hasArtboards else { return }
    let snapshot = store.document
    let panel = NSSavePanel(); panel.title = "Artboards to PDF"; panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = snapshot.name + ".pdf"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        do {
          try await Task.detached(priority: .userInitiated) {
            let bytes = try ArtboardExport.encode(snapshot, ids: snapshot.artboards.map(\.id), format: "pdf")
            let writer = try AtomicFileWriter(to: url, maximumBytes: DocumentIO.maximumDownloadBytes); try writer.append(bytes); try writer.commit()
          }.value
          store.status = "Exported artboards to PDF"
        } catch { store.error = error.localizedDescription }
      }
    }
  }
}
