import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor struct ChannelMergeFence {
  let files: [CraftNSDocument]
  let models: [CraftDocument]
  let panels: [UUID]
  let sessions: [UUID]
  let settings: ColorSettings
  let opening: UUID
  let closing: UUID?
  let maintenance: UUID
  let discovery: UUID
  init(_ files: [CraftNSDocument], controller: CraftDocumentController) {
    self.files = files; models = files.map { $0.store.document }
    panels = files.map { $0.store.layerPanelGeneration }; sessions = files.map { $0.store.sessionGeneration }
    settings = controller.colorSettings.value; opening = controller.documentOpening.generation
    closing = controller.documentClosing.state?.id; maintenance = controller.recoveryMaintenance.generation
    discovery = controller.recoveryDiscovery.generation
  }
  func isCurrent(_ controller: CraftDocumentController, sheet: NSWindow? = nil) -> Bool {
    !controller.documentOpening.isActive && !controller.documentOpening.hasPendingRequests && controller.documentOpenPanel == nil
      && controller.documentOpening.generation == opening && !controller.documentClosing.isActive
      && controller.documentClosing.state?.id == closing && !controller.recoveryIndex.isBusy
      && controller.initialRecoveryTask == nil && controller.recoveryMaintenance.generation == maintenance
      && controller.recoveryDiscovery.generation == discovery && controller.colorSettings.value == settings
      && NSApp?.modalWindow == nil && files.indices.allSatisfy { i in
        let file = files[i], store = file.store
        return file.ownerController === controller && store.document == models[i]
          && store.layerPanelGeneration == panels[i] && store.sessionGeneration == sessions[i]
          && !file.recoveryWriteBusy && !file.fileOperationBusy && file.closeWorkflowID == nil
          && !store.aiBusy && !store.hasToneDraft && store.transformDraft == nil && !store.coalescingChanges
          && store.numericEditor == nil && store.layerNameDraft == nil && store.pathGesture == nil
          && store.error == nil && (file.windowForSheet?.attachedSheet == nil || file.windowForSheet?.attachedSheet === sheet)
      }
  }
  func lock(_ task: Task<Void,Never>) {
    for file in files { file.store.geometryBusy = true; file.store.renderTask?.cancel(); file.store.geometryTask = task }
  }
  func unlock() {
    for i in files.indices where files[i].store.layerPanelGeneration == panels[i] {
      files[i].store.geometryBusy = false; files[i].store.geometryTask = nil; files[i].store.render()
    }
  }
}

@MainActor extension CraftDocumentController {
  var canStartChannelMerge: Bool { channelMergeWorkspace == nil && imageStackWorkspace == nil && contactSheetWorkspace == nil && hdrMergeWorkspace == nil && photomergeWorkspace == nil && scanCropOperationID == nil && documentClosing.canStart([]) }
  func channelMergeCandidates(for anchor: CraftNSDocument) -> [CraftNSDocument] {
    guard ChannelMerge.unavailableReason(anchor.store.document) == nil else { return [] }
    return documents.compactMap { $0 as? CraftNSDocument }.filter {
      $0.canRunFileCommand && $0.store.canBeginLayerCreation && $0.store.numericEditor == nil && $0.store.layerNameDraft == nil
        && ChannelMerge.matches($0.store.document, anchor: anchor.store.document)
    }
  }
  @discardableResult func publishChannelMerge(_ plan: PreparedChannelMerge, sources: [CraftNSDocument],
    display: Bool = true, register: (CraftNSDocument) throws -> Void = { _ in }) throws -> CraftNSDocument {
    guard !sources.isEmpty, sources.map({ $0.store.document }) == plan.sources,
      Set(sources.map(ObjectIdentifier.init)).count == sources.count,
      !sources.contains(where: { $0.store.document.id == plan.document.id }), documentClosing.canStart(sources) else {
      throw CraftError.invalid("Merge Channels sources or document lifecycle changed.")
    }
    try plan.document.validate()
    guard let first = plan.sources.first, plan.document.width == first.width, plan.document.height == first.height,
      plan.document.depth == first.depth else { throw CraftError.invalid("Invalid merged channel document.") }
    let result = CraftNSDocument(model: plan.document)
    addDocument(result)
    do { try register(result) } catch { result.close(); throw error }
    result.updateChangeCount(.changeDone)
    for source in sources { source.close() }
    assert(sources.allSatisfy { $0.ownerController == nil })
    if display { documentWindows.presentAfterCurrentSheet(result) }
    return result
  }
}

