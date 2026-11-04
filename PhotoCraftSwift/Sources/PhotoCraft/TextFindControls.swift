import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class TextFindWorkspace:Identifiable {
  let id=UUID()
  var source:CraftDocument
  let initialLayerID:UUID?
  let initialPosition:Int
  let canChooseAllLayers:Bool
  var find=""
  var replacement=""
  var caseSensitive=false
  var wholeWord=false
  var forward=true
  var allLayers:Bool
  var busy=false
  var replacing=false
  var current:TextSearchMatch?
  var anchorID:UUID?
  var position=0
  var lastSettings:TextSearchSettings?
  var lastForward=true
  var lastAll=true
  var message:String?
  var error:String?
  @ObservationIgnored var task:Task<Void,Never>?
  init(source:CraftDocument,position:Int) {
    self.source=source;initialLayerID=source.activeLayerID;initialPosition=position
    if case .text=source.layers.first(where:{$0.id==source.activeLayerID})?.content {canChooseAllLayers=false;allLayers=false}
    else {canChooseAllLayers=true;allLayers=true}
  }
  var settings:TextSearchSettings {.init(find:find,caseSensitive:caseSensitive,wholeWord:wholeWord)}
  var scopeID:UUID? {allLayers ? nil:initialLayerID}
  var preview:AttributedString? {
    guard let current,let layer=source.layers.first(where:{$0.id==current.layerID}),case .text(let text)=layer.content else{return nil}
    let string=text.text as NSString
    guard current.location<=string.length,current.length<=string.length-current.location else{return nil}
    let start=max(0,current.location-60),end=min(string.length,current.location+current.length+60)
    let range=string.rangeOfComposedCharacterSequences(for:NSRange(location:start,length:end-start))
    let value=NSMutableAttributedString(string:string.substring(with:range))
    value.addAttribute(.backgroundColor,value:NSColor.systemYellow.withAlphaComponent(0.35),range:NSRange(location:current.location-range.location,length:current.length))
    return AttributedString(value)
  }
}
extension EditorStore {
  var canBeginTextFind:Bool {
    !geometryBusy && !aiBusy && historyOperation==nil && !coalescingChanges && !editingComponent && !editingMask
      && (typeEditingDraft != nil || canBeginLayerCreation)
      && ((try? NativeTextSearch.layers(in:document).isEmpty)==false)
  }
  func beginTextFind() {
    guard canBeginTextFind else{return}
    let position=typeEditor?.selectedRange().location ?? 0
    guard finishType() else{return}
    textFindWorkspace=TextFindWorkspace(source:document,position:position)
  }
  func closeTextFind() {
    guard let workspace=textFindWorkspace else{return}
    workspace.task?.cancel()
    if workspace.replacing {geometryBusy=false;geometryTask=nil}
    textFindWorkspace=nil;render()
  }
  func findNextText(_ workspace:TextFindWorkspace) {
    guard textFindWorkspace === workspace,!workspace.busy else{return}
    do {
      let settings=workspace.settings;try settings.validate()
      guard workspace.source==document else{throw CraftError.invalid("The document changed. Close and reopen Find and Replace Text.")}
      if workspace.lastSettings != settings || workspace.lastForward != workspace.forward || workspace.lastAll != workspace.allLayers {
        workspace.anchorID=workspace.scopeID;workspace.position=workspace.forward && !workspace.allLayers ? workspace.initialPosition:0
        workspace.lastSettings=settings;workspace.lastForward=workspace.forward;workspace.lastAll=workspace.allLayers;workspace.current=nil
      }
      let source=document,scope=workspace.scopeID,anchor=workspace.anchorID,position=workspace.position
      workspace.busy=true;workspace.error=nil
      workspace.task=Task { [weak self,weak workspace] in
        let worker=Task.detached(priority:.userInitiated) { ()throws->TextSearchMatch? in
          let layers=try NativeTextSearch.layers(in:source,layerID:scope)
          let first=anchor.flatMap{id in layers.firstIndex{$0.id==id}} ?? 0
          for (index,layer) in layers.enumerated() where index>=first {
            try Task.checkCancellation()
            let found=try NativeTextSearch.scan(source,settings:settings,layerID:layer.id,start:index==first ? position:0,limit:1)
            if let match=found.matches.first{return match}
          }
          return nil
        }
        do {
          let found=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation()
          guard let self,let workspace,self.textFindWorkspace === workspace else{return}
          guard self.document==source else{throw CraftError.invalid("The document changed during text search.")}
          workspace.current=found
          if let found {workspace.anchorID=found.layerID;workspace.position=found.location+found.length;workspace.message="\(found.layerName) · UTF-16 \(found.location)–\(found.location+found.length)"}
          else {workspace.anchorID=scope;workspace.position=workspace.forward && !workspace.allLayers ? workspace.initialPosition:0;workspace.message="No further matches. Find Next starts the search again."}
        }catch is CancellationError{}catch{workspace?.error=error.localizedDescription}
        if let self,let workspace,self.textFindWorkspace === workspace {workspace.busy=false}
      }
    }catch{workspace.error=error.localizedDescription}
  }
  func changeFoundText(_ workspace:TextFindWorkspace,all:Bool = false,findNext:Bool = false) {
    guard textFindWorkspace === workspace,!workspace.busy,!geometryBusy else{return}
    do {
      let settings=workspace.settings;try settings.validate()
      guard workspace.source==document else{throw CraftError.invalid("The document changed. Close and reopen Find and Replace Text.")}
      var target=workspace.scopeID,start=workspace.forward && !workspace.allLayers ? workspace.initialPosition:0
      if !all {
        guard let match=workspace.current,workspace.lastSettings==settings,
          let layer=document.layers.first(where:{$0.id==match.layerID}),case .text(let text)=layer.content,
          try settings.ranges(in:text.text).contains(NSRange(location:match.location,length:match.length)) else{throw CraftError.invalid("Use Find Next to select a current match.")}
        target=match.layerID;start=match.location
      }
      let request=RecordedTextReplacement(settings:settings,replacement:workspace.replacement,
        target:target.map{.init($0,in:document,preferActive:false)},start:start,replaceAll:all)
      try request.validate()
      let source=document,generation=layerPanelGeneration,sessionID=sessionGeneration
      let nextPosition=workspace.current.map{$0.location+workspace.replacement.utf16.count}
      let nextLayer=workspace.current?.layerID
      workspace.error=nil;workspace.busy=true;workspace.replacing=true;geometryBusy=true;renderTask?.cancel()
      workspace.task=Task { [weak self,weak workspace] in
        let worker=Task.detached(priority:.userInitiated){try TextReplacementPreparation.prepare(source,request:request)}
        do {
          let prepared=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()});try Task.checkCancellation()
          guard let self,let workspace,self.textFindWorkspace === workspace else{return}
          guard self.layerPanelGeneration==generation,self.sessionGeneration==sessionID,self.document==source else{throw CraftError.invalid("The document changed during text replacement.")}
          try self.executeCompositePreparedEdit(PreparedEdit(command:prepared.command,document:source))
          if self.document != source{self.onChange?(.changeDone)}
          workspace.source=self.document;workspace.current=nil
          workspace.lastSettings=settings;workspace.lastForward=workspace.forward;workspace.lastAll=workspace.allLayers
          if !all,let nextPosition {workspace.anchorID=nextLayer;workspace.position=nextPosition}
          else{workspace.anchorID=workspace.scopeID;workspace.position=0}
          workspace.message="Replaced \(prepared.occurrences) occurrence\(prepared.occurrences==1 ? "":"s") in \(prepared.layers) changed layer\(prepared.layers==1 ? "":"s")."
        }catch is CancellationError{}catch{workspace?.error=error.localizedDescription}
        guard let self,let workspace,self.textFindWorkspace === workspace else{return}
        workspace.busy=false;workspace.replacing=false;self.geometryBusy=false;self.geometryTask=nil;self.render()
        if findNext,workspace.error==nil{self.findNextText(workspace)}
      }
      geometryTask=workspace.task
    }catch{workspace.error=error.localizedDescription}
  }
}
struct TextFindSheet:View {
  @Bindable var store:EditorStore
  @Bindable var workspace:TextFindWorkspace
  var body:some View {
    VStack(alignment:.leading,spacing:14) {
      Text("Find and Replace Text").font(.headline)
      HStack(alignment:.top,spacing:20) {
        VStack(alignment:.leading,spacing:12) {
          LabeledContent("Find What:"){TextField("Find What",text:$workspace.find).accessibilityIdentifier("textFind.find")}
          LabeledContent("Change To:"){TextField("Change To",text:$workspace.replacement).accessibilityIdentifier("textFind.replacement")}
          Toggle("Search All Layers",isOn:$workspace.allLayers).disabled(!workspace.canChooseAllLayers)
          Toggle("Forward",isOn:$workspace.forward)
          Toggle("Case Sensitive",isOn:$workspace.caseSensitive)
          Toggle("Whole Word Only",isOn:$workspace.wholeWord)
          if let preview=workspace.preview {Text(preview).font(.system(.body,design:.monospaced)).lineLimit(4).textSelection(.enabled)}
        }.textFieldStyle(.roundedBorder).disabled(workspace.busy)
        VStack(alignment:.trailing,spacing:10) {
          Button("Find Next"){store.findNextText(workspace)}.keyboardShortcut(.defaultAction).disabled(workspace.find.isEmpty || workspace.busy)
          Button("Change"){store.changeFoundText(workspace)}.disabled(workspace.current==nil || workspace.busy)
          Button("Change/Find"){store.changeFoundText(workspace,findNext:true)}.disabled(workspace.current==nil || workspace.busy)
          Button("Change All"){store.changeFoundText(workspace,all:true)}.disabled(workspace.find.isEmpty || workspace.busy)
        }.buttonStyle(.bordered)
      }
      if workspace.busy {ProgressView().controlSize(.small)}
      if let message=workspace.message{Text(message).font(.caption).foregroundStyle(.secondary)}
      if let error=workspace.error{Text(error).font(.caption).foregroundStyle(.red)}
      HStack{Spacer();Button("Done"){store.closeTextFind()}.keyboardShortcut(.cancelAction)}
    }.padding(20).frame(width:570)
  }
}
@MainActor extension AppDelegate {@objc func findReplaceText(){store?.beginTextFind()}}
