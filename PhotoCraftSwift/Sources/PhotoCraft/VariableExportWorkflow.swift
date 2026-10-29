import AppKit
import PhotoCraftCore

extension EditorStore {
  var canEditVariables: Bool { canUseTimeline && timelineTask == nil }
  func encodedVariableData(_ options: VariableExportOptions, archive: Bool = false) async throws -> ImageSequenceOutput {
    guard canEditVariables, variableExportID == nil else { throw CraftError.invalid("Stop playback and finish the current edit before exporting data sets.") }
    _ = try options.selectedRows(in: document)
    let snapshot = document, generation = layerPanelGeneration, operation = UUID()
    variableExportID = operation; geometryBusy = true; status = "Rendering data sets…"
    let worker = Task.detached(priority: .userInitiated) {
      var output = try VariableDataExport.render(snapshot, options: options)
      if archive { output.archive = try output.zip() }
      return output
    }
    variableExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    geometryTask = observer
    var completed = false
    defer {
      if variableExportID == operation {
        variableExportID = nil; variableExportWorker = nil
        if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil }
        status = completed ? "Data sets rendered" : "Data-set export stopped"
      }
    }
    let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == snapshot, layerPanelGeneration == generation else { throw CancellationError() }
    completed = true; return output
  }
  func presentVariableExport() {
    guard canEditVariables, let variables = document.variables, !variables.dataSets.isEmpty else { return }
    let snapshot = document, generation = layerPanelGeneration
    let prefix = NSTextField(string: "data-set"), format = NSPopUpButton(), rows = NSPopUpButton()
    let formats: [DocumentIO.Format] = [.psd, .psb, .native, .png, .tiff, .jpeg]
    format.addItems(withTitles: ["Photoshop PSD", "Large Document PSB", "Photato template", "PNG", "TIFF", "JPEG"])
    rows.addItems(withTitles: ["All Data Sets"] + variables.dataSets.map(\.name))
    let grid = NSGridView(views: [[NSTextField(labelWithString: "Filename Prefix:"), prefix], [NSTextField(labelWithString: "File Type:"), format], [NSTextField(labelWithString: "Data Set:"), rows]])
    prefix.widthAnchor.constraint(equalToConstant: 230).isActive = true; grid.rowSpacing = 8; grid.setFrameSize(grid.fittingSize)
    let panel = NSOpenPanel(); panel.title = "Data Sets as Files"; panel.prompt = "Export"
    panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.accessoryView = grid
    panel.message = "Create a new <prefix>-data-sets folder. Each variation starts from this template. Photato files retain variables; rendered formats contain the applied result."
    let window = NSApp.keyWindow
    let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
      guard response == .OK, let self, let parent = panel.url else { return }
      guard self.canEditVariables, self.document == snapshot, self.layerPanelGeneration == generation else { self.error = "The template changed. Reopen export settings."; return }
      let options = VariableExportOptions(prefix: prefix.stringValue, format: formats[format.indexOfSelectedItem], dataSetIDs: rows.indexOfSelectedItem == 0 ? [] : [variables.dataSets[rows.indexOfSelectedItem - 1].id])
      do { _ = try options.selectedRows(in: snapshot) } catch { self.error = error.localizedDescription; return }
      let destination = parent.appendingPathComponent(options.prefix + "-data-sets", isDirectory: true)
      let progress = NSAlert(); progress.messageText = "Exporting Data Sets"; progress.informativeText = "Rendering variations…"; progress.addButton(withTitle: "Cancel")
      let task = Task { @MainActor in
        let scoped = parent.startAccessingSecurityScopedResource()
        defer { if scoped { parent.stopAccessingSecurityScopedResource() }; if let parent = progress.window.sheetParent { parent.endSheet(progress.window, returnCode: .OK) } }
        do {
          let output = try await self.encodedVariableData(options)
          let worker = Task.detached(priority: .userInitiated) { try PreparedSequenceFolder.prepare(output, destination: destination) }
          let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }; defer { prepared.discard() }
          guard self.document == snapshot, self.layerPanelGeneration == generation else { throw CancellationError() }
          try Task.checkCancellation(); try prepared.commit(); self.status = "Exported \(output.files.count - 1) data sets"
        } catch is CancellationError { self.status = "Data-set export cancelled" }
        catch { self.error = error.localizedDescription }
      }
      if let window { progress.beginSheetModal(for: window) { response in if response != .OK { task.cancel(); self.variableExportWorker?.cancel() } } }
    }
    if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
  }
}
extension AutomationCommand {
  func variableExportOptions() throws -> VariableExportOptions {
    guard let format = DocumentIO.Format(rawValue: try variableString("format")) else { throw AutomationFailure(status: 400, message: "Unknown data-set output format.") }
    var ids: [UUID] = []
    if let input = parameters["dataSetIDs"] {
      let raw = try BrushAPI.merge(input, schema: VariablesAPI.schema("dataSetIDs"), path: "dataSetIDs") as! [String]
      ids = try raw.map(VariablesAPI.parseUUID)
    }
    return .init(prefix: try parameters["prefix"].map { _ in try variableString("prefix") } ?? "data-set", format: format, dataSetIDs: ids)
  }
}
extension AutomationService {
  func exportVariableData(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers before exporting data sets.") }
    let options = try command.variableExportOptions(), snapshot = document.store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    variableExportShares.insert(shareID); defer { variableExportShares.remove(shareID) }
    let output = try await document.store.encodedVariableData(options, archive: true)
    prune()
    guard isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where: { $0.id == shareID && $0.document === document }), document.store.document == snapshot, revision(document.store) == command.revision else {
      throw AutomationFailure(status: 409, message: "Data-set export was revoked or its source changed.")
    }
    guard let bytes = output.archive else { throw CraftError.invalid("Data-set archive was not produced.") }
    document.store.status = "Exported data sets"; return .init(status: 200, contentType: "application/zip", body: bytes)
  }
  func cancelSharedVariableExport(_ share: Share) {
    guard variableExportShares.contains(share.id) else { return }
    share.document?.store.variableExportWorker?.cancel()
  }
}
