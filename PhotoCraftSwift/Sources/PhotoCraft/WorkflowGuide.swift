import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

struct WorkflowGuideSnapshot: Equatable {
  var documentID: UUID?
  var layerID: UUID?
  var layerName = ""
  var layerCount = 0
  var selectedLayerCount = 0
  var isRaster = false
  var isBackground = false
  var isLocked = false
  var canTransform = false
  var canChangeOpacity = false
  var hasMask = false
  var editingMask = false
  var hasSelection = false
  var selectionBounds: IntRect?
  var savedChannelCount = 0
  var layerVisible = false
  var layerOpacity: Float = 0
  var tool: EditorTool = .move
  var zoom = 0.0
  var brushSize = 0.0
  var brushHardness = 0.0
  var brushOpacity = 0.0
  var selectionFeather = 0.0
  var antiAlias = false
  var sampleAllLayers = false
  var autoSelect = false
  var layerBounds = false
  var showsRulers = false
  var transformOpen = false
  var cropOpen = false

  @MainActor static func capture(_ store: EditorStore?) -> Self {
    var state = Self()
    guard let store else { return state }
    let document = store.document
    let layer = document.activeIndex.map { document.layers[$0] }
    state.documentID = store.identity
    state.layerID = layer?.id
    state.layerName = layer?.name ?? ""
    state.layerCount = document.layers.count
    state.selectedLayerCount = max(layer == nil ? 0 : 1, store.selectedLayerIDs.count)
    if let layer, case .raster = layer.content { state.isRaster = true }
    state.isBackground = layer?.isBackground == true
    state.isLocked = layer.map { document.isLocked($0.id) } ?? false
    state.canTransform = document.selection == nil && !store.editingMask && !store.editingComponent
      && store.editingChannel == nil && store.canTransformActiveLayer
    state.canChangeOpacity = store.canBeginLayerOpacity
    state.hasMask = layer?.mask != nil
    state.editingMask = store.editingMask
    state.hasSelection = document.selection != nil
    state.selectionBounds = document.selection
    state.savedChannelCount = document.alphaChannels?.count ?? 0
    state.layerVisible = layer?.visible == true
    state.layerOpacity = layer?.opacity ?? 0
    state.tool = store.tool
    state.zoom = store.zoom
    state.brushSize = Double(store.brush.size)
    state.brushHardness = Double(store.brush.hardness)
    state.brushOpacity = Double(store.brush.opacity)
    state.selectionFeather = store.selectionFeather
    state.antiAlias = store.selectionAntiAlias
    state.sampleAllLayers = store.selectionSampleAllLayers
    state.autoSelect = store.autoSelect
    state.layerBounds = store.showLayerBounds
    state.showsRulers = store.showRulers
    state.transformOpen = store.transformDraft != nil
    state.cropOpen = store.cropDraft != nil
    return state
  }

  func observed(_ check: WorkflowGuideStep.Check, since baseline: Self) -> Bool {
    switch check {
    case .layerSelected: layerID != nil
    case .layerAdded: layerCount > baseline.layerCount
    case .opacityChanged: layerID == baseline.layerID && layerOpacity != baseline.layerOpacity
    case .visibilityChanged: layerID == baseline.layerID && layerVisible != baseline.layerVisible
    case .maskAvailable: hasMask
    case .maskEditing: editingMask
    case .selectionExists: hasSelection
    case .selectionCleared: !hasSelection
    case .selectionSaved: savedChannelCount > baseline.savedChannelCount
    case .brushTool: tool == .brush
    case .cropTool: tool == .crop
    case .transformOpen: transformOpen
    case .zoomChanged: zoom != baseline.zoom
    }
  }
}

@MainActor @Observable final class WorkflowGuideModel {
  struct Walkthrough {
    let lesson: WorkflowGuideLesson
    let documentID: UUID
    var index = 0
    var baseline: WorkflowGuideSnapshot
    var step: WorkflowGuideStep { lesson.steps[index] }
  }

