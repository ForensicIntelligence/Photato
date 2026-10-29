import AppKit
import SwiftUI
import PhotoCraftCore

@MainActor final class RawPlacementWorkspace {
  let store: EditorStore
  let model = CameraRawWorkspace()
  private(set) var finished = false
  var completion: ((Result<RawDevelopment,Error>) -> Void)?
  init(document: CraftDocument) throws {
    guard let layer = document.layers.first,let settings = layer.smartObject?.rawDevelopment else {
      throw CraftError.invalid("Choose a camera RAW source.")
    }
    store = EditorStore(document:document)
    var filter = RasterFilter(.cameraRaw);filter.cameraRaw = settings.adjustments
    store.filterDraft = FilterDraft(id:layer.id,filter:filter,rawDevelopment:settings)
  }
  func prepare() async {
    guard !finished,let draft = store.filterDraft else {return}
    await model.prepare(document:store.document,draft:draft)
  }
  func run() {
    guard !finished,model.ready,let settings = model.sensorSettings else {return}
    finish(.success(settings))
  }
  func cancel() {finish(.failure(CancellationError()))}
  private func finish(_ result: Result<RawDevelopment,Error>) {
    guard !finished else {return};finished = true
    model.close();store.renderTask?.cancel();store.filterDraft = nil
    let callback = completion;completion = nil;callback?(result)
  }
}

@MainActor final class RawPlacementWindow: NSWindowController,NSWindowDelegate {
  let model: RawPlacementWorkspace
  init(model: RawPlacementWorkspace) {
    self.model = model
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:720),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    window.title = "Camera Raw — Place Embedded";window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView:CameraRawSheet(store:model.store,workspace:model.model,placement:model));window.center()
    super.init(window:window);window.delegate = self
  }
  required init?(coder: NSCoder) {nil}
  func windowWillClose(_ notification: Notification) {model.cancel()}
}