@MainActor extension EditorStore {
  var mergeChannelAnchor: CraftNSDocument? { documentController?.documents.compactMap { $0 as? CraftNSDocument }.first { $0.store === self } }
  var canMergeChannels: Bool {
    guard canBeginLayerCreation, let controller = documentController, controller.canStartChannelMerge,
      let anchor = mergeChannelAnchor else { return false }
    return controller.channelMergeCandidates(for: anchor).count >= (document.depth == .f32 ? 3 : 2)
  }
  func beginMergeChannels() {
    finishNumericField(); finishLayerName()
    guard canMergeChannels, let controller = documentController, let anchor = mergeChannelAnchor,
      let window = anchor.windowForSheet else { return }
    let model = ChannelMergeWorkspace(controller: controller, anchor: anchor)
    controller.channelMergeWorkspace = model
    model.present(on: window)
  }
}

@MainActor @Observable final class ChannelMergeWorkspace {
  let sources: [CraftNSDocument]
  let snapshots: [CraftDocument]
  weak var controller: CraftDocumentController?
  weak var anchor: CraftNSDocument?
  var mode: ChannelMergeMode
  var countText: String
  var assignments: [Int]
  var stage = 0
  var error: String?
  var busy = false
  @ObservationIgnored var panel: NSPanel?
  @ObservationIgnored var task: Task<Void,Never>?
  @ObservationIgnored private var worker: Task<PreparedChannelMerge,Error>?
  @ObservationIgnored private var fence: ChannelMergeFence?
  @ObservationIgnored private var prepared: PreparedChannelMerge?
  private var closed = false
  let depth: PixelDepth
  var count: Int { mode == .multichannel ? Int(countText) ?? 0 : mode.components.count }
  var titles: [String] { sources.map { $0.displayName ?? $0.store.document.name } }
  init(controller: CraftDocumentController, anchor: CraftNSDocument) {
    self.controller = controller; self.anchor = anchor; depth = anchor.store.document.depth
    sources = controller.channelMergeCandidates(for: anchor); snapshots = sources.map { $0.store.document }
    mode = anchor.store.document.depth == .f32 ? .rgb : .multichannel
    countText = String(anchor.store.document.depth == .f32 ? 3 : min(56, sources.count)); assignments = Array(0..<sources.count)
  }
  func present(on window: NSWindow) {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260), styleMask: [.titled], backing: .buffered, defer: false)
    panel.title = "Merge Channels"; panel.isReleasedWhenClosed = false
    panel.contentView = NSHostingView(rootView: ChannelMergeView(model: self)); self.panel = panel
    window.beginSheet(panel) { [weak self] response in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.panel = nil
        if response == .OK {
          // AppKit may still expose attachedSheet while invoking this callback.
          // Publish on the next main-actor turn and revalidate all sources there.
          self.task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { self?.close(); return }
            self?.publish()
          }
        } else { self.close() }
      }
    }
  }
  func advance() {
    error = nil
    guard mode.accepts(count: count, depth: depth), count <= sources.count else {
      error = "Choose \(mode == .multichannel ? "2–\(min(56, sources.count))" : String(mode.components.count)) channels from the eligible documents."; return
    }
    if stage == 0 { assignments = Array(0..<count); stage = 1; return }
    if mode == .multichannel && stage < count { stage += 1; return }
    guard Set(assignments.prefix(count)).count == count else { error = "A document cannot be selected for more than one channel."; return }
    prepare()
  }
  func cancel() {
    worker?.cancel(); task?.cancel()
    if let panel, let parent = panel.sheetParent { parent.endSheet(panel, returnCode: .cancel) }
    else { close() }
  }
  func close() {
    closed = true; worker?.cancel(); task?.cancel(); fence?.unlock(); fence = nil
    if controller?.channelMergeWorkspace === self { controller?.channelMergeWorkspace = nil }
  }
  private func prepare() {
    guard let controller, let anchor, !closed, !busy else { return }
    let selected = assignments.prefix(count).map { sources[$0] }
    guard sources.indices.allSatisfy({ sources[$0].store.document == snapshots[$0] }) else { error = "A source changed. Cancel and reopen Merge Channels."; return }
    let files = selected.contains(where: { $0 === anchor }) ? selected : selected + [anchor]
    let fence = ChannelMergeFence(files, controller: controller)
    guard fence.isCurrent(controller, sheet: panel), files.allSatisfy({ !$0.store.geometryBusy }) else { error = "Finish the source document operation first."; return }
    let models = selected.map { $0.store.document }, mode = mode, name = controller.nextUntitledName, prepare = anchor.store.mergeChannelsPreparation
    do {
      let profile = try mode == .multichannel ? nil : fence.settings.profile(mode.colorMode, depth: depth)
      busy = true; self.fence = fence
      let worker = Task.detached(priority: .userInitiated) { try prepare(models, mode, profile, name) }; self.worker = worker
      let task = Task { [weak self] in
        do {
          let plan = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
          try Task.checkCancellation()
          guard let self, !self.closed, fence.isCurrent(controller, sheet: self.panel), let panel = self.panel, let parent = panel.sheetParent else { throw CraftError.invalid("Merge Channels was cancelled or a source changed.") }
          self.prepared = plan; parent.endSheet(panel, returnCode: .OK)
        } catch {
          guard let self, !self.closed else { return }
          fence.unlock(); self.fence = nil; self.busy = false
          if !(error is CancellationError) { self.error = error.localizedDescription }
        }
      }
      self.task = task; fence.lock(task)
    } catch { self.error = error.localizedDescription }
  }
  private func publish() {
    guard let controller, let plan = prepared, let fence else { close(); return }
    defer { close() }
    do {
      guard fence.isCurrent(controller), !closed else { throw CraftError.invalid("Merge Channels source or lifecycle changed.") }
      fence.unlock(); self.fence = nil
      controller.channelMergeWorkspace = nil
      let selected = assignments.prefix(count).map { sources[$0] }
      _ = try controller.publishChannelMerge(plan, sources: selected)
    } catch { anchor?.store.error = error.localizedDescription }
  }
}

