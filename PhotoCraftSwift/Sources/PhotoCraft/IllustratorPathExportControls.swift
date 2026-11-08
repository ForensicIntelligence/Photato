import AppKit
import PhotoCraftCore
import PhotoCraftImaging

@MainActor final class IllustratorPathExportOptions {
  let alert = NSAlert()
  let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
  let choices: [IllustratorPathExport.Choice]
  init(_ document: CraftDocument) throws {
    choices = try IllustratorPathExport.choices(document)
    picker.addItems(withTitles: choices.map(\.name))
    let selection = try IllustratorPathExport.defaultSelection(document)
    picker.selectItem(at: choices.firstIndex(where: { $0.selection == selection }) ?? 0)
    picker.setAccessibilityLabel("Path")
    alert.messageText = "Export Paths to File"
    alert.accessoryView = picker
    alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
  }
  var selection: IllustratorPathExport.Selection { choices[max(0, picker.indexOfSelectedItem)].selection }
}

@MainActor extension EditorStore {
  var canExportIllustratorPaths: Bool {
    canExportImages && !showAI && !showImagePlayground && geometrySheet == nil
      && pathGesture == nil && freeformGesture == nil && eyedropperGesture == nil
      && layerProtectionDraft == nil && error == nil
  }
  func encodedIllustratorPaths(_ selection: IllustratorPathExport.Selection? = nil,
    title: String = "Paths.ai") async throws -> Data {
    guard canExportIllustratorPaths, illustratorExportID == nil else {
      throw CraftError.invalid("Finish the current interaction before exporting paths.")
    }
    let source = document, generation = layerPanelGeneration, session = sessionGeneration
    let id = UUID(), prepare = illustratorPathPreparation
    illustratorExportID = id; geometryBusy = true
    let worker = Task.detached(priority: .userInitiated) { try prepare(source, selection, title) }
    illustratorExportWorker = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value }
      onCancel: { worker.cancel() } }
    geometryTask = observer
    defer {
      if illustratorExportID == id {
        illustratorExportID = nil; illustratorExportWorker = nil
        if layerPanelGeneration == generation { geometryBusy = false; geometryTask = nil }
      }
    }
    let bytes = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation()
    guard !worker.isCancelled, !observer.isCancelled, document == source,
      layerPanelGeneration == generation, sessionGeneration == session else { throw CancellationError() }
    return bytes
  }
}

@MainActor extension AppDelegate {
  var canPresentIllustratorPathExport: Bool {
    controller.documentWindows.canChangeDocument && store?.canExportIllustratorPaths == true
      && NSApp.modalWindow == nil && controller.currentDocument?.windowForSheet?.attachedSheet == nil
  }
  @objc func exportPathsToIllustrator() {
    guard canPresentIllustratorPathExport, let document = controller.currentDocument as? CraftNSDocument,
      let window = document.windowForSheet else { return }
    let store = document.store, source = store.document, generation = store.layerPanelGeneration
    do {
      let options = try IllustratorPathExportOptions(source)
      options.alert.beginSheetModal(for: window) { [weak self, weak document] response in
        guard response == .alertFirstButtonReturn, let self, let document else { return }
        guard document.store.document == source, document.store.layerPanelGeneration == generation,
          document.closeWorkflowID == nil, self.store === store, store.canExportIllustratorPaths else {
          store.error = "The document changed. Reopen path export."; return
        }
        let selection = options.selection, panel = NSSavePanel()
        panel.title = "Choose a file name to save paths to"
        panel.allowedContentTypes = [IllustratorPathExport.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ImageAssetExport.safeName(source.name) + ".ai"
        panel.beginSheetModal(for: window) { [weak document] result in
          guard result == .OK, let document, let destination = panel.url else { return }
          guard store.document == source, store.layerPanelGeneration == generation,
            document.closeWorkflowID == nil, store.canExportIllustratorPaths else {
            store.error = "The document changed. Reopen path export."; return
          }
          Task { @MainActor in
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            do {
              store.status = "Exporting paths…"
              let bytes = try await store.encodedIllustratorPaths(selection, title: destination.lastPathComponent)
              try Task.checkCancellation()
              guard store.document == source, store.layerPanelGeneration == generation,
                document.closeWorkflowID == nil else { throw CancellationError() }
              let worker = Task.detached(priority: .userInitiated) {
                try PreparedDocumentOutput.data(bytes).write(to: destination)
              }
              try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
              store.status = "Exported paths to " + destination.lastPathComponent
            } catch is CancellationError { store.status = "Path export cancelled" }
            catch { store.error = error.localizedDescription }
          }
        }
      }
    } catch { store.error = error.localizedDescription }
  }
}
