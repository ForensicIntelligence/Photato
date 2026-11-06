import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class BatchWorkspace {
  var sources: [ActionBatchSource] = []
  var results: [ActionBatchResult] = []
  var selected: UUID?
  var destination: URL?
  var format = DocumentIO.Format.png
  var quality = 0.9
  var suffix = "-processed"
  var naming = BatchFileNaming()
  var useLegacyNaming = false
  var stopOnError = false
  var busy = false
  var error: String?
  @ObservationIgnored var task: Task<Void, Never>?
  @ObservationIgnored var scopedURLs: [URL] = []
  let library: ActionLibrary
  weak var controller: CraftDocumentController?
  init(controller: CraftDocumentController, library: ActionLibrary = .shared) { self.controller = controller; self.library = library }
  func hold(_ url: URL) { if url.startAccessingSecurityScopedResource() { scopedURLs.append(url) } }
  func release() { for url in scopedURLs { url.stopAccessingSecurityScopedResource() }; scopedURLs = [] }
  func chooseSources(folder: Bool) {
    let panel = NSOpenPanel(); panel.canChooseDirectories = folder; panel.canChooseFiles = !folder; panel.allowsMultipleSelection = !folder
    if !folder { panel.allowedContentTypes = DocumentIO.readableContentTypes }
    panel.begin { [weak self] response in
      guard let self, !busy, response == .OK else { return }
      do {
        for url in panel.urls { hold(url) }
        let urls = try folder ? FileManager.default.contentsOfDirectory(at: panel.urls[0], includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]).filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }.sorted { $0.lastPathComponent < $1.lastPathComponent } : panel.urls
        guard sources.count + urls.count <= 256 else { throw CraftError.invalid("Choose at most 256 files.") }
        sources += urls.map { ActionBatchSource(url: $0) }; error = nil
      } catch { self.error = error.localizedDescription }
    }
  }
  func addOpen() {
    guard let documents = controller?.documents.compactMap({ $0 as? CraftNSDocument }), documents.allSatisfy(PhotomergeWorkspace.readable), sources.count + documents.count <= 256 else { error = "Finish open-document edits; choose at most 256 sources."; return }
    sources += documents.map { ActionBatchSource(document: $0.store.document) }
  }
  func chooseDestination() {
    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "Choose Output Folder"
    panel.begin { [weak self] response in guard let self, !busy, response == .OK, let url = panel.url else { return }; hold(url); destination = url }
  }
  func run() {
    guard !busy, let selected, let destination else { return }
    do {
      let action = try library.action(selected), sources = sources, format = format, suffix = suffix, stop = stopOnError
      var selectedNaming = useLegacyNaming ? nil:naming
      selectedNaming?.date = Date()
      let options = RasterEncodingOptions(jpegQuality: format == .jpeg ? Int((quality * 12).rounded()) : nil)
      let input = try action.requiresInitialClipboard ? SystemClipboard.shared.read() : nil
      busy = true; results = []; error = nil
      task = Task { [weak self] in
        guard let self else { return }
        defer { busy = false; task = nil }
        do {
          let decoder = Task.detached(priority: .userInitiated) { try input?.decoded() }
          let clipboard = try await withTaskCancellationHandler { try await decoder.value } onCancel: { decoder.cancel() }
          results = try await ActionBatch.run(sources: sources, action: action, destination: destination, format: format, options: options, suffix: suffix, naming:selectedNaming, stopOnError: stop, clipboard: clipboard, progress: { self.results = $0 }) }
        catch { self.error = error.localizedDescription }
      }
    } catch { self.error = error.localizedDescription }
  }
}
struct BatchPanel: View {
  @Bindable var model: BatchWorkspace
  var body: some View {
    ScrollView {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Action", selection: $model.selected) { Text("Choose an action").tag(nil as UUID?); ForEach(model.library.file.actions) { Text("\($0.set) / \($0.name)").tag(Optional($0.id)) } }.disabled(model.busy)
      HStack { Button("Files…") { model.chooseSources(folder: false) }; Button("Folder…") { model.chooseSources(folder: true) }; Button("Opened Files") { model.addOpen() }; Button("Clear") { model.sources = []; model.results = [] } }.disabled(model.busy)
      Text("\(model.sources.count) sources").font(.caption)
      List {
        ForEach(model.sources) { source in
          HStack {
            Text(source.name); Spacer()
            if let result = model.results.first(where: { $0.id == source.id }) {
              Text(result.output ?? result.error ?? "Cancelled").font(.caption).foregroundStyle(result.output == nil ? .orange : .secondary)
            } else if !model.busy { Button { model.sources.removeAll { $0.id == source.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless) }
          }
        }
      }.frame(height: 180)
      HStack { Button("Destination…") { model.chooseDestination() }; Text(model.destination?.lastPathComponent ?? "Choose an output folder") }.disabled(model.busy)
      HStack {
        Picker("Format", selection: $model.format) { ForEach(DocumentIO.Format.allCases, id: \.self) { Text($0.title).tag($0) } }
        Toggle("Numbered copies",isOn:$model.useLegacyNaming)
        if model.useLegacyNaming {TextField("Filename suffix",text:$model.suffix)}
      }.disabled(model.busy)
      if !model.useLegacyNaming {BatchNamingControls(model:model).disabled(model.busy)}
      if model.format == .jpeg { HStack { Text("JPEG quality"); Slider(value: $model.quality, in: 0...1); Text("\(Int(model.quality * 100))%") }.disabled(model.busy) }
      Text(model.format.copyDescription).font(.caption).foregroundStyle(.secondary)
      Toggle("Stop on first error", isOn: $model.stopOnError).disabled(model.busy)
      Text("Existing output names report an error. Batch creates new files from source snapshots.").font(.caption).foregroundStyle(.secondary)
      if let error = model.error { Text(error).foregroundStyle(.red) }
      HStack {
        if model.busy { ProgressView(value: Double(model.results.count), total: Double(max(1, model.sources.count))); Button("Cancel") { model.task?.cancel() } }
        else { Text("\(model.results.filter { $0.output != nil }.count) completed · \(model.results.filter { $0.error != nil && !$0.cancelled }.count) errors"); Spacer(); Button("Run") { model.run() }.disabled(model.selected == nil || model.destination == nil || model.sources.isEmpty) }
      }
    }.padding(18)
    }.frame(minWidth: 560, minHeight: 500, idealHeight: 620, maxHeight: .infinity)
  }
}
@MainActor final class BatchWindow: NSWindowController, NSWindowDelegate {
  let model: BatchWorkspace
  init(model: BatchWorkspace) {
    self.model = model
    let window = PhotatoWindow(contentRect: NSRect(x: 170, y: 170, width: 680, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Batch"; window.isReleasedWhenClosed = false; window.contentView = NSHostingView(rootView: BatchPanel(model: model)); window.appearance = NSAppearance(named: .darkAqua)
    super.init(window: window); window.delegate = self
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func windowShouldClose(_ sender: NSWindow) -> Bool { if model.busy { model.task?.cancel(); return false }; return true }
  func windowWillClose(_ notification: Notification) { model.release(); model.sources = []; model.destination = nil }
}
@MainActor extension AppDelegate {
  @objc func showBatch() {
    if batchWindow == nil { batchWindow = BatchWindow(model: BatchWorkspace(controller: controller)) }
    batchWindow?.showWindow(nil)
  }
}
