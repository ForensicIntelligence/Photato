import AppKit
import SwiftUI
import PhotoCraftCore
import PhotoCraftImaging

@MainActor final class VariableEditorModel: ObservableObject {
  let source: CraftDocument
  @Published var settings: DataDrivenGraphics
  @Published var layerID: UUID?
  @Published var rowID: UUID?
  @Published var tab = 0
  @Published var previewEnabled = true
  @Published var preview: NSImage?
  @Published var error: String?
  @Published var busy = false { didSet { onBusyChanged?(busy) } }
  var onBusyChanged: ((Bool) -> Void)?
  private var previewTask: Task<Void, Never>?
  private var importTask: Task<Void, Never>?
  private var previewGeneration = UUID()
  private var importGeneration = UUID()
  init(_ document: CraftDocument, dataSets: Bool = false) {
    source = document; settings = document.variables ?? .init()
    layerID = document.activeLayerID ?? document.layers.first?.id
    rowID = settings.activeDataSetID ?? settings.dataSets.first?.id; tab = dataSets ? 1 : 0
  }
  var selectedLayer: Layer? { source.layers.first { $0.id == layerID } }
  func binding(_ kind: VariableKind) -> VariableDefinition? { settings.definitions.first { $0.layerID == layerID && $0.kind == kind } }
  func supports(_ kind: VariableKind) -> Bool {
    guard let layer = selectedLayer else { return false }
    return VariableDefinition(name: "Variable", layerID: layer.id, kind: kind).supports(layer)
  }
  func setEnabled(_ kind: VariableKind, _ enabled: Bool) {
    guard let layerID, supports(kind) else { return }
    if enabled, binding(kind) == nil {
      let stem = kind == .visibility ? "Visible" : kind == .textReplacement ? "Text" : "Image"
      var name = stem, suffix = 1
      while settings.variableNames.contains(name) { suffix += 1; name = stem + String(suffix) }
      settings.definitions.append(.init(name: name, layerID: layerID, kind: kind))
    } else if !enabled { settings.definitions.removeAll { $0.layerID == layerID && $0.kind == kind }; pruneValues() }
  }
  func rename(_ kind: VariableKind, _ name: String) {
    guard let index = settings.definitions.firstIndex(where: { $0.layerID == layerID && $0.kind == kind }) else { return }
    let old = settings.definitions[index].name
    settings.definitions[index].name = name
    for i in settings.dataSets.indices where settings.dataSets[i].values[name] == nil {
      settings.dataSets[i].values[name] = settings.dataSets[i].values[old]
    }
    pruneValues()
  }
  private func pruneValues() {
    let names = Dictionary(settings.definitions.map { ($0.name, $0.kind) }, uniquingKeysWith: { a, _ in a })
    for i in settings.dataSets.indices { settings.dataSets[i].values = settings.dataSets[i].values.filter { names[$0.key] == $0.value.kind } }
    if settings.definitions.isEmpty { settings.dataSets = []; rowID = nil }
    settings.activeDataSetID = nil
  }
  func setPixelOptions(_ options: VariablePixelOptions) {
    guard let i = settings.definitions.firstIndex(where: { $0.layerID == layerID && $0.kind == .pixelReplacement }) else { return }
    settings.definitions[i].pixelOptions = options
  }
  var selectedRow: VariableDataSet? { settings.dataSets.first { $0.id == rowID } }
  func setRowName(_ name: String) { if let i = settings.dataSets.firstIndex(where: { $0.id == rowID }) { settings.dataSets[i].name = name } }
  func setValue(_ value: VariableValue?, for name: String) {
    if let i = settings.dataSets.firstIndex(where: { $0.id == rowID }) { settings.dataSets[i].values[name] = value }
  }
  func addRow(duplicate: Bool = false) {
    guard !settings.definitions.isEmpty, settings.dataSets.count < DataDrivenGraphics.maximumDataSets else { return }
    var number = settings.dataSets.count + 1
    while settings.dataSets.contains(where: { $0.name == "Data Set \(number)" }) { number += 1 }
    var values = duplicate ? selectedRow?.values ?? [:] : [:]
    if !duplicate {
      for definition in settings.definitions where values[definition.name] == nil {
        guard let layer = source.layers.first(where: { $0.id == definition.layerID }) else { continue }
        switch definition.kind {
        case .visibility: values[definition.name] = .visibility(layer.visible)
        case .textReplacement: if case .text(let text) = layer.content { values[definition.name] = .text(text.text) }
        case .pixelReplacement: values[definition.name] = .pixels(nil)
        }
      }
    }
    let row = VariableDataSet(name: "Data Set \(number)", values: values)
    settings.dataSets.append(row); rowID = row.id
  }
  func deleteRow() { settings.dataSets.removeAll { $0.id == rowID }; rowID = settings.dataSets.first?.id; settings.activeDataSetID = nil }
  func command(apply: Bool) throws -> Command {
    let command = Command.variables(.configure(settings, apply: apply ? rowID : nil))
    var candidate = source; try command.apply(to: &candidate)
    return command
  }
  func refreshPreview() {
    previewTask?.cancel(); let generation = UUID(); previewGeneration = generation
    guard previewEnabled else { preview = nil; return }
    let original = source, draft = settings, selected = tab == 1 ? rowID : nil
    previewTask = Task {
      let worker = Task.detached(priority: .userInitiated) {
        var candidate = original
        try Command.variables(.configure(draft, apply: selected)).apply(to: &candidate)
        try Task.checkCancellation()
        return try ColorManagement.displayImage(Renderer.composite(candidate), in: candidate)
      }
      do {
        let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, self.previewGeneration == generation else { return }
        self.preview = NSImage(cgImage: image, size: .init(width: image.width, height: image.height)); self.error = nil
      } catch is CancellationError {} catch { if self.previewGeneration == generation { self.preview = nil; self.error = error.localizedDescription } }
    }
  }
  func cancel() { previewGeneration = UUID(); importGeneration = UUID(); previewTask?.cancel(); importTask?.cancel(); busy = false }
  func chooseImage(for name: String, window: NSWindow?) {
    guard !busy, let rowID else { return }
    let panel = NSOpenPanel(); panel.title = "Select Replacement Image"; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
    let finish: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK, let url = panel.url else { return }
      let original = self.source, generation = UUID(); self.importGeneration = generation; self.busy = true
      self.importTask = Task {
        defer { if self.importGeneration == generation { self.busy = false } }
        let worker = Task.detached(priority: .userInitiated) {
          let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          return try VariableGraphicsInput.image(Self.read(url, limit: VariableGraphicsInput.maximumImageFileBytes), name: url.lastPathComponent, for: original)
        }
        do {
          let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          guard !Task.isCancelled, self.importGeneration == generation, let index = self.settings.dataSets.firstIndex(where: { $0.id == rowID }) else { return }
          var candidate = self.settings; candidate.images.append(image); candidate.dataSets[index].values[name] = .pixels(image.id)
          var checked = original; try Command.variables(.configure(candidate, apply: nil)).apply(to: &checked)
          self.settings = checked.variables ?? .init(); self.error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
    if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
  }
  nonisolated static func read(_ url: URL, limit: Int) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    let data = try handle.read(upToCount: limit + 1) ?? Data()
    guard data.count <= limit else { throw CraftError.invalid("The selected file exceeds the import limit.") }
    return data
  }
  func chooseDataFile(window: NSWindow?) {
    guard !busy, !settings.definitions.isEmpty else { return }
    let panel = NSOpenPanel(); panel.title = "Import Variable Data Sets"; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
    let encoding = NSPopUpButton(), delimiter = NSPopUpButton()
    encoding.addItems(withTitles: ["Automatic", "UTF-8", "UTF-16 Little Endian", "UTF-16 Big Endian", "Mac Roman", "Windows Latin 1"])
    delimiter.addItems(withTitles: ["Comma (CSV)", "Tab (TSV)"])
    let names = NSButton(checkboxWithTitle: "Use First Column for Data Set Names", target: nil, action: nil)
    let replace = NSButton(checkboxWithTitle: "Replace Existing Data Sets", target: nil, action: nil); replace.state = .on
    let grid = NSGridView(views: [[NSTextField(labelWithString: "Encoding:"), encoding], [NSTextField(labelWithString: "Delimiter:"), delimiter], [NSTextField(labelWithString: ""), names], [NSTextField(labelWithString: ""), replace]])
    grid.rowSpacing = 8; grid.setFrameSize(grid.fittingSize); panel.accessoryView = grid
    panel.message = "Include every variable in the header. Image paths are resolved relative to this data file; imported images are embedded in the template."
    let finish: (NSApplication.ModalResponse) -> Void = { response in
      guard response == .OK, let url = panel.url else { return }
      var original = self.source
      do { try Command.variables(.configure(self.settings, apply: nil)).apply(to: &original) } catch { self.error = error.localizedDescription; return }
      var options = VariableDataImportOptions(); options.delimiter = delimiter.indexOfSelectedItem == 0 ? .comma : .tab
      options.firstColumnNames = names.state == .on; options.replaceExisting = replace.state == .on
      let input = original, importOptions = options, selectedEncoding = VariableTextEncoding.allCases[encoding.indexOfSelectedItem], generation = UUID()
      self.importGeneration = generation; self.busy = true
      self.importTask = Task {
        defer { if self.importGeneration == generation { self.busy = false } }
        let worker = Task.detached(priority: .userInitiated) {
          let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          return try VariableGraphicsInput.importing(Self.read(url, limit: DataDrivenGraphics.maximumMetadataBytes), encoding: selectedEncoding, options: importOptions, into: input) { path in
            let imageURL = (path as NSString).isAbsolutePath ? URL(fileURLWithPath: path) : url.deletingLastPathComponent().appendingPathComponent(path)
            return try Self.read(imageURL, limit: VariableGraphicsInput.maximumImageFileBytes)
          }
        }
        do {
          let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          guard !Task.isCancelled, self.importGeneration == generation else { return }
          self.settings = result; self.rowID = result.dataSets.first?.id; self.tab = 1; self.error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
      }
    }
    if let window { panel.beginSheetModal(for: window, completionHandler: finish) } else { panel.begin(completionHandler: finish) }
  }
}
