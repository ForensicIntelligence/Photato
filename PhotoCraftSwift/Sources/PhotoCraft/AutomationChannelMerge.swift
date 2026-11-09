import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum ChannelMergeAPI {
  static let name = "channel.merge"
  static let cancel = "channel.merge.cancel"
  static func schema(_ key: String) -> [String:Any] {
    key == "mode" ? ["type":"string","enum":ChannelMergeMode.allCases.map(\.rawValue)] : ["type":"array","minItems":2,"maxItems":8,"items":BrushAPI.object(["shareID":["type":"string","format":"uuid"],"revision":["type":"string","minLength":1,"maxLength":256]],required:["shareID","revision"])]
  }
  static var stateSchema: [String:Any] { BrushAPI.object(["available":BrushAPI.flag,"eligibleSharedSources":["type":"integer","minimum":0,"maximum":8],"active":BrushAPI.flag],required:["available","eligibleSharedSources","active"]) }
  static var resultSchema: [String:Any] { BrushAPI.object(["document":["type":"object","description":"Full newly shared document state."],"closedSources":["type":"array","minItems":2,"maxItems":8,"items":BrushAPI.object(["shareID":["type":"string","format":"uuid"],"documentID":["type":"string","format":"uuid"]],required:["shareID","documentID"])]],required:["document","closedSources"]) }
  static var capabilities: [String:Any] { ["command":name,"cancelCommand":cancel,"state":"channelMerge","stateSchema":stateSchema,"resultSchema":resultSchema,
    "native":"Channels panel > Merge Channels. Choose the output mode/count, then one grayscale image per destination channel. Multichannel uses an assignment wizard. Only chosen sources close, without changing their original files. The new untitled document is unsaved and has fresh identity/empty history.",
    "samples":"Same-size, same-depth flattened opaque single-channel Gray inputs. RGB8/16/32, CMYK8/16, Lab8/16, auxiliary-only Multichannel8/16. Direct component assignment, with Photoshop's independently measured15-bit working grid at16-bit. No source ICC color conversion. Result untagged; process modes retain captured working ICC. Resolution follows first assigned source, with full Photoshop resolution/selection/profile defaults still under qualification.",
    "publication":"Requires transfers plus document closing and explicit current source shares/revisions. The route anchor may remain unused. Register the output before closing only selected sources, in one main-actor transaction. Source/session/permission/lease/color/lifecycle changes or cancellation reject without partial publication. APIcancel targets only its authorized active request; cancellation acknowledgment precedes worker completion.",
    "limits":"Native auxiliary-only documents admit56channels; ordinary auxiliary allowance remains52. API shares retain the existing8-document policy. Native components and auxiliary planes retain paged storage and existing scratch/format/heap limits; maximum dense physical capacity and60fps are not qualified.",
    "adobe":"No dedicated Merge Channels endpoint exists in the pinned Adobe HTTP contract. No route or unsupported multi-document Action descriptor is invented. Native/Photato support does not establish UXP, Actions or full COL02 parity." ] }
}

extension AutomationCommand {
  func mergeChannelOptions() throws -> (ChannelMergeMode,[(UUID,String)]) {
    guard let mode = ChannelMergeMode(rawValue: try string("mode")), case .array(let values) = parameters["sources"], (2...8).contains(values.count) else { throw AutomationFailure(status:400,message:"Choose a supported mode and two to eight explicitly shared source documents.") }
    let sources = try values.map { value -> (UUID,String) in
      guard case .object(let fields) = value, Set(fields.keys) == ["shareID","revision"],
        case .string(let text) = fields["shareID"], let id = UUID(uuidString:text),
        case .string(let revision) = fields["revision"], !revision.isEmpty, revision.count <= 256 else { throw AutomationFailure(status:400,message:"Each source needs its shareID and current revision.") }
      return (id,revision)
    }
    guard Set(sources.map(\.0)).count == sources.count else { throw AutomationFailure(status:400,message:"A document cannot be selected for more than one channel.") }
    return (mode,sources)
  }
}

