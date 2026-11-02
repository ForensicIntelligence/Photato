import AppKit
import Darwin
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canEmbedAllLinkedArtwork:Bool {canManageLinkedArtwork && hasLinkedArtwork && document.layers.filter{$0.smartObject?.linkedSource != nil}.allSatisfy{!document.isImageLocked($0.id)}}
  var canPackageLinkedArtwork:Bool {canManageLinkedArtwork && hasLinkedArtwork && linkedArtworkDocumentURL != nil}
  func linkedArtworkGrants(needingOriginalsOnly:Bool=false)throws->[UUID:LinkedArtworkGrant] {
    var result:[UUID:LinkedArtworkGrant]=[:]
    for layer in document.layers {
      guard let source=layer.smartObject,let link=source.linkedSource,result[source.sourceID]==nil else{continue}
      if needingOriginalsOnly,!source.data.isEmpty,try layer.linkedSmartObjectPreview()==nil{continue}
      result[source.sourceID]=try linkedSourceRegistry.resolve(link,documentID:document.id,documentURL:linkedArtworkDocumentURL)
    }
    return result
  }
  func embedAllLinkedArtwork() {
    guard canEmbedAllLinkedArtwork else{return}
    let grants:[UUID:LinkedArtworkGrant]
    do{grants=try linkedArtworkGrants(needingOriginalsOnly:true)}catch{self.error=error.localizedDescription;return}
    let original=document,panel=layerPanelGeneration,session=sessionGeneration,registry=linkedSourceRegistry,operation=UUID()
    linkedArtworkOperationID=operation;geometryBusy=true;renderTask?.cancel()
    geometryTask=Task {[weak self]in
      guard let self else{return}
      defer{if self.linkedArtworkOperationID==operation && self.layerPanelGeneration==panel{self.linkedArtworkOperationID=nil;self.geometryBusy=false;self.geometryTask=nil;self.render()}}
      do {
        let worker=Task.detached(priority:.userInitiated){()throws->PreparedEdit in
          var files:[UUID:LinkedArtworkRead]=[:];for(id,grant)in grants{files[id]=try LinkedArtworkRead.read(grant)}
          let command=try LinkedSmartObjectIO.embed(original,originals:files.mapValues(\.data))
          let edit=try PreparedEdit(command:command,document:original)
          for file in files.values{guard try LinkedArtworkRead.signature(file.grant)==file.signature else{throw DocumentPersistenceConflict.changed}};return edit
        }
        let edit=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard self.document==original,self.layerPanelGeneration==panel,self.sessionGeneration==session,grants.values.allSatisfy({registry.stillAuthorizes($0)})else{throw CraftError.invalid("The document or artwork authorization changed.")}
        try self.executeCompositePreparedEdit(edit,allowLinkedSmartObject:true)
        if self.document != original{self.onChange?(.changeDone)};self.status="Embed All Linked";self.synchronizeLinkedArtwork()
      }catch is CancellationError{self.status="Embedding cancelled"}catch{self.error=error.localizedDescription}
    }
  }
  func publishLinkedPackage(parent:URL,options:LinkedPackageOptions,grants:[UUID:LinkedArtworkGrant],
    validatePublication:@escaping @MainActor () throws -> Void = {})async throws->PreparedLinkedPackage {
    guard canPackageLinkedArtwork else{throw CraftError.invalid("Save this document and finish the current interaction before packaging.")}
    let original=document,panel=layerPanelGeneration,session=sessionGeneration,registry=linkedSourceRegistry,operation=UUID()
    var completed=false
    let access=parent.startAccessingSecurityScopedResource();defer{if access{parent.stopAccessingSecurityScopedResource()}}
    linkedArtworkOperationID=operation;geometryBusy=true;status="Packaging linked artwork…"
    let worker=Task.detached(priority:.userInitiated){try PreparedLinkedPackage.prepare(original,grants:grants,parent:parent,options:options)}
    let observer=Task{await withTaskCancellationHandler{_ = try? await worker.value}onCancel:{worker.cancel()}};geometryTask=observer
    defer{if linkedArtworkOperationID==operation && layerPanelGeneration==panel{linkedArtworkOperationID=nil;geometryBusy=false;geometryTask=nil;if !completed{status="Packaging stopped"}}}
    let prepared=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
    guard !observer.isCancelled,document==original,layerPanelGeneration==panel,sessionGeneration==session,
      grants.values.allSatisfy({registry.stillAuthorizes($0)})else{throw CraftError.invalid("The document changed or packaging was cancelled.")}
    try validatePublication();try prepared.validateSources();try prepared.directory.commit();completed=true;status="Packaged linked artwork";return prepared
  }
  func presentLinkedPackage() {
    guard canPackageLinkedArtwork else{return}
    let original=document,panelGeneration=layerPanelGeneration,session=sessionGeneration
    let panel=NSOpenPanel();panel.title="Package";panel.prompt="Package";panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.canCreateDirectories=true
    let name=NSTextField(string:LinkedPackageOptions.safeName(document.name)+"-package"),format=NSPopUpButton(),update=NSButton(checkboxWithTitle:"Update Existing Folder",target:nil,action:nil)
    let formats:[DocumentIO.Format]=[.native,.psd,.psb];format.addItems(withTitles:["Photato","Photoshop PSD","Large Document PSB"])
    let grid=NSGridView(views:[[NSTextField(labelWithString:"Package Folder:"),name],[NSTextField(labelWithString:"Document Format:"),format],[NSTextField(labelWithString:""),update]])
    name.widthAnchor.constraint(equalToConstant:240).isActive=true;grid.rowSpacing=8;grid.setFrameSize(grid.fittingSize);panel.accessoryView=grid
    panel.message="Collect the document and linked files inside the selected location. Updating an existing folder replaces its packaged document and matching inventory; other files are preserved."
    panel.begin {[weak self] response in
      guard response == .OK,let parent=panel.url,let self,self.document==original,self.layerPanelGeneration==panelGeneration,self.sessionGeneration==session,self.canPackageLinkedArtwork else{return}
      let options=LinkedPackageOptions(name:name.stringValue,format:formats[format.indexOfSelectedItem],replaceExisting:update.state == .on)
      Task {[weak self]in
        guard let self else{return};let access=parent.startAccessingSecurityScopedResource();defer{if access{parent.stopAccessingSecurityScopedResource()}}
        do {
          let prepared=try await self.publishLinkedPackage(parent:parent,options:options,grants:self.linkedArtworkGrants())
          do{try self.linkedSourceRegistry.authorizePackage(prepared.folderURL,document:prepared.document,documentURL:prepared.documentURL)}
          catch{self.error="The package was saved. Locate its sources after opening the packaged document. "+error.localizedDescription}
        }catch{self.error=error.localizedDescription}
      }
    }
  }
  var hasRelativePackageLinks:Bool {document.layers.contains{layer in layer.smartObject?.linkedSource.map{LinkedSourceRegistry.isPackageReference($0.reference)}==true}}
  func locatePackageSources() {
    guard canManageLinkedArtwork,hasRelativePackageLinks,let documentURL=linkedArtworkDocumentURL else{return}
    let original=document,panelGeneration=layerPanelGeneration
    let panel=NSOpenPanel();panel.title="Locate Packaged Sources";panel.prompt="Authorize Package Sources";panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.directoryURL=documentURL.deletingLastPathComponent()
    panel.message="Choose this document's package folder to authorize its Links files."
    panel.begin{[weak self] response in
      guard response == .OK,let url=panel.url,let self,self.document==original,self.layerPanelGeneration==panelGeneration else{return}
      do{try self.linkedSourceRegistry.authorizePackage(url,document:original,documentURL:documentURL);self.synchronizeLinkedArtwork();Task{await self.linkedSourceController?.scan()}}
      catch{self.error=error.localizedDescription}
    }
  }
}
extension AppDelegate {
  @objc func embedAllLinkedSmartObjects(){store?.embedAllLinkedArtwork()}
  @objc func packageLinkedSmartObjects(){store?.presentLinkedPackage()}
}
extension AutomationService {
  func packageLinkedArtwork(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws->AutomationResponse {
    for (key,value)in command.parameters{_ = try BrushAPI.merge(value,schema:LinkedArtworkAPI.schema(key),path:key)}
    guard documentSavesEnabled,let parent=saveDirectoryURL else{throw AutomationFailure(status:403,message:"Enable local saving and select an API output folder before packaging.")}
    guard document.fileURL != nil else{throw AutomationFailure(status:409,message:"Save the document once before packaging.")}
    guard let format=DocumentIO.Format(rawValue:try command.string("format"))else{throw AutomationFailure(status:400,message:"Choose Photato, PSD or PSB package format.")}
    let options=LinkedPackageOptions(name:try command.string("name"),format:format,replaceExisting:try command.adjustmentBrushFlag("replace",false))
    do{try options.validate()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    let store=document.store,expectedToken=token,saveGeneration=documentSaveGeneration
    var grants:[UUID:LinkedArtworkGrant]=[:]
    for layer in store.document.layers {
      if let source=layer.smartObject,let link=source.linkedSource,grants[source.sourceID]==nil{grants[source.sourceID]=try linkedArtworkGrant(link,store:store)}
    }
    let captured=grants
    let prepared:PreparedLinkedPackage
    do {
      prepared=try await store.publishLinkedPackage(parent:parent,options:options,grants:grants,validatePublication:{[weak self]in
        guard let self,self.isRunning,self.token==expectedToken,self.documentSavesEnabled,self.documentSaveGeneration==saveGeneration,
          self.shares.contains(where:{$0.id==shareID && $0.document === document}),self.revision(store)==command.revision,
          captured.values.allSatisfy({grant in self.linkedArtworkAssets.values.contains{$0.id==grant.id && $0.generation==grant.generation}})else{throw AutomationFailure(status:409,message:"Package saving, sharing or source authorization was revoked.")}
      })
    }catch let recovery as LinkedPackageRecoveryRequired {return .json(["error":recovery.localizedDescription,"recoveryFolder":recovery.stagingName as Any? ?? NSNull()],status:409)
    }catch let failure as NSError where failure.domain==NSPOSIXErrorDomain && failure.code==Int(EEXIST){throw AutomationFailure(status:409,message:"The package folder exists. Choose a new folder name.")}
    // Only newly copied, already authorized sources are registered for desktop use.
    // Their private grants never become API-session approvals automatically.
    try? store.linkedSourceRegistry.authorizePackage(prepared.folderURL,document:prepared.document,documentURL:prepared.documentURL)
    return .json(["folder":options.name,"document":prepared.documentName,"manifest":prepared.directory.manifestName,"updatedExisting":prepared.directory.updatedExisting,"sourceCount":Set(prepared.sources.map(\.name)).count,"originalDocumentUnchanged":true])
  }
}
