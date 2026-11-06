import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PatternLibrary {
  static let shared = PatternLibrary(persistenceURL:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("Photato/Patterns.pclibrary"))
  let identity=UUID()
  private(set) var state:PatternLibraryState
  private(set) var revision=UUID()
  private(set) var busy=false
  var error:String?
  @ObservationIgnored var loadTask:Task<Void,Never>?
  @ObservationIgnored let persistenceURL:URL?
  @ObservationIgnored private let importDecoder:@Sendable(Data)throws->PATCodec.Library
  @ObservationIgnored private var loadFailed=false
  @ObservationIgnored private var selectionAnchor:UUID?
  var items:[RasterPattern]{state.patterns}
  var selected:RasterPattern?{items.first{$0.id==selectedID} ?? items.first}
  var selectedID:String? {
    get{state.selectedID}
    set{
      guard !busy,newValue==nil || items.contains(where:{$0.id==newValue})else{return}
      var next=state;next.selectedID=newValue
      let node=next.nodes.first{$0.patternID==newValue && newValue != nil}
      next.activeNodeID=node?.id;next.selectedNodes=Set(node.map{[$0.id]} ?? [])
      publishSelection(next)
    }
  }
  init(persistenceURL:URL?=nil,decoder:@escaping @Sendable(Data)throws->PATCodec.Library = {try PATCodec.readLibrary($0)}) {
    self.persistenceURL=persistenceURL
    importDecoder=decoder
    do {let patterns=try PatternPresets.make();state=PatternLibraryState(patterns:patterns,selectedID:patterns.first?.id)}
    catch{state=PatternLibraryState(patterns:[]);self.error=error.localizedDescription}
    if let url=persistenceURL,FileManager.default.fileExists(atPath:url.path) {
      busy=true
      loadTask=Task{[weak self]in
        let worker=Task.detached(priority:.userInitiated){try PatternArchive.decodeLibraryState(Self.readFile(url))}
        do {let loaded=try await worker.value;self?.state=loaded}
        catch{self?.loadFailed=true;self?.error="Could not load saved patterns: \(error.localizedDescription)"}
        self?.revision=UUID();self?.busy=false
      }
    }
  }
  nonisolated static func readFile(_ url:URL)throws->Data {
    let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
    guard size<=PatternArchive.maxBytes else{throw CraftError.invalid("Pattern file is too large.")}
    return try Data(contentsOf:url,options:.mappedIfSafe)
  }
  private func publishSelection(_ next:PatternLibraryState) {
    if next != state{state=next;revision=UUID()}
  }
  func select(_ ids:Set<UUID>,active:UUID?)throws {
    guard !busy,ids.isSubset(of:Set(state.nodes.map(\.id))),active==nil || ids.contains(active!),
      active==nil || state.node(active!)?.patternID != nil else{throw CraftError.invalid("Pattern selection changed or the library is busy.")}
    var next=state;next.selectedNodes=ids;next.activeNodeID=active
    if let active{next.selectedID=state.node(active)?.patternID}
    selectionAnchor=active ?? ids.first;publishSelection(next)
  }
  func click(_ id:UUID,modifiers:NSEvent.ModifierFlags)throws {
    guard let node=state.node(id)else{throw CraftError.invalid("Pattern item no longer exists.")}
    var ids:Set<UUID>=[id]
    if modifiers.contains(.shift),let anchor=selectionAnchor,
      let a=state.nodes.firstIndex(where:{$0.id==anchor}),let b=state.nodes.firstIndex(where:{$0.id==id}) {
      ids=Set(state.nodes[min(a,b)...max(a,b)].map(\.id))
    }else if modifiers.contains(.command){ids=state.selectedNodes;if !ids.insert(id).inserted{ids.remove(id)}}
    let oldAnchor=selectionAnchor
    try select(ids,active:!node.isGroup && ids.contains(id) ? id:nil)
    if modifiers.contains(.shift){selectionAnchor=oldAnchor}else{selectionAnchor=id}
  }
  func collapse(_ id:UUID,_ collapsed:Bool)throws {
    guard !busy,state.node(id)?.isGroup==true else{throw CraftError.invalid("Choose an available pattern group.")}
    var next=state;if collapsed{next.collapsed.insert(id)}else{next.collapsed.remove(id)};publishSelection(next)
  }
  /// Preparation is cancellable. Authorization precedes atomic replacement, the commit point.
  func edit<Result:Sendable>(_ operation:@escaping @Sendable(inout PatternLibraryState)throws->Result,
    authorize:@escaping @MainActor ()->Bool = {true})async throws->Result {
    guard !loadFailed else{throw CraftError.invalid("The saved pattern library could not be read. Its file has been preserved; repair it before saving presets.")}
    guard !busy else{throw CraftError.invalid("Wait for the current pattern operation to finish.")}
    try Task.checkCancellation();busy=true;defer{busy=false}
    let original=state,originalRevision=revision,url=persistenceURL
    let worker=Task.detached(priority:.userInitiated){
      var next=original;let result=try operation(&next);try next.validate();next.nodes=try next.orderedNodes()
      let data=try url != nil && next != original ? PatternArchive.encodeLibraryState(next):nil
      try Task.checkCancellation();return(next,data,result)
    }
    let(next,data,result)=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation()
    guard revision==originalRevision,authorize()else{throw CraftError.invalid("Pattern operation was cancelled or its source changed.")}
    if let url,let data {
      // Publish matching memory even if outer cancellation arrives after this point.
      try await Task.detached(priority:.userInitiated){
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:url,options:.atomic)
      }.value
    }
    if state != next{state=next;revision=UUID()};error=nil;return result
  }
  @discardableResult func mutate(_ mutation:PatternLibraryMutation,authorize:@escaping @MainActor ()->Bool = {true})async throws->UUID? {
    try await edit({try $0.apply(mutation)},authorize:authorize)
  }
  nonisolated private static func mergeAssets(_ patterns:[RasterPattern],into state:inout PatternLibraryState) {
    for pattern in patterns {
      if let index=state.patterns.firstIndex(where:{$0.id==pattern.id}){state.patterns[index]=pattern}
      else{state.patterns.append(pattern);state.nodes.append(.init(patternID:pattern.id))}
    }
    if let last=patterns.last,let node=state.nodes.first(where:{$0.patternID==last.id}) {
      state.selectedID=last.id;state.selectedNodes=[node.id];state.activeNodeID=node.id
    }
  }
  func install(_ patterns:[RasterPattern],authorize:@escaping @MainActor ()->Bool = {true})async throws {
    try await edit({Self.mergeAssets(patterns,into:&$0)},authorize:authorize)
  }
  func define(in document:CraftDocument,name:String,authorize:@escaping @MainActor ()->Bool = {true})async throws->String {
    try await edit({ state in
      let pattern=try PatternDefinition.make(in:document,name:name)
      Self.mergeAssets([pattern],into:&state);return pattern.id
    },authorize:authorize)
  }
  func install(_ library:PATCodec.Library,into parent:UUID?=nil,authorize:@escaping @MainActor ()->Bool = {true})async throws {
    let incoming=PatternLibraryState(patterns:library.patterns,nodes:library.nodes)
    try await edit({try $0.install(incoming,into:parent)},authorize:authorize)
  }
  func importData(_ data:Data,into parent:UUID?=nil,authorize:@escaping @MainActor ()->Bool = {true})async throws->Int {
    let decode=importDecoder
    return try await edit({state in
      let library=try decode(data)
      try state.install(PatternLibraryState(patterns:library.patterns,nodes:library.nodes),into:parent)
      return library.patterns.count
    },authorize:authorize)
  }
  func rename(_ id:String,to name:String)async throws {
    guard let node=state.nodes.first(where:{$0.patternID==id})else{throw CraftError.invalid("Pattern no longer exists.")}
    _=try await mutate(.rename(node.id,name))
  }
  func remove(_ id:String)async throws {
    let ids=Set(state.nodes.filter{$0.patternID==id}.map(\.id));_=try await mutate(.delete(ids))
  }
  func resetBuiltins()async throws{try await install(PatternPresets.make())}
}