extension AutomationService {
  func channelMergeState(_ document: CraftNSDocument) -> [String:Any] {
    let count = shares.compactMap(\.document).filter { ChannelMerge.matches($0.store.document,anchor:document.store.document) && $0.canRunFileCommand }.count
    return ["available":ChannelMerge.unavailableReason(document.store.document) == nil && controller.canStartChannelMerge && count >= (document.store.document.depth == .f32 ? 3 : 2),"eligibleSharedSources":count,"active":mergeChannelsTask != nil]
  }
  func mergeChannels(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    let (mode,inputs) = try command.mergeChannelOptions()
    guard documentTransfersEnabled, documentClosingEnabled else { throw AutomationFailure(status:403,message:"Enable document transfers and document closing for Merge Channels.") }
    guard !documentTransferBusy, controller.canStartChannelMerge else { throw AutomationFailure(status:409,message:"Finish the current document lifecycle operation first.") }
    let selected = try inputs.map { id,revision -> CraftNSDocument in
      guard let source = shares.first(where: { $0.id == id })?.document else { throw AutomationFailure(status:404,message:"An explicitly shared source was not found.") }
      try preflight(source)
      guard self.revision(source.store) == revision else { throw AutomationFailure(status:409,message:"A source revision is stale.") }
      return source
    }
    guard let first = selected.first, ChannelMerge.matches(document.store.document,anchor:first.store.document), mode.accepts(count:selected.count,depth:first.store.document.depth) else { throw AutomationFailure(status:422,message:"Source geometry, depth or output channel count disagree.") }
    let locked = selected.contains(where: { $0 === document }) ? selected : selected + [document]
    let fence = ChannelMergeFence(locked,controller:controller)
    guard controller.documentClosing.canStart(selected), fence.isCurrent(controller) else { throw AutomationFailure(status:409,message:"A source or document lifecycle operation is busy.") }
    let token = token, generation = generation, transfer = documentTransferGeneration, closing = documentClosingGeneration
    let sources = selected.map { $0.store.document }, prepare = document.store.mergeChannelsPreparation, name = controller.nextUntitledName
    let profile = try mode == .multichannel ? nil : fence.settings.profile(mode.colorMode,depth:first.store.document.depth)
    documentTransferBusy = true; mergeChannelsShareIDs = Set(inputs.map(\.0) + [share.id])
    let worker = Task.detached(priority:.userInitiated) { try prepare(sources,mode,profile,name) }; mergeChannelsTask = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }; fence.lock(observer)
    defer { mergeChannelsTask = nil; mergeChannelsShareIDs = []; documentTransferBusy = false; fence.unlock() }
    let plan = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard !observer.isCancelled, !worker.isCancelled, isRunning, self.token == token, self.generation == generation,
      documentTransfersEnabled, documentClosingEnabled, documentTransferGeneration == transfer, documentClosingGeneration == closing,
      controller.channelMergeWorkspace == nil, fence.isCurrent(controller), plan.sources == sources,
      plan.document.colorMode == mode.colorMode, shares.contains(where: { $0.id == share.id && $0.document === document }),
      revision(document.store) == command.revision,
      inputs.indices.allSatisfy({ i in shares.contains(where: { $0.id == inputs[i].0 && $0.document === selected[i] }) && revision(selected[i].store) == inputs[i].1 }) else { throw AutomationFailure(status:409,message:"Merge Channels cancelled or sharing, sources or lifecycle changed.") }
    try Self.checkLimits(plan.document)
    fence.unlock()
    let result = try controller.publishChannelMerge(plan,sources:selected) { try self.replaceMergeChannelShares(inputs.map(\.0),with:$0) }
    guard let lease = shares.first(where: { $0.document === result }) else { throw AutomationFailure(status:409,message:"Merged document sharing ended.") }
    let closed = inputs.indices.map { ["shareID":inputs[$0].0.uuidString,"documentID":sources[$0].id.uuidString] }
    return .json(["document":state(lease,document:result),"closedSources":closed],status:201)
  }
}