private struct ChannelMergeView: View {
  @Bindable var model: ChannelMergeWorkspace
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if model.stage == 0 {
        HStack {
          Text("Mode:")
          ChannelMergeModePicker(selection:$model.mode, sourceCount:model.sources.count, depth:model.depth)
        }
        HStack { Text("Channels:"); TextField("Channels", text: $model.countText).frame(width: 70).disabled(model.mode != .multichannel || model.depth == .f32) }
      } else if model.mode == .multichannel {
        Text("Specify Channel \(model.stage):")
        sourcePicker("Image:", index: model.stage - 1)
      } else {
        ForEach(Array(model.mode.components.enumerated()), id: \.offset) { index, label in sourcePicker(label + ":", index: index) }
      }
      if model.busy { ProgressView("Merging Channels…").controlSize(.small) }
      if let error = model.error { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).accessibilityLabel("Merge Channels: " + error) }
      HStack {
        if model.stage > 0 { Button("Mode") { model.stage = 0; model.error = nil }.disabled(model.busy) }
        Spacer()
        Button("Cancel") { model.cancel() }.keyboardShortcut(.cancelAction)
        Button(model.mode == .multichannel && model.stage > 0 && model.stage < model.count ? "Next" : "OK") { model.advance() }.keyboardShortcut(.defaultAction).disabled(model.busy)
      }
    }.padding(20).frame(width: 420)
      .onChange(of: model.mode) { _, value in if value != .multichannel { model.countText = String(value.components.count) } }
  }
  private func sourcePicker(_ title: String, index: Int) -> some View {
    Picker(title, selection: $model.assignments[index]) {
      ForEach(model.sources.indices, id: \.self) { i in Text(model.titles[i]).tag(i).help(model.titles[i]) }
    }.disabled(model.busy)
  }
}

private struct ChannelMergeModePicker: NSViewRepresentable {
  @Binding var selection: ChannelMergeMode
  let sourceCount: Int
  let depth: PixelDepth
  func makeCoordinator() -> Coordinator { Coordinator(selection:$selection) }
  func makeNSView(context: Context) -> NSPopUpButton {
    let view = NSPopUpButton(frame:.zero,pullsDown:false)
    view.addItems(withTitles:ChannelMergeMode.allCases.map(\.title))
    view.menu?.autoenablesItems = false
    view.font = .systemFont(ofSize:NSFont.systemFontSize)
    view.setAccessibilityLabel("Mode")
    view.target = context.coordinator; view.action = #selector(Coordinator.selectMode(_:))
    return view
  }
  func updateNSView(_ view: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection
    for (index,mode) in ChannelMergeMode.allCases.enumerated() {
      view.item(at:index)?.isEnabled = mode.canChoose(sourceCount:sourceCount,depth:depth)
    }
    if let index = ChannelMergeMode.allCases.firstIndex(of:selection) { view.selectItem(at:index) }
  }
  @MainActor final class Coordinator: NSObject {
    var selection: Binding<ChannelMergeMode>
    init(selection: Binding<ChannelMergeMode>) { self.selection = selection }
    @objc func selectMode(_ sender: NSPopUpButton) {
      guard ChannelMergeMode.allCases.indices.contains(sender.indexOfSelectedItem), sender.selectedItem?.isEnabled == true else { return }
      selection.wrappedValue = ChannelMergeMode.allCases[sender.indexOfSelectedItem]
    }
  }
}