  private(set) var snapshot = WorkflowGuideSnapshot()
  private(set) var context = WorkflowGuideContext.document
  private(set) var caption = "Open a document to see suggested workflows."
  private(set) var walkthrough: Walkthrough?
  var suggestions: [WorkflowGuideLesson] {
    let contextual = WorkflowGuideContent.suggestions(for: context, state: snapshot)
    return contextual.isEmpty ? WorkflowGuideContent.suggestions(for: .document, state: snapshot) : contextual
  }
  var onLessonDocument: Bool {
    walkthrough.map { $0.documentID == snapshot.documentID } ?? false
  }
  var stepObserved: Bool {
    guard onLessonDocument, let walk = walkthrough, let check = walk.step.check else { return false }
    return snapshot.observed(check, since: walk.baseline)
  }

  func update(_ value: WorkflowGuideSnapshot) {
    let old = snapshot
    guard old != value else { return }
    snapshot = value
    if old.documentID != value.documentID {
      if value.layerID != nil { showLayer(value) }
      else {
        context = .document
        caption = value.documentID == nil ? "Open a document to see suggested workflows." : "Document active"
      }
    } else if old.layerID != value.layerID || old.selectedLayerCount != value.selectedLayerCount {
      showLayer(value)
    } else if old.tool != value.tool {
      showTool(value.tool)
    } else if old.editingMask != value.editingMask || old.hasMask != value.hasMask {
      note(.mask, value.editingMask ? "Editing the layer mask" : "Layer mask changed")
    } else if old.hasSelection != value.hasSelection || old.selectionBounds != value.selectionBounds {
      note(.selection, value.hasSelection ? "Pixels selected" : "Selection cleared")
    } else if old.savedChannelCount != value.savedChannelCount {
      note(.channels, "Saved channels changed")
    } else if old.transformOpen != value.transformOpen {
      note(.transform, value.transformOpen ? "Free Transform active" : "Free Transform closed")
    } else if old.cropOpen != value.cropOpen {
      note(.crop, value.cropOpen ? "Crop active" : "Crop closed")
    } else if old.layerOpacity != value.layerOpacity {
      note(.layer, "Layer opacity changed")
    } else if old.layerVisible != value.layerVisible {
      note(.layer, value.layerVisible ? "Layer shown" : "Layer hidden")
    } else if old.autoSelect != value.autoSelect || old.layerBounds != value.layerBounds {
      note(.layer, "Move options changed")
    } else if old.selectionFeather != value.selectionFeather || old.antiAlias != value.antiAlias
      || old.sampleAllLayers != value.sampleAllLayers {
      note(.selection, "Selection options changed")
    } else if old.brushSize != value.brushSize || old.brushHardness != value.brushHardness
      || old.brushOpacity != value.brushOpacity {
      note(.brush, "Brush options changed")
    } else if old.zoom != value.zoom || old.showsRulers != value.showsRulers {
      note(.navigation, old.zoom != value.zoom ? "Canvas zoom changed" : "Ruler visibility changed")
    }
  }

  func showLayer(_ value: WorkflowGuideSnapshot) {
    snapshot = value
    if value.selectedLayerCount > 1 {
      note(.layer, "\(value.selectedLayerCount) layers selected")
    } else if value.layerID != nil {
      note(.layer, "Selected layer · \(value.layerName)")
    } else {
      note(.document, value.documentID == nil ? "Open a document to see suggested workflows." : "No layer selected")
    }
  }

  func showTool(_ tool: EditorTool) {
    note(WorkflowGuideContext(tool: tool), "\(tool.rawValue) tool")
  }

  func note(_ view: WorkflowGuideContext, _ title: String) {
    if context != view { context = view }
    if caption != title { caption = title }
  }

  func start(_ lesson: WorkflowGuideLesson) {
    guard let documentID = snapshot.documentID, suggestions.contains(lesson), !lesson.steps.isEmpty else { return }
    walkthrough = Walkthrough(lesson: lesson, documentID: documentID, baseline: snapshot)
  }

  func next() {
    guard onLessonDocument, var walk = walkthrough else { return }
    if walk.index == walk.lesson.steps.count - 1 { end(); return }
    walk.index += 1
    walk.baseline = snapshot
    walkthrough = walk
  }

  func back() {
    guard onLessonDocument, var walk = walkthrough, walk.index > 0 else { return }
    walk.index -= 1
    walk.baseline = snapshot
    walkthrough = walk
  }

  func end() { walkthrough = nil }
}

struct WorkflowGuideView: View {
  let model: WorkflowGuideModel
  let current: () -> WorkflowGuideSnapshot

