import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PhotoBlendWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  let layerIDs: Set<UUID>
  var settings = PhotoBlendSettings()
  var image: CGImage?
  var originalImage: CGImage?
  var preview = true
  var rendering = false
  var error: String?
  var edit: PhotoBlendEdit?
  @ObservationIgnored var task: Task<Void,Never>?
  private var generation = 0
  private var closed = false
  var ready: Bool { edit != nil && !rendering && error == nil }
  init(source: CraftDocument,layerIDs: Set<UUID>) { self.source = source;self.layerIDs = layerIDs }
  func refresh() {
    task?.cancel();edit = nil;error = nil;rendering = true;generation += 1
    let token = generation,options = settings,source = source,ids = layerIDs,needOriginal = originalImage == nil
    task = Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(60))
        let worker = Task.detached(priority:.userInitiated) { () throws -> (PhotoBlendEdit,CGImage,CGImage?) in
          let edit = try PhotoBlend.prepare(source,layerIDs:ids,settings:options)
          let image = try ColorManagement.displayImage(Renderer.composite(edit.result),in:source)
          let before = needOriginal ? try ColorManagement.displayImage(Renderer.composite(source),in:source):nil
          return (edit,image,before)
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation();guard let self,!self.closed,self.generation == token else { return }
        self.edit = result.0;self.image = result.1;if let before = result.2 { self.originalImage = before };self.rendering = false
      } catch {
        guard let self,!self.closed,self.generation == token else { return }
        self.rendering = false;if !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  func close() { closed = true;generation += 1;task?.cancel();task = nil;rendering = false }
}
struct PhotoBlendSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: PhotoBlendWorkspace
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Auto-Blend Layers").font(.headline)
      HStack(alignment:.top,spacing:18) {
        ZStack {
          Color.black.opacity(0.2)
          if let image = model.preview ? model.image:model.originalImage { Image(decorative:image,scale:1).resizable().scaledToFit() }
          if model.rendering { ProgressView() }
        }.frame(minWidth:420,minHeight:300)
        VStack(alignment:.leading,spacing:14) {
          GroupBox("Blend Method") {
            Picker("Method",selection:$model.settings.method) {
              Text("Panorama").tag(PhotoBlendSettings.Method.panorama)
              Text("Stack Images").tag(PhotoBlendSettings.Method.stack)
            }.pickerStyle(.radioGroup).labelsHidden().padding(6)
          }
          Toggle("Seamless Tones and Colors",isOn:$model.settings.seamlessTones)
          Toggle("Content Aware Fill Transparent Areas",isOn:$model.settings.fillTransparentAreas)
          Text(model.settings.method == .stack ? "Combine the sharpest regions of aligned photos into one focus stack.":"Blend overlapping, aligned layers into a panorama.").font(.caption).foregroundStyle(.secondary)
          Text("Sources keep editable masks and color corrections. Transparent-area fill adds a merged layer; translucent sources are hidden to avoid doubling their alpha.").font(.caption).foregroundStyle(.secondary)
          Toggle("Preview",isOn:$model.preview)
        }.frame(width:260)
      }
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
      HStack {
        Text("\(model.layerIDs.count) selected layers").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { store.cancelPhotoBlend() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitPhotoBlend() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:760,height:460)
      .onChange(of:model.settings) { _,_ in model.refresh() }
      .task { if model.edit == nil { model.refresh() } }
      .onDisappear { model.close() }
  }
}
extension EditorStore {
  var canBeginPhotoBlend: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingMask && !editingComponent
      && (try? PhotoBlend.targets(layoutSelection,in:document)) != nil
  }
  func beginPhotoBlend() {
    guard canBeginPhotoBlend else { return }
    photoBlendDraft = PhotoBlendWorkspace(source:document,layerIDs:layoutSelection)
  }
  func cancelPhotoBlend() { photoBlendDraft?.close();photoBlendDraft = nil }
  func commitPhotoBlend() {
    guard let draft = photoBlendDraft,draft.ready,let edit = draft.edit else { return }
    cancelPhotoBlend()
    performGeometry(.photoBlend(edit),onSuccess:{ [weak self] in
      guard let self else { return };self.selectedLayerIDs = edit.selectedLayerIDs
    })
  }
}
extension AppDelegate { @objc func autoBlendLayers() { store?.beginPhotoBlend() } }
