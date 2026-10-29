import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class CameraRawWorkspace {
  struct Snapshot { var rgb: CameraRawSettings; var sensor: RawDevelopment? }
  var settings = CameraRawSettings()
  var sensorSettings: RawDevelopment?
  var sensorInfo: RawSourceIO.Info?
  var onSensorChange: ((RawDevelopment) -> Void)?
  private var snapshot: Snapshot { Snapshot(rgb:settings,sensor:sensorSettings) }
  var image: CGImage?
  var originalImage: CGImage?
  var histogram = [[Float]](repeating:[Float](repeating:0,count:256),count:3)
  var undoStates: [Snapshot] = []
  var redoStates: [Snapshot] = []
  var rendering = false
  var preview = true
  var zoom = 1.0
  var error: String?
  var task: Task<Void,Never>?
  var onChange: ((CameraRawSettings) -> Void)?
  private var document: CraftDocument?
  private var draft: FilterDraft?
  private var generation = 0
  private var closed = false
  private var sliderStart: Snapshot?
  var ready: Bool { image != nil && !rendering && error == nil }
  func prepare(document: CraftDocument,draft: FilterDraft) async {
    self.document = document; self.draft = draft; closed = false; settings = draft.filter.cameraRaw ?? .init()
    sensorSettings = draft.rawDevelopment
    if let object = document.layers.first(where: { $0.id == draft.id })?.smartObject,object.rawDevelopment != nil {
      do {
        let worker = Task.detached { try RawSourceIO.inspect(object.data,decoderVersion:object.rawDevelopment?.decoderVersion) }
        sensorInfo = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      } catch { self.error = error.localizedDescription; return }
    }
    refresh(); await task?.value
  }
  func change(_ value: CameraRawSettings,remember: Bool = true) {
    do { try value.validate() } catch { self.error = error.localizedDescription; return }
    if value == settings { return }
    if remember && sliderStart == nil { rememberUndo(snapshot) }
    settings = value; sensorSettings?.adjustments = value; error = nil; notify(); refresh()
  }
  func rememberUndo(_ value: Snapshot) {
    undoStates.append(value); if undoStates.count > 100 { undoStates.removeFirst() }; redoStates.removeAll()
  }
  func slider(_ editing: Bool) {
    if editing { sliderStart = snapshot }
    else if let before = sliderStart { sliderStart = nil; if before.rgb != settings || before.sensor != sensorSettings { rememberUndo(before) } }
  }
  private func notify() { onChange?(settings); if let sensorSettings { onSensorChange?(sensorSettings) } }
  func changeSensor(_ value: RawDevelopment,remember: Bool = true) {
    do { try value.validate() } catch { self.error = error.localizedDescription; return }
    guard sensorSettings != value else { return }
    if remember && sliderStart == nil { rememberUndo(snapshot) }
    sensorSettings = value; settings = value.adjustments; error = nil; notify(); refresh()
  }
  func reset() { if sensorSettings != nil { changeSensor(.init()) } else { change(.init()) } }
  private func restore(_ state: Snapshot) { settings = state.rgb; sensorSettings = state.sensor; error = nil; notify(); refresh() }
  func undo() { guard let value = undoStates.popLast() else { return }; redoStates.append(snapshot); restore(value) }
  func redo() { guard let value = redoStates.popLast() else { return }; undoStates.append(snapshot); restore(value) }
  func refresh() {
    guard !closed, let document, var draft else { return }
    task?.cancel(); generation += 1; let token = generation
    draft.filter.cameraRaw = settings; draft.rawDevelopment = sensorSettings
    let request = draft, needsOriginal = originalImage == nil
    rendering = true; error = nil
    task = Task {
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker = Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?,[[Float]],RawSourceIO.Info?) in
          var edited = document; try request.command(in:document).apply(to:&edited)
          let pixels = try Renderer.composite(edited)
          let before = needsOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document) : nil
          var bins = [[Float]](repeating:[Float](repeating:0,count:256),count:3)
          let step = max(1,Int(sqrt(Double(pixels.width*pixels.height)/262144)))
          for y in stride(from:0,to:pixels.height,by:step) { try Task.checkCancellation(); for x in stride(from:0,to:pixels.width,by:step) {
            let p = pixels.pixel(x:x,y:y)
            for c in 0..<3 { bins[c][Int(unit(p.rgb[c])*255)] += p.a }
          } }
          let maximum = max(1,bins.flatMap { $0 }.max() ?? 1)
          bins = bins.map { $0.map { $0/maximum } }
          let object = edited.layers.first(where: { $0.id == request.id })?.smartObject
          let info = request.rawDevelopment != nil && object != nil ? try RawSourceIO.inspect(object!.data,decoderVersion:object?.rawDevelopment?.decoderVersion) : nil
          return (try ColorManagement.displayImage(pixels,in:document),before,bins,info)
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation(); guard !closed, token == generation else { return }
        image = result.0; if let before = result.1 { originalImage = before }; histogram = result.2; if let info = result.3 { sensorInfo = info }; rendering = false
      } catch { guard !closed, token == generation else { return }; rendering = false; if !Task.isCancelled { self.error = error.localizedDescription } }
    }
  }
  func close() { closed = true; generation += 1; task?.cancel(); task = nil; rendering = false; onChange = nil; onSensorChange = nil }
}