  var body: some View {
    let state = current()
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        if let walk = model.walkthrough {
          Text(walk.lesson.title).font(.headline).accessibilityAddTraits(.isHeader)
          if model.onLessonDocument {
            Text("Step \(walk.index + 1) of \(walk.lesson.steps.count)")
              .font(.subheadline).foregroundStyle(.secondary)
            Text(walk.step.instruction).fixedSize(horizontal: false, vertical: true)
            if model.stepObserved {
              Label("Verified in the editor", systemImage: "checkmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack {
              Button("Back", action: model.back).disabled(walk.index == 0)
              Spacer()
              Button(walk.index == walk.lesson.steps.count - 1 ? "Done" : "Next", action: model.next)
            }
          } else {
            Text("Switch back to the document where you started this guide, or end it to get suggestions here.")
              .fixedSize(horizontal: false, vertical: true)
          }
          if let step = walk.lesson.diaryStep,
            let link = URL(string: "https://github.com/ForensicIntelligence/Photato/blob/main/PhotoCraftSwift/docs/DEVLOG.md#dev-step-\(step)") {
            Link("Development diary", destination: link)
          }
          Button("End Guide", action: model.end).buttonStyle(.link)
        } else {
          Text(model.caption).font(.headline).accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
          if !model.suggestions.isEmpty {
            Divider()
            ForEach(model.suggestions) { lesson in
              Button {
                model.start(lesson)
              } label: {
                HStack {
                  Text(lesson.title).fixedSize(horizontal: false, vertical: true)
                  Spacer()
                  Image(systemName: "chevron.forward").accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .buttonStyle(.bordered)
              .controlSize(.large)
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
    }
    .frame(minWidth: 280, minHeight: 185)
    .onChange(of: state, initial: true) { _, value in model.update(value) }
  }
}

@MainActor final class WorkflowGuideWindow: NSWindowController, NSWindowDelegate {
  let model = WorkflowGuideModel()
  private weak var documents: CraftDocumentController?

  init(documents: CraftDocumentController) {
    self.documents = documents
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 285),
      styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
    super.init(window: panel)
    panel.title = "Workflow Guide"
    panel.identifier = NSUserInterfaceItemIdentifier("photato.workflowGuide")
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.isExcludedFromWindowsMenu = true
    panel.isReleasedWhenClosed = false
    panel.contentMinSize = NSSize(width: 280, height: 185)
    panel.collectionBehavior = [.fullScreenAuxiliary]
    panel.delegate = self
    if !panel.setFrameUsingName("PhotatoWorkflowGuide"),
      let frame = documents.documentWindows.current?.window?.frame,
      let screen = documents.documentWindows.current?.window?.screen?.visibleFrame {
      panel.setFrameTopLeftPoint(NSPoint(x: max(screen.minX, min(screen.maxX - 340, frame.maxX - 355)),
        y: min(screen.maxY, frame.maxY - 42)))
    }
    panel.setFrameAutosaveName("PhotatoWorkflowGuide")
    panel.contentViewController = NSHostingController(rootView: WorkflowGuideView(model: model) { [weak documents] in
      WorkflowGuideSnapshot.capture(documents?.documentWindows.activeDocument?.store)
    })
  }

  required init?(coder: NSCoder) { nil }

  func open() {
    guard let window, !window.isVisible else { return }
    documents?.workflowGuide = model
    model.update(.capture(documents?.documentWindows.activeDocument?.store))
    NotificationCenter.default.addObserver(self, selector: #selector(menuAction(_:)),
      name: NSMenu.didSendActionNotification, object: nil)
    window.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    NotificationCenter.default.removeObserver(self, name: NSMenu.didSendActionNotification, object: nil)
    if documents?.workflowGuide === model { documents?.workflowGuide = nil }
    model.end()
  }

  @objc private func menuAction(_ notification: Notification) {
    guard let item = notification.userInfo?["MenuItem"] as? NSMenuItem,
      let path = item.identifier?.rawValue, let context = WorkflowGuideContext.menu(path)
    else { return }
    model.update(.capture(documents?.documentWindows.activeDocument?.store))
    model.note(context, item.title)
  }
}

@MainActor extension AppDelegate {
  @objc func toggleWorkflowGuide() {
    if let panel = workflowGuideWindow?.window, panel.isVisible { panel.close(); return }
    if workflowGuideWindow == nil { workflowGuideWindow = WorkflowGuideWindow(documents: controller) }
    workflowGuideWindow?.open()
  }
}
