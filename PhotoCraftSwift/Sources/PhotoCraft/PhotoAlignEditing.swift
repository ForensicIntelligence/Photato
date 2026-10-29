import AppKit
import SwiftUI
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PhotoAlignWorkspace: Identifiable {
  let id = UUID()
  let source: CraftDocument
  let layerIDs: Set<UUID>
  var settings = PhotoAlignSettings()
  var image: CGImage?
  var originalImage: CGImage?
  var preview = true
  var rendering = false
  var error: String?
  var edit: PhotoAlignEdit?
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
        let worker = Task.detached(priority:.userInitiated) { () throws -> (PhotoAlignEdit,CGImage,CGImage?) in
          let edit = try PhotoAlign.prepare(source,layerIDs:ids,settings:options)
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
struct PhotoAlignSheet: View {
  @Bindable var store: EditorStore
  @Bindable var model: PhotoAlignWorkspace
  var body: some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Auto-Align Layers").font(.headline)
      HStack(alignment:.top,spacing:18) {
        ZStack {
          Color.black.opacity(0.2)
          if let image = model.preview ? model.image:model.originalImage { Image(decorative:image,scale:1).resizable().scaledToFit() }
          if model.rendering { ProgressView() }
        }.frame(minWidth:420,minHeight:300)
        VStack(alignment:.leading,spacing:14) {
          GroupBox("Projection") {
            Picker("Projection",selection:$model.settings.projection) {
              ForEach(PhotoAlignSettings.Projection.allCases,id:\.self) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup).labelsHidden().padding(6)
          }
          Picker("Reference",selection:$model.settings.referenceLayerID) {
            Text("Automatic").tag(UUID?.none)
            ForEach(model.source.layers.filter{model.layerIDs.contains($0.id)}) { Text($0.name).tag(Optional($0.id)) }
          }
          Text("Align overlapping photos by shared detail. A locked layer becomes the fixed reference for planar projections.").font(.caption).foregroundStyle(.secondary)
          if let edit = model.edit {
            Text("\(edit.projection.title) · \(edit.matchedPoints) matches · \(edit.rmsPixels.formatted(.number.precision(.fractionLength(2)))) px residual").font(.caption).foregroundStyle(.secondary)
          }
          Toggle("Preview",isOn:$model.preview)
        }.frame(width:260)
      }
      if let error = model.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
      HStack {
        Text("\(model.layerIDs.count) selected layers").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") { store.cancelPhotoAlign() }.keyboardShortcut(.cancelAction)
        Button("OK") { store.commitPhotoAlign() }.keyboardShortcut(.defaultAction).disabled(!model.ready)
      }
    }.padding(20).frame(width:760,height:520)
      .onChange(of:model.settings) { _,_ in model.refresh() }
      .task { if model.edit == nil { model.refresh() } }
      .onDisappear { model.close() }
  }
}
extension EditorStore {
  var canBeginPhotoAlign: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges && transformDraft == nil && !editingMask && !editingComponent
      && (try? PhotoAlign.targets(layoutSelection,in:document)) != nil
  }
  func beginPhotoAlign() {
    guard canBeginPhotoAlign else { return }
    photoAlignDraft = PhotoAlignWorkspace(source:document,layerIDs:layoutSelection)
  }
  func cancelPhotoAlign() { photoAlignDraft?.close();photoAlignDraft = nil }
  func commitPhotoAlign() {
    guard let draft = photoAlignDraft,draft.ready,let edit = draft.edit else { return }
    cancelPhotoAlign()
    performGeometry(.photoAlign(edit),onSuccess:{ [weak self] in
      guard let self else { return };self.selectedLayerIDs = edit.selectedLayerIDs
    })
  }
}
extension AppDelegate { @objc func autoAlignLayers() { store?.beginPhotoAlign() } }
