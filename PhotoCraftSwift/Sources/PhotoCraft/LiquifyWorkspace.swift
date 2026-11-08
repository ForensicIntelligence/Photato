import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class LiquifyWorkspace {
  var settings = LiquifySettings()
  var tool: LiquifyTool = .forwardWarp
  var size = 100.0
  var density = 50.0
  var pressure = 100.0
  var rate = 80.0
  var showMesh = false
  var showMask = true
  var showBackdrop = false
  var preview = true
  var backdropOpacity = 0.5
  var zoom = 1.0
  var pan = CGSize.zero
  var panTool = false
  var selectedFace = 0
  var image: CGImage?
  var originalImage: CGImage?
  var field: LiquifyField?
  var notice: String?
  var error: String?
  var loading = false
  var detecting = false
  var rendering = false
  var undoStates: [LiquifySettings] = []
  var redoStates: [LiquifySettings] = []
  var input: LiquifyInput?
  var meshLibrary: LiquifyMeshLibrary?
  var document: CraftDocument?
  var stroke: LiquifyStroke?
  var onChange: ((LiquifySettings) -> Void)?
  var task: Task<Void,Never>?
  var detectionTask: Task<Void,Never>?
  private var generation = 0
  private var closed = false
  private var sliderStart: LiquifySettings?
  var ready: Bool { input != nil && !loading && !detecting }
  var canLoadLastMesh: Bool { ready && meshLibrary?.settings != nil }
  func loadLastMesh() {
    guard ready, let saved = meshLibrary?.settings else { return }
    end()
    change(saved)
    selectedFace = 0
  }
  var currentSettings: LiquifySettings {
    var value = settings
    if let stroke { value.strokes.append(stroke) }
    return value
  }
  func prepare(document: CraftDocument, draft: FilterDraft) async {
    closed = false; self.document = document; loading = true
    do {
      let worker = Task.detached(priority:.userInitiated) {
        try LiquifyInput.prepare(document:document,layerID:draft.id,filterID:draft.filterID)
      }
      let source = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation()
      input = source; settings = draft.filter.liquify ?? .init()
      if settings.width == 0 { settings.width = source.width; settings.height = source.height }
      originalImage = try ColorManagement.displayImage(source.pixels,in:document)
      refresh()
    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    loading = false
  }
  func saveUndo(_ before: LiquifySettings) {
    undoStates.append(before); if undoStates.count > 100 { undoStates.removeFirst() }; redoStates.removeAll()
  }
  func change(_ value: LiquifySettings, remember: Bool = true) {
    var value = value
    if value.width == 0, let input { value.width = input.width; value.height = input.height }
    do { try value.validate() } catch { self.error = error.localizedDescription; return }
    if remember && value != settings { saveUndo(settings) }
    settings = value; error = nil; onChange?(settings); refresh()
  }
  func begin(x: Double,y: Double,pressure pen: Double,alternate: Bool) {
    guard ready, stroke == nil else { return }
    let selected = resolvedTool(alternate:alternate)
    var s = LiquifyStroke(tool:selected,size:size,points:[[x,y,pen]])
    s.density = density; s.pressure = pressure; s.rate = rate
    if selected == .lassoMask { s.amount = alternate ? 0 : 1 }
    do { try s.validate() } catch { self.error = error.localizedDescription; return }
    stroke = s; refresh()
  }
  func drag(x: Double,y: Double,pressure: Double) {
    guard stroke != nil else { return }
    guard settings.strokes.reduce(0,{ $0+$1.points.count })+(stroke?.points.count ?? 0) < 32768 else { end(); error = "Liquify point limit reached. Commit this edit before continuing."; return }
    stroke?.points.append([x,y,pressure]); refresh()
  }
  func end() {
    guard let stroke else { return }; self.stroke = nil
    var next = settings; next.strokes.append(stroke); change(next)
  }
  func global(_ tool: LiquifyTool, amount: Double? = nil) {
    end(); var next = settings; var s = LiquifyStroke(tool:tool); s.amount = amount
    next.strokes.append(s); change(next)
  }
  func restore() { end(); change(LiquifySettings(width:settings.width,height:settings.height)) }
  func undo() {
    end(); guard let value = undoStates.popLast() else { return }; redoStates.append(settings); change(value,remember:false)
  }
  func redo() {
    guard let value = redoStates.popLast() else { return }; undoStates.append(settings); change(value,remember:false)
  }
  func faceValue(_ key: LiquifyFaceParameter) -> Double {
    settings.faces.indices.contains(selectedFace) ? settings.faces[selectedFace][key] : 0
  }
  func faceSlider(_ editing: Bool) {
    if editing { sliderStart = settings }
    else if let before = sliderStart { sliderStart = nil; if before != settings { saveUndo(before) } }
  }
  func setFace(_ key: LiquifyFaceParameter, value: Double) {
    guard settings.faces.indices.contains(selectedFace) else { return }
    var next = settings; next.faces[selectedFace][key] = value
    change(next,remember:sliderStart == nil)
  }
  func detect(using detector: any LiquifyFaceDetecting = VisionLiquifyFaces()) {
    guard ready, let input else { return }; end(); detecting = true; error = nil; notice = nil
    detectionTask = Task { @MainActor in
      defer { detecting = false }
      do {
        let faces = try await detector.faces(in:input.pixels); try Task.checkCancellation()
        var next = settings; next.faces = faces.map { .init(geometry:$0) }; selectedFace = 0; change(next)
        if faces.isEmpty { notice = "No faces were found in this layer." }
      } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func refresh() {
    guard !closed, let input, let document else { return }
    generation += 1
    guard !rendering else { return }
    let current = generation, value = currentSettings
    rendering = true
    task = Task { @MainActor in
      do {
        let worker = Task.detached(priority:.userInitiated) {
          let mesh = try value.field(targetWidth:input.width,targetHeight:input.height)
          let image = try ColorManagement.displayImage(input.preview(mesh),in:document)
          return (mesh,image)
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, !closed else { return }
        field = result.0; image = result.1
      } catch { if !Task.isCancelled, current == generation { self.error = error.localizedDescription } }
      rendering = false
      if !Task.isCancelled, !closed, current != generation { refresh() }
    }
  }
  func close() { closed = true; task?.cancel(); detectionTask?.cancel(); task = nil; detectionTask = nil; onChange = nil }
}
