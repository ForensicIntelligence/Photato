import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import UniformTypeIdentifiers

extension EditorStore {
  var linkedArtworkDocumentURL:URL? {documentController?.documents.compactMap{$0 as? CraftNSDocument}.first{$0.store === self}?.fileURL}
  var canManageLinkedArtwork:Bool {
    if let owner=documentController?.documents.compactMap({$0 as? CraftNSDocument}).first(where:{$0.store === self}),
      owner.fileOperationBusy || owner.recoveryWriteBusy || owner.closeWorkflowID != nil {return false}
    return canSelectComponentTarget && historyOperation==nil && !smartFilterMaskEditing && channelArithmeticWorkspace==nil
  }
  var hasLinkedArtwork:Bool {document.layers.contains{$0.smartObject?.linkedSource != nil}}
  var selectedLinkedArtwork:SmartObject? {guard let object=activeLayer?.smartObject,object.linkedSource != nil else{return nil};return object}
  var canUpdateLinkedArtwork:Bool {canManageLinkedArtwork && selectedLinkedArtwork != nil}
  var canUpdateAllLinkedArtwork:Bool {canManageLinkedArtwork && hasLinkedArtwork}
  var canConvertToLinked:Bool {canEditSmartObject && activeLayer?.smartObject?.linkedSource==nil && !(activeLayer?.smartObject?.data.isEmpty ?? true)}
  var canEmbedLinkedArtwork:Bool {canManageLinkedArtwork && selectedLinkedArtwork != nil && activeLayer.map{!document.isImageLocked($0.id)}==true}
  func synchronizeLinkedArtwork() {
    if linkedSourceController==nil,hasLinkedArtwork {linkedSourceController=LinkedSourceController(store:self)}
    linkedSourceController?.modelChanged()
  }
  func linkedArtworkState(_ source:SmartObject)->LinkedArtworkState {
    linkedSourceController?.state(source) ?? .init(status:source.linkedSource?.authorizationID==nil ? .authorizationRequired:.checking)
  }
  func placeLinked(replacing:Bool=false) {
    guard clipboardTargetAvailable,(!replacing || canEditSmartObject)else{return}
    let original=document,panelGeneration=layerPanelGeneration,session=sessionGeneration,id=replacing ? activeLayer?.id:nil
    let panel=NSOpenPanel();panel.title=replacing ? "Relink to File":"Place Linked"
    panel.allowedContentTypes=[.pdf,RawSourceIO.contentType,.png,.jpeg,.tiff,.heic,.bmp,.gif,UTType(filenameExtension:"psd") ?? .data,UTType(filenameExtension:"psb") ?? .data,UTType(filenameExtension:"photato") ?? .data]
    panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
    panel.begin {[weak self] response in
      guard response == .OK,let selected=panel.url,let self,self.document==original,self.layerPanelGeneration==panelGeneration,self.sessionGeneration==session,self.clipboardTargetAvailable else{return}
      do {
        let grant=try self.linkedSourceRegistry.authorize(selected)
        if let id {self.relinkArtwork(id,grant:grant)}else{self.placeEmbeddedSource(grant.url,frame:self.selectedFrame?.id,linkedGrant:grant)}
      }catch{self.error=error.localizedDescription}
    }
  }
  func relinkArtwork(_ layerID:UUID,grant:LinkedArtworkGrant) {
    performLinkedArtwork(label:"Relink Smart Object",grant:grant){source,file in
      try LinkedSmartObjectIO.replacement(file.data,fileName:file.fileName,reference:file.reference,in:source,layerID:layerID)
    }
  }
  func performLinkedArtwork(label:String,grant:LinkedArtworkGrant,
    prepare:@escaping @Sendable(CraftDocument,LinkedArtworkRead)throws->Command) {
    guard canManageLinkedArtwork else{return}
    let original=document,session=sessionGeneration,panel=layerPanelGeneration,registry=linkedSourceRegistry
    let operation=UUID();linkedArtworkOperationID=operation;geometryBusy=true;renderTask?.cancel()
    geometryTask=Task {[weak self] in
      guard let self else{return}
      defer{if self.linkedArtworkOperationID==operation && self.layerPanelGeneration==panel{self.linkedArtworkOperationID=nil;self.geometryBusy=false;self.geometryTask=nil;self.render()}}
      do {
        let worker=Task.detached(priority:.userInitiated){()throws->PreparedEdit in
          let file=try LinkedArtworkRead.read(grant),command=try prepare(original,file)
          let edit=try PreparedEdit(command:command,document:original)
          guard try LinkedArtworkRead.signature(grant)==file.signature else{throw DocumentPersistenceConflict.changed};return edit
        }
        let edit=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard self.document==original,self.sessionGeneration==session,self.layerPanelGeneration==panel,registry.stillAuthorizes(grant)else{throw CraftError.invalid("The document or file authorization changed.")}
        try self.executeCompositePreparedEdit(edit,allowLinkedSmartObject:true)
        if self.document != original{self.onChange?(.changeDone)};self.status=label;self.synchronizeLinkedArtwork()
      }catch is CancellationError{self.status="Linked artwork operation cancelled"}catch{self.error=error.localizedDescription}
    }
  }
  func embedLinkedArtwork() {
    guard canEmbedLinkedArtwork,let layer=activeLayer,let object=layer.smartObject,let reference=object.linkedSource else{return}
    if !object.data.isEmpty,(try? layer.linkedSmartObjectPreview())==nil {
      performGeometry(label:"Convert to Embedded",allowLinkedSmartObject:true){source in try LinkedSmartObjectIO.retag(source,layerID:layer.id,source:object.embedding(),title:"Convert to Embedded")}
      return
    }
    do {
      let grant=try linkedSourceRegistry.resolve(reference,documentID:document.id,documentURL:linkedArtworkDocumentURL)
      performLinkedArtwork(label:"Convert to Embedded",grant:grant){source,file in
        if file.fingerprint==object.linkedSource?.contentHash,try source.layers.first(where:{$0.id==layer.id})?.linkedSmartObjectPreview()==nil {
          return try LinkedSmartObjectIO.retag(source,layerID:layer.id,source:object.hydrating(file.data).embedding(),title:"Convert to Embedded")
        }
        return try LinkedSmartObjectIO.replacement(file.data,fileName:file.fileName,reference:nil,in:source,layerID:layer.id,title:"Convert to Embedded")
      }
    }catch{self.error=error.localizedDescription}
  }
  func updateLinkedArtwork(all:Bool=false) {
    guard all ? canUpdateAllLinkedArtwork:canUpdateLinkedArtwork else{return};synchronizeLinkedArtwork()
    let id=all ? nil:activeLayer?.id
    Task {[weak self]in do{try await self?.linkedSourceController?.update(id)}catch{self?.error=error.localizedDescription}}
  }
  func revealLinkedArtwork() {
    guard let link=selectedLinkedArtwork?.linkedSource else{return}
    do{let file=try linkedSourceRegistry.resolve(link,documentID:document.id,documentURL:linkedArtworkDocumentURL);NSWorkspace.shared.activateFileViewerSelecting([file.url])}catch{self.error=error.localizedDescription}
  }
  func editLinkedArtwork() {
    guard let link=selectedLinkedArtwork?.linkedSource else{return}
    do{let file=try linkedSourceRegistry.resolve(link,documentID:document.id,documentURL:linkedArtworkDocumentURL);NSWorkspace.shared.open(file.url)}catch{self.error=error.localizedDescription}
  }
  func convertToLinkedArtwork() {
    guard canConvertToLinked,let layer=activeLayer,let object=layer.smartObject else{return}
    let original=document,panelGeneration=layerPanelGeneration,session=sessionGeneration
    let panel=NSSavePanel();panel.title="Convert to Linked";panel.nameFieldStringValue=object.fileName
    panel.begin {[weak self] response in
      guard response == .OK,let url=panel.url,let self,self.document==original,self.layerPanelGeneration==panelGeneration,self.sessionGeneration==session,self.canConvertToLinked else{return}
      self.saveLinkedArtworkSource(layer.id,object:object,url:url)
    }
  }
  func saveLinkedArtworkSource(_ layerID:UUID,object:SmartObject,url:URL) {
    guard canConvertToLinked else{return}
    let original=document,session=sessionGeneration,panel=layerPanelGeneration,registry=linkedSourceRegistry
    let operation=UUID();linkedArtworkOperationID=operation;geometryBusy=true;renderTask?.cancel()
    geometryTask=Task {[weak self]in
      guard let self else{return};var sourceSaved=false
      defer{if self.linkedArtworkOperationID==operation && self.layerPanelGeneration==panel{self.linkedArtworkOperationID=nil;self.geometryBusy=false;self.geometryTask=nil;self.render()}}
      do {
        // Validate every shared instance before creating or replacing a source file.
        _ = try LinkedSmartObjectIO.retag(original,layerID:layerID,source:object,title:"Convert to Linked")
        let staged=Task.detached(priority:.userInitiated){try LinkedArtworkExport(url:url,data:object.data)}
        let export=try await withTaskCancellationHandler{try await staged.value}onCancel:{staged.cancel()}
        try Task.checkCancellation()
        guard self.document==original,self.sessionGeneration==session,self.layerPanelGeneration==panel else{throw CraftError.invalid("The document changed before the source could be saved.")}
        let writer=Task.detached(priority:.userInitiated){try export.commit()}
        try await withTaskCancellationHandler{try await writer.value}onCancel:{writer.cancel()};sourceSaved=true
        try Task.checkCancellation()
        guard self.document==original,self.sessionGeneration==session,self.layerPanelGeneration==panel else{throw CraftError.invalid("The document changed before conversion completed.")}
        let grant=try registry.authorize(url)
        let worker=Task.detached(priority:.userInitiated){()throws->PreparedEdit in
          let file=try LinkedArtworkRead.read(grant)
          var linked=try object.linked(to:file.reference);linked.fileName=file.fileName
          let command=try LinkedSmartObjectIO.retag(original,layerID:layerID,source:linked,title:"Convert to Linked")
          let edit=try PreparedEdit(command:command,document:original)
          guard try LinkedArtworkRead.signature(grant)==file.signature else{throw DocumentPersistenceConflict.changed};return edit
        }
        let edit=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard self.document==original,self.sessionGeneration==session,self.layerPanelGeneration==panel,registry.stillAuthorizes(grant)else{throw CraftError.invalid("The document or source authorization changed before conversion completed.")}
        try self.executeCompositePreparedEdit(edit,allowLinkedSmartObject:true)
        if self.document != original{self.onChange?(.changeDone)};self.status="Convert to Linked";self.synchronizeLinkedArtwork()
      }catch {
        // A successfully exported user-selected file is retained even if model commit fails.
        if sourceSaved{self.error="The artwork file was saved, but the document was not converted. " + error.localizedDescription}
        else if !(error is CancellationError){self.error=error.localizedDescription}
      }
    }
  }
}
extension AppDelegate {
  @objc func placeLinked(){store?.placeLinked()}
  @objc func relinkSmartObject(){store?.placeLinked(replacing:true)}
  @objc func updateLinkedSmartObject(){store?.updateLinkedArtwork()}
  @objc func updateAllLinkedSmartObjects(){store?.updateLinkedArtwork(all:true)}
  @objc func convertLinkedSmartObject(){store?.convertToLinkedArtwork()}
  @objc func embedLinkedSmartObject(){store?.embedLinkedArtwork()}
  @objc func revealLinkedSmartObject(){store?.revealLinkedArtwork()}
}
