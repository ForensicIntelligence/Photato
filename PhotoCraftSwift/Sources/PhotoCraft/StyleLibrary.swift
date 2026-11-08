import Foundation
import Observation
import PhotoCraftCore

@MainActor @Observable final class StyleLibrary {
  static let shared:StyleLibrary = {
    let isolated=ProcessInfo.processInfo.environment["PHOTATO_ISOLATED_UI_SESSION"]=="1" || CommandLine.arguments.contains{$0.hasPrefix("--snapshot")}
    return StyleLibrary(persistenceURL:isolated ? nil:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("Photato/Styles.pclibrary"))
  }()
  let identity=UUID()
  private(set) var state:StyleLibraryState
  private(set) var revision=UUID()
  private(set) var busy=false
  private(set) var loadFailed=false
  var error:String?
  var selected=Set<UUID>()
  var collapsed=Set<UUID>()
  @ObservationIgnored var loadTask:Task<Void,Never>?
  @ObservationIgnored let persistenceURL:URL?
  @ObservationIgnored let preparation:@Sendable(StyleLibraryState,StyleLibraryMutation)throws->(StyleLibraryState,UUID?)
  init(persistenceURL:URL?=nil,initialState:StyleLibraryState = .init(),preparation:@escaping @Sendable(StyleLibraryState,StyleLibraryMutation)throws->(StyleLibraryState,UUID?) = {state,mutation in var next=state;let id=try next.apply(mutation);return(next,id)}) {
    self.persistenceURL=persistenceURL;self.preparation=preparation;state=initialState
    if let url=persistenceURL,FileManager.default.fileExists(atPath:url.path) {
      busy=true
      loadTask=Task { [weak self] in
        do {
          let next=try await Task.detached(priority:.userInitiated) {
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size<=StyleLibraryState.maximumBytes else {throw CraftError.invalid("Style library file is too large.")}
            return try StyleLibraryState.decode(Data(contentsOf:url,options:.mappedIfSafe))
          }.value
          self?.state=next;self?.revision=UUID()
        } catch {self?.loadFailed=true;self?.error="Could not load saved styles: \(error.localizedDescription)"}
        self?.busy=false
      }
    }
  }
  @discardableResult func edit(_ mutation:StyleLibraryMutation,authorize:@escaping @MainActor ()->Bool = {true}) async throws -> UUID? {
    guard !loadFailed else {throw CraftError.invalid("The saved style library could not be read. Its file has been preserved.")}
    guard !busy else {throw CraftError.invalid("Wait for the current style library operation.")}
    try Task.checkCancellation();busy=true;defer{busy=false}
    let source=state,oldRevision=revision,url=persistenceURL,prepare=preparation
    let worker=Task.detached(priority:.userInitiated) {let(next,id)=try prepare(source,mutation);let data=try next.encoded();try Task.checkCancellation();return(next,data,id)}
    let (next,data,id)=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
    try Task.checkCancellation();guard revision==oldRevision,authorize() else {throw CraftError.invalid("Style library operation was cancelled or its source changed.")}
    if let url {
      try await Task.detached(priority:.userInitiated) {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
      }.value
    }
    if state != next {state=next;revision=UUID()}
    selected.formIntersection(Set(next.nodes.map(\.id)));collapsed.formIntersection(Set(next.nodes.filter(\.isGroup).map(\.id)))
    if let id {selected=[id]};error=nil;return id
  }
}
