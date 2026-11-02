import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

enum LinkedArtworkStatus:String,Sendable {
  case checking,current,modified,missing,authorizationRequired,failed
  var title:String {switch self {case .checking:"Checking source…";case .current:"Source is up to date";case .modified:"Source has changed";case .missing:"Source is missing";case .authorizationRequired:"Relink to authorize the source";case .failed:"Source update failed"}}
}
struct LinkedArtworkState:Sendable {
  var status:LinkedArtworkStatus
  var message:String?
  var fingerprint:String?
  var signature:String?
}
@MainActor @Observable final class LinkedSourceController {
  weak var store:EditorStore?
  var states:[UUID:LinkedArtworkState]=[:]
  @ObservationIgnored var lastSignatures:[UUID:String]=[:]
  @ObservationIgnored var lastFingerprints:[UUID:String]=[:]
  @ObservationIgnored var seen=Set<UUID>()
  @ObservationIgnored var pending=Set<UUID>()
  @ObservationIgnored var loop:Task<Void,Never>?
  @ObservationIgnored var operationID:UUID?
  var stopped=false
  init(store:EditorStore){self.store=store}
  func modelChanged() {
    guard let store,!stopped else{return}
    let ids=Set(store.document.layers.compactMap{$0.smartObject?.linkedSource==nil ? nil:$0.smartObject?.sourceID})
    states=states.filter{ids.contains($0.key)};pending.formIntersection(ids)
    guard !ids.isEmpty else{loop?.cancel();loop=nil;return}
    guard loop==nil else{return}
    loop=Task {[weak self] in
      while !Task.isCancelled {
        guard self?.stopped==false,self?.store != nil else{return};await self?.scan()
        do{try await Task.sleep(for:.seconds(2))}catch{return}
      }
    }
  }
  func stop(){stopped=true;loop?.cancel();loop=nil;if operationID != nil{store?.geometryTask?.cancel()}}
  func state(_ source:SmartObject)->LinkedArtworkState {
    states[source.sourceID] ?? .init(status:source.linkedSource?.authorizationID==nil ? .authorizationRequired:.checking)
  }
  func scan()async {
    guard let store,!stopped,operationID==nil else{return}
    let original=store.document,registry=store.linkedSourceRegistry
    var objects:[UUID:SmartObject]=[:],grants:[UUID:LinkedArtworkGrant]=[:]
    for layer in original.layers {if let source=layer.smartObject,let link=source.linkedSource,objects[source.sourceID]==nil {
      objects[source.sourceID]=source
      do{grants[source.sourceID]=try registry.resolve(link,documentID:original.id,documentURL:store.linkedArtworkDocumentURL)}catch{states[source.sourceID] = .init(status:link.authorizationID==nil ? .authorizationRequired:.missing,message:error.localizedDescription)}
    }}
    let signatures=lastSignatures,fingerprints=lastFingerprints,queued=pending,canUpdate=store.canManageLinkedArtwork
    let captured=grants,sources=objects
    struct Result:Sendable {let id:UUID;let signature:String?;let file:LinkedArtworkRead?;let error:String?}
    let worker=Task.detached(priority:.utility){()throws->[Result] in
      var results:[Result]=[]
      for (id,grant) in captured {
        try Task.checkCancellation()
        do {
          let sig=try LinkedArtworkRead.signature(grant)
          let source=sources[id]!
          let needsHydration=source.data.isEmpty && source.linkedSource?.contentHash==fingerprints[id]
          let file=(signatures[id] != sig || needsHydration || (queued.contains(id)&&canUpdate)) ? try LinkedArtworkRead.read(grant):nil
          results.append(.init(id:id,signature:sig,file:file,error:nil))
        }catch is CancellationError{throw CancellationError()}catch{results.append(.init(id:id,signature:nil,file:nil,error:error.localizedDescription))}
      }
      return results
    }
    let values:[Result]
    do{values=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()}catch{return}
    guard !stopped,store.document==original else{return}
    var updates:[UUID:LinkedArtworkRead]=[:]
    for value in values {
      guard let source=objects[value.id],let grant=grants[value.id],registry.stillAuthorizes(grant)else{continue}
      if let error=value.error{states[value.id] = .init(status:.missing,message:error);continue}
      let first = !seen.contains(value.id);seen.insert(value.id)
      let previous=lastFingerprints[value.id]
      if let signature=value.signature{lastSignatures[value.id]=signature}
      if let file=value.file{lastFingerprints[value.id]=file.fingerprint}
      let fingerprint=value.file?.fingerprint ?? previous
      let matches=fingerprint != nil && fingerprint==source.linkedSource?.contentHash
      states[value.id] = .init(status:matches ? .current:.modified,fingerprint:fingerprint,signature:value.signature)
      if matches{pending.remove(value.id)}
      if matches,source.data.isEmpty,let file=value.file {
        do{try store.session.hydrateLinkedSmartObject(value.id,bytes:file.data);store.renderSnapshot=nil;store.render()}catch{states[value.id] = .init(status:.failed,message:error.localizedDescription)}
      }
      // A source first seen after reopening is highlighted, not silently replaced.
      // Remember the observed version so Undo is not immediately undone by a poll.
      if !first,let fingerprint,previous != fingerprint,!matches {pending.insert(value.id)}
      if pending.contains(value.id),canUpdate,let file=value.file,!matches {updates[value.id]=file}
    }
    if !updates.isEmpty {
      do{try await apply(updates,title:updates.count==1 ? "Update Linked Smart Object":"Update Linked Smart Objects")}catch{for id in updates.keys{states[id] = .init(status:.failed,message:error.localizedDescription)}}
    }
  }
  func update(_ layerID:UUID?=nil)async throws {
    guard let store,store.canManageLinkedArtwork else{throw CraftError.invalid("Finish the current interaction before updating linked artwork.")}
    let selected=layerID.flatMap{id in store.document.layers.first{$0.id==id}?.smartObject?.sourceID}
    if layerID != nil,selected==nil{throw CraftError.invalid("Choose a linked Smart Object.")}
    var grants:[UUID:LinkedArtworkGrant]=[:]
    for layer in store.document.layers {if let source=layer.smartObject,let link=source.linkedSource,(selected==nil || selected==source.sourceID),grants[source.sourceID]==nil {grants[source.sourceID]=try store.linkedSourceRegistry.resolve(link,documentID:store.document.id,documentURL:store.linkedArtworkDocumentURL)}}
    guard !grants.isEmpty else{throw CraftError.invalid("Choose a linked Smart Object.")}
    let original=store.document,registry=store.linkedSourceRegistry,captured=grants
    let worker=Task.detached(priority:.userInitiated){()throws->[UUID:LinkedArtworkRead]in
      var result:[UUID:LinkedArtworkRead]=[:];for(id,grant)in captured{result[id]=try LinkedArtworkRead.read(grant)};return result
    }
    let reads=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation();guard store.document==original,reads.values.allSatisfy({registry.stillAuthorizes($0.grant)})else{throw CraftError.invalid("The document or source authorization changed.")}
    try await apply(reads,title:reads.count==1 ? "Update Linked Smart Object":"Update Linked Smart Objects")
  }
  func acknowledge(_ files:[UUID:LinkedArtworkRead]) {
    for (id,file)in files {
      guard store?.document.layers.contains(where:{$0.smartObject?.sourceID==id && $0.smartObject?.linkedSource?.contentHash==file.fingerprint})==true else{continue}
      pending.remove(id);seen.insert(id);lastFingerprints[id]=file.fingerprint;lastSignatures[id]=file.signature
      states[id] = .init(status:.current,fingerprint:file.fingerprint,signature:file.signature)
    }
  }
  func apply(_ files:[UUID:LinkedArtworkRead],title:String)async throws {
    guard let store,store.canManageLinkedArtwork else{throw CraftError.invalid("Finish the current interaction before updating artwork.")}
    let original=store.document,session=store.sessionGeneration,panel=store.layerPanelGeneration,id=UUID(),registry=store.linkedSourceRegistry
    operationID=id;store.geometryBusy=true;store.renderTask?.cancel()
    defer{if operationID==id{operationID=nil;if store.layerPanelGeneration==panel{store.geometryBusy=false;store.geometryTask=nil;store.render()}}}
    let worker=Task.detached(priority:.userInitiated){()throws->PreparedEdit in
      var result=original
      for (sourceID,file) in files {
        guard let layer=result.layers.first(where:{$0.smartObject?.sourceID==sourceID})else{throw CraftError.invalid("Linked source no longer exists.")}
        let old=layer.smartObject!
        if old.linkedSource?.contentHash==file.fingerprint,try layer.linkedSmartObjectPreview()==nil{continue}
        try LinkedSmartObjectIO.replacement(file.data,fileName:file.fileName,reference:file.reference,in:result,layerID:layer.id).apply(to:&result)
      }
      for file in files.values {guard try LinkedArtworkRead.signature(file.grant)==file.signature else{throw DocumentPersistenceConflict.changed}}
      return try PreparedEdit(command:.linkedSmartObject(.init(source:original,result:result,title:title)),document:original)
    }
    store.geometryTask=Task{await withTaskCancellationHandler{_ = try? await worker.value}onCancel:{worker.cancel()}}
    let prepared=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
    guard !stopped,operationID==id,store.geometryTask?.isCancelled != true,store.sessionGeneration==session,
      store.layerPanelGeneration==panel,store.document==original,files.values.allSatisfy({registry.stillAuthorizes($0.grant)})else{throw CraftError.invalid("Linked artwork update was cancelled or became stale.")}
    try store.executeCompositePreparedEdit(prepared,allowLinkedSmartObject:true)
    for (sourceID,file)in files {
      pending.remove(sourceID);seen.insert(sourceID);lastFingerprints[sourceID]=file.fingerprint;lastSignatures[sourceID]=file.signature
      states[sourceID] = .init(status:.current,fingerprint:file.fingerprint,signature:file.signature)
      if store.document.layers.first(where:{$0.smartObject?.sourceID==sourceID})?.smartObject?.data.isEmpty==true {try store.session.hydrateLinkedSmartObject(sourceID,bytes:file.data)}
    }
    if store.document != original{store.onChange?(.changeDone)};store.status=title
  }
}
