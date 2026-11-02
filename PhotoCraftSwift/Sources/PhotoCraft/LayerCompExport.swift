import AppKit
import CoreGraphics
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

struct LayerCompExportOptions: Sendable {
  var format = "png"
  var ids: [UUID] = []
  var prefix = "layer-comp"
  var includeICC = true
  func selected(in document: CraftDocument) throws -> [LayerComp] {
    guard LayerCompsAPI.formats.contains(format), !prefix.isEmpty, prefix.utf8.count <= 64,
      prefix.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "_- ".unicodeScalars.contains($0) }),
      Set(ids).count == ids.count, let library = document.layerComps,
      Set(ids).isSubset(of: Set(library.comps.map(\.id))) else { throw CraftError.invalid("Choose existing Layer Comps, a safe filename prefix and an output format.") }
    let comps = library.comps.filter { ids.isEmpty || ids.contains($0.id) }
    guard !comps.isEmpty else { throw CraftError.invalid("Create a Layer Comp before exporting.") }
    guard comps.allSatisfy({ $0.missingLayers(in: document).isEmpty }) else { throw CraftError.invalid("Some comp layers were deleted. Review and recapture those comps before exporting.") }
    guard comps.allSatisfy({ $0.unavailableSmartObjectLayers(in: document).isEmpty }) else { throw CraftError.invalid("A recorded Smart Object source changed. Review and recapture those comps before exporting.") }
    return comps
  }
}
struct LayerCompExportOutput: Sendable {
  let data: Data
  let contentType: String
  let files: [StoredZIP.File]
}
enum LayerCompExport {
  static let maximumBytes = 128 * 1024 * 1024
  static func render(_ document: CraftDocument, options: LayerCompExportOptions, maximumBytes: Int = maximumBytes, sourceData: [UUID: Data] = [:]) throws -> LayerCompExportOutput {
    try Task.checkCancellation(); try document.validate()
    guard (1...Self.maximumBytes).contains(maximumBytes) else { throw CraftError.invalid("Invalid comp output budget.") }
    let comps = try options.selected(in: document)
    if options.format == "pdf" { return try pdf(document, comps: comps, maximumBytes: maximumBytes, sourceData: sourceData) }
    guard let format = DocumentIO.Format(rawValue: options.format) else { throw CraftError.invalid("Unknown comp format.") }
    var files: [StoredZIP.File] = [], records: [[String: String]] = [], total = 0
    for (index, comp) in comps.enumerated() {
      try Task.checkCancellation()
      // Each variation starts from the same source, including unrecorded properties.
      var variation = try LayerCompIO.document(document, applying: comp.id, sourceData: sourceData)
      if format != .native { variation.layerComps = nil }
      if format != .native { variation.profileIsUntagged = options.includeICC ? nil : true }
      let bytes = try DocumentIO.encode(variation, format: format,
        options: .init(jpegEmbedProfile: format == .jpeg ? options.includeICC : nil))
      guard bytes.count <= maximumBytes - total else { throw CraftError.invalid("Comp export exceeds its output budget. Export fewer comps.") }
      total += bytes.count
      var safe = comp.name.map { character in "/:\\".contains(character) || character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? Character("_") : character }
      while String(safe).utf8.count > 160 { safe.removeLast() }
      let name = options.prefix + String(format: "_%04d_", index) + String(safe) + "." + format.rawValue
      files.append(.init(name: name, data: bytes)); records.append(["id": comp.id.uuidString, "name": comp.name, "file": name])
    }
    let manifest = try JSONSerialization.data(withJSONObject: ["version": 1, "source": document.name, "format": options.format, "comps": records], options: [.sortedKeys, .prettyPrinted])
    guard manifest.count <= maximumBytes - total else { throw CraftError.invalid("The comp manifest exceeds its output budget.") }
    files.append(.init(name: "layer-comps.json", data: manifest))
    let data = try StoredZIP.encode(files, maximumBytes: maximumBytes)
    return .init(data: data, contentType: "application/zip", files: files)
  }
  private static func pdf(_ document: CraftDocument, comps: [LayerComp], maximumBytes: Int, sourceData: [UUID: Data]) throws -> LayerCompExportOutput {
    let bytes = NSMutableData()
    guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw CraftError.invalid("Could not create a comp PDF.") }
    for comp in comps {
      try Task.checkCancellation()
      let variation = try LayerCompIO.document(document, applying: comp.id, sourceData: sourceData)
      let image = try ColorManagement.image(Renderer.composite(variation), in: variation)
      var page = CGRect(x: 0, y: 0, width: document.width, height: document.height)
      context.beginPDFPage([kCGPDFContextMediaBox as String: NSData(bytes: &page, length: MemoryLayout<CGRect>.size)] as CFDictionary)
      context.draw(image, in: page); context.endPDFPage()
      guard bytes.length <= maximumBytes else { throw CraftError.invalid("Comp PDF exceeds its output budget.") }
    }
    context.closePDF(); try Task.checkCancellation()
    guard bytes.length <= maximumBytes else { throw CraftError.invalid("Comp PDF exceeds its output budget.") }
    return .init(data: bytes as Data, contentType: "application/pdf", files: [])
  }
}
extension EditorStore {
  var canEditLayerComps: Bool {
    canEditFileInfo && !coalescingChanges && numericEditor == nil && layerNameDraft == nil && typeEditingDraft == nil &&
      brushGesture == nil && pathGesture == nil && timelineTask == nil && !printBusy
  }
  func editLayerComp(_ command: LayerCompCommand) throws {
    guard canEditLayerComps else { throw CraftError.invalid("Finish the current edit before using Layer Comps.") }
    try editPreparedLayerComp(command)
  }
  func encodedLayerComps(_ options: LayerCompExportOptions, grants: [UUID: LinkedArtworkGrant] = [:]) async throws -> LayerCompExportOutput {
    guard canEditLayerComps, layerCompExportID == nil else { throw CraftError.invalid("Finish the current edit or comp export first.") }
    _ = try options.selected(in: document)
    let snapshot = document, generation = layerPanelGeneration, id = UUID()
    layerCompExportID = id; geometryBusy = true; status = "Exporting Layer Comps…"
    let registry = linkedSourceRegistry
    let worker = Task.detached(priority: .userInitiated) {
      let files = try LayerCompSourceFiles.read(grants)
      let output = try LayerCompExport.render(snapshot, options: options, sourceData: files.mapValues(\.data))
      try LayerCompSourceFiles.validate(files); return output
    }
    layerCompExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }; geometryTask = observer
    defer {
      if layerCompExportID == id {
        layerCompExportID = nil; layerCompExportWorker = nil
        if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil }
      }
    }
    let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == snapshot, layerPanelGeneration == generation else { throw CancellationError() }
    guard grants.values.allSatisfy({ registry.stillAuthorizes($0) }) else { throw CraftError.invalid("Linked artwork authorization changed during comp export.") }
    return output
  }
  func presentLayerCompExport(pdf: Bool, selected: Set<UUID> = []) {
    guard canEditLayerComps, let library = document.layerComps, !library.comps.isEmpty else { return }
    let snapshot = document, generation = layerPanelGeneration
    let panel: NSSavePanel = pdf ? NSSavePanel() : NSOpenPanel()
    if let open = panel as? NSOpenPanel { open.canChooseFiles = false; open.canChooseDirectories = true; open.canCreateDirectories = true }
    else { panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = snapshot.name + ".pdf" }
    panel.title = pdf ? "Layer Comps to PDF" : "Layer Comps to Files"; panel.prompt = "Export"
    let format = NSPopUpButton(), prefix = NSTextField(string: "layer-comp"), onlySelected = NSButton(checkboxWithTitle: "Selected Layer Comps Only", target: nil, action: nil), icc = NSButton(checkboxWithTitle: "Include ICC Profile", target: nil, action: nil)
    let formats = ["psd", "psb", "png", "jpeg", "tiff", "photato"]; format.addItems(withTitles: ["Photoshop PSD", "Large Document PSB", "PNG", "JPEG", "TIFF", "Photato (editable)"])
    onlySelected.isEnabled = !selected.isEmpty; icc.state = .on
    let grid = NSGridView(views: pdf ? [[onlySelected]] : [[NSTextField(labelWithString: "File Name Prefix:"), prefix], [NSTextField(labelWithString: "File Type:"), format], [onlySelected], [icc]])
    grid.rowSpacing = 8; grid.setFrameSize(grid.fittingSize); panel.accessoryView = grid
    if !pdf { panel.message = "Creates a new folder named <prefix>-comps. Existing folders are never replaced." }
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let self, let destination = panel.url else { return }
      guard self.document == snapshot, self.layerPanelGeneration == generation, self.canEditLayerComps else { self.error = "The document changed. Reopen comp export."; return }
      let options = LayerCompExportOptions(format: pdf ? "pdf" : formats[format.indexOfSelectedItem], ids: onlySelected.state == .on ? Array(selected) : [], prefix: prefix.stringValue, includeICC: icc.state == .on)
      Task { @MainActor in
        let accessed = destination.startAccessingSecurityScopedResource(); defer { if accessed { destination.stopAccessingSecurityScopedResource() } }
        do {
          let grants = try self.layerCompGrants(LayerCompSourceFiles.targets(options, document: snapshot))
          let output = try await self.encodedLayerComps(options, grants: grants)
          let worker = Task.detached(priority: .userInitiated) {
            if pdf {
              try Task.checkCancellation(); let writer = try AtomicFileWriter(to: destination, maximumBytes: LayerCompExport.maximumBytes); try writer.append(output.data); try writer.commit()
            } else {
              let folder = destination.appendingPathComponent(options.prefix + "-comps", isDirectory: true)
              let prepared = try PreparedSequenceFolder.prepare(.init(files: output.files), destination: folder); defer { prepared.discard() }
              try prepared.commit()
            }
          }
          try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          self.status = "Exported Layer Comps"
        } catch is CancellationError { self.status = "Comp export cancelled" }
        catch { self.error = error.localizedDescription }
      }
    }
    if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
  }
}
