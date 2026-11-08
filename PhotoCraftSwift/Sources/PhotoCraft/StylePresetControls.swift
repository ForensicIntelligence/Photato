import AppKit
import SwiftUI
import PhotoCraftCore

struct StylePresetSaveSource {
  let document:CraftDocument
  let layerID:UUID
  let style:LayerStyle
  let session:UUID
  let generation:UUID
  let draftSession:UUID?
  @MainActor init(_ store:EditorStore) throws {
    guard let layer=store.activeLayer,store.layerStyleDraft?.globalLightOnly != true else {throw CraftError.invalid("Choose a layer with style settings.")}
    document=store.document;layerID=layer.id;style=store.layerStyleDraft?.style ?? layer.style ?? LayerStyle()
    session=store.sessionGeneration;generation=store.layerPanelGeneration;draftSession=store.layerStyleDraft?.sessionID
  }
  @MainActor func matches(_ store:EditorStore)->Bool {
    store.sessionGeneration==session && store.layerPanelGeneration==generation && store.document==document && store.layerStyleDraft?.sessionID==draftSession
  }
}
extension EditorStore {
  var stylePresetDestination:UUID? {
    guard styles.selected.count==1,let node=styles.selected.first.flatMap(styles.state.node) else{return nil}
    return node.isGroup ? node.id:node.parentID
  }
  func saveStylePreset(_ source:StylePresetSaveSource,name:String,includeEffects:Bool=true,includeBlending:Bool=false,parent:UUID?=nil) async throws -> UUID? {
    guard source.matches(self) else {throw CraftError.invalid("The style source changed. Reopen New Style.")}
    let preset=try StylePreset.capture(layerID:source.layerID,in:source.document,includesEffects:includeEffects,includesBlending:includeBlending,styleOverride:source.style)
    return try await styles.edit(.save(name,preset,parent:parent),authorize:{[weak self] in self.map(source.matches) ?? false})
  }
  func canApplyStylePreset(_ id:UUID)->Bool {
    guard canBeginLayerCreation,!editingComponent,!editingMask,!styles.busy,!styles.loadFailed,
      let preset=styles.state.node(id)?.preset,!groupSelectionIDs.isEmpty else {return false}
    return groupSelectionIDs.allSatisfy {id in
      guard let layer=document.layers.first(where:{$0.id==id}),!document.isLocked(id) else{return false}
      if preset.includesEffects && !preset.style.isChannelBlendingOnly {if case .adjustment=layer.content{return false};return document.width<=8_388_608/document.height}
      return true
    }
  }
  func applyStylePreset(_ id:UUID) {
    guard canApplyStylePreset(id),let preset=styles.state.node(id)?.preset else{return}
    let ids=groupSelectionIDs
    performGeometry(label:"Apply Style",prepare:{source in .layerStyles(try preset.edit(layerIDs:ids,in:source))})
  }
  func styleLibraryOperation(_ mutation:StyleLibraryMutation) {
    guard !styles.busy else{return}
    let session=sessionGeneration,owner=document.id,generation=layerPanelGeneration
    styleLibraryTask=Task { [weak self] in
      guard let self else{return}
      do {_=try await self.styles.edit(mutation,authorize:{[weak self] in self?.sessionGeneration==session && self?.document.id==owner && self?.layerPanelGeneration==generation})}
      catch is CancellationError {self.status="Style library operation cancelled"}
      catch {self.error=error.localizedDescription}
    }
  }
  func beginNewStylePreset() {
    do {
      guard !styles.busy,!styles.loadFailed else {throw CraftError.invalid("Resolve the saved style library error or wait for it to finish.")}
      let source=try StylePresetSaveSource(self),parent=stylePresetDestination
      let alert=NSAlert();alert.messageText="New Style";alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel")
      let name=NSTextField(string:"Style \(styles.state.nodes.filter{!$0.isGroup}.count+1)");name.placeholderString="Style name";name.setAccessibilityLabel("Style name")
      let effects=NSButton(checkboxWithTitle:"Include Layer Effects",target:nil,action:nil);effects.state = .on
      let blending=NSButton(checkboxWithTitle:"Include Layer Blending Options",target:nil,action:nil)
      let stack=NSStackView(views:[NSTextField(labelWithString:"Name:"),name,effects,blending]);stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=8;stack.frame=NSRect(x:0,y:0,width:320,height:114);name.widthAnchor.constraint(equalToConstant:320).isActive=true
      alert.accessoryView=stack
      guard let window=NSApp.keyWindow else{return}
      alert.beginSheetModal(for:window){[weak self]response in
        guard response == .alertFirstButtonReturn,let self else{return}
        let text=name.stringValue,a=effects.state == .on,b=blending.state == .on
        self.styleLibraryTask=Task { [weak self] in
          guard let self else{return}
          do {_=try await self.saveStylePreset(source,name:text,includeEffects:a,includeBlending:b,parent:parent)}
          catch {self.error=error.localizedDescription}
        }
      }
      window.attachedSheet?.makeFirstResponder(name)
    }catch{self.error=error.localizedDescription}
  }
  func beginStyleLibraryName(group:Bool=false,rename:UUID?=nil) {
    guard !styles.busy,!styles.loadFailed,let window=NSApp.keyWindow else{return}
    let captured=styles.revision,parent=stylePresetDestination
    let alert=NSAlert();alert.messageText=rename==nil ? "New Style Group":"Rename Style";alert.addButton(withTitle:"OK");alert.addButton(withTitle:"Cancel")
    let name=NSTextField(string:rename.flatMap(styles.state.node)?.name ?? "New Group");name.setAccessibilityLabel("Name");name.frame=NSRect(x:0,y:0,width:300,height:24);let stack=NSStackView(views:[NSTextField(labelWithString:"Name:"),name]);stack.orientation = .vertical;stack.alignment = .leading;stack.frame=NSRect(x:0,y:0,width:300,height:50);alert.accessoryView=stack
    alert.beginSheetModal(for:window){[weak self]response in
      guard response == .alertFirstButtonReturn,let self,self.styles.revision==captured else{return}
      self.styleLibraryOperation(rename.map{.rename($0,name.stringValue)} ?? .group(name.stringValue,parent:parent))
    }
  }
  func confirmStylePresetDeletion() {
    guard !styles.busy,!styles.selected.isEmpty,let window=NSApp.keyWindow else{return}
    let ids=styles.selected,revision=styles.revision,alert=NSAlert();alert.messageText="Delete selected styles?";alert.informativeText="Groups and their contents will be removed from the preset library. Styles already applied to documents are retained.";alert.addButton(withTitle:"Delete");alert.addButton(withTitle:"Cancel")
    alert.beginSheetModal(for:window){[weak self]response in guard response == .alertFirstButtonReturn,let self,self.styles.revision==revision else{return};self.styleLibraryOperation(.delete(ids))}
  }
}
struct StylesPanel:View {
  @Bindable var store:EditorStore
  var visible:[StyleLibraryNode] {(try? store.styles.state.ordered())?.filter{node in
    var parent=node.parentID
    while let id=parent {if store.styles.collapsed.contains(id){return false};parent=store.styles.state.node(id)?.parentID};return true
  } ?? []}
  var body:some View {
    VStack(spacing:0) {
      HStack {
        Text("Styles").font(.headline);Spacer()
        if store.styles.busy {ProgressView("Saving styles").controlSize(.small).labelsHidden().accessibilityLabel("Loading or saving style library")}
        Menu {
          Button("New Style…"){store.beginNewStylePreset()}.disabled(store.activeLayer==nil || store.layerStyleDraft?.globalLightOnly==true)
          Button("New Style Group…"){store.beginStyleLibraryName(group:true)}
          Button("Duplicate Styles"){store.styleLibraryOperation(.duplicate(store.styles.selected,parent:store.stylePresetDestination,before:nil))}.disabled(store.styles.selected.isEmpty)
          if store.styles.selected.count==1,let id=store.styles.selected.first {Button("Rename Style…"){store.beginStyleLibraryName(rename:id)}}
          Menu("Move to Group") {
            Button("Root"){store.styleLibraryOperation(.move(store.styles.selected,parent:nil,before:nil))}
            ForEach(store.styles.state.nodes.filter(\.isGroup)){node in Button(node.name){store.styleLibraryOperation(.move(store.styles.selected,parent:node.id,before:nil))}.disabled(store.styles.selected.contains(node.id))}
          }.disabled(store.styles.selected.isEmpty)
          Button("Delete Styles…"){store.confirmStylePresetDeletion()}.disabled(store.styles.selected.isEmpty)
          Divider()
          Button("Import Styles…"){}.disabled(true).help("Adobe ASL style libraries are not supported yet")
          Button("Export Selected Styles…"){}.disabled(true).help("Adobe ASL style libraries are not supported yet")
        }label:{Label("Styles panel options",systemImage:"line.3.horizontal").labelStyle(.iconOnly)}.menuStyle(.borderlessButton).fixedSize()
      }.padding(8)
      if let error=store.styles.error {Text(error).font(.caption).foregroundStyle(.red).padding(8)}
      if visible.isEmpty {Text("Save a layer style to reuse it in other documents.").foregroundStyle(.secondary).font(.caption).padding(12).frame(maxWidth:.infinity,maxHeight:.infinity)}
      else {
        List(selection:Binding(get:{store.styles.selected},set:{ids in
          store.styles.selected=ids
          if ids.count==1,let id=ids.first,!NSEvent.modifierFlags.contains(.command),!NSEvent.modifierFlags.contains(.shift){store.applyStylePreset(id)}
        })) {
          ForEach(visible){node in
            HStack(spacing:6){
              if node.isGroup {Button {if !store.styles.collapsed.insert(node.id).inserted {store.styles.collapsed.remove(node.id)}}label:{Image(systemName:store.styles.collapsed.contains(node.id) ? "chevron.right":"chevron.down")}.buttonStyle(.plain).accessibilityLabel("Expand or collapse \(node.name)")}
              Label(node.name,systemImage:node.isGroup ? "folder":"square.stack.3d.up").lineLimit(1)
            }.padding(.leading,CGFloat(depth(node))*12).tag(node.id).help(node.name)
              .contextMenu {Button("Apply Style"){store.applyStylePreset(node.id)}.disabled(!store.canApplyStylePreset(node.id));Button("Rename…"){store.beginStyleLibraryName(rename:node.id)}}
          }
        }.listStyle(.inset).accessibilityLabel("Saved layer styles")
      }
      Divider()
      HStack {
        Button{store.beginStyleLibraryName(group:true)}label:{Label("New Style Group",systemImage:"folder.badge.plus").labelStyle(.iconOnly)}
        Button{store.beginNewStylePreset()}label:{Label("New Style",systemImage:"plus.square").labelStyle(.iconOnly)}.disabled(store.activeLayer==nil)
        Spacer()
        Button{store.confirmStylePresetDeletion()}label:{Label("Delete Styles",systemImage:"trash").labelStyle(.iconOnly)}.disabled(store.styles.selected.isEmpty)
      }.buttonStyle(.borderless).padding(8)
    }.disabled(store.styles.busy || store.styles.loadFailed).clipped()
  }
  private func depth(_ node:StyleLibraryNode)->Int {var p=node.parentID,n=0;while let id=p,n<StyleLibraryState.maximumDepth {n+=1;p=store.styles.state.node(id)?.parentID};return n}
}
@MainActor extension AppDelegate {
  @objc func stylesPanel() {
    guard store != nil,controller.documentWindows.canChangeDocument,controller.workspaces.error==nil else{return}
    do {try controller.workspaces.setPanelVisible(.styles,true)}catch{reportWorkspaceError(error)}
  }
  func validateStylesPanel(_ item:NSMenuItem)->Bool? {
    guard item.action == #selector(stylesPanel) else{return nil}
    let library=controller.workspaces
    item.state=library.panelDock.groups.contains{library.panelDock.visiblePanels(in:$0,visibility:library.layout.visibility).contains(.styles)} ? .on:.off
    return store != nil && controller.documentWindows.canChangeDocument && library.error==nil
  }
}
