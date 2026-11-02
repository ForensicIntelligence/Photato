import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

struct SelectionRecall:Sendable {
  let documentID:UUID
  let width:Int,height:Int
  let rectangle:IntRect?
  let mask:SelectionMask?
  init(_ document:CraftDocument){documentID=document.id;width=document.width;height=document.height;rectangle=document.selection;mask=document.selectionMask}
  func command(in document:CraftDocument)throws->Command {
    guard document.id==documentID,document.width==width,document.height==height else {throw CraftError.invalid("The previous selection belongs to another canvas.")}
    let coverage=try mask ?? rectangle.map{try SelectionMask.make(.rectangle($0),width:width,height:height,antiAlias:false)}
    guard let coverage else {throw CraftError.invalid("No previous selection is available.")};return .reselectedSelection(coverage)
  }
}
@MainActor @Observable final class SelectionModifyDraft:Identifiable {
  let id=UUID()
  let original:CraftDocument
  var settings:SelectionModification
  var busy=false
  var error:String?
  var task:Task<Void,Never>?
  var closed=false
  init(_ original:CraftDocument,operation:SelectionModification.Kind){self.original=original;settings = .init(operation)}
  func close(){closed=true;task?.cancel()}
}
@MainActor extension EditorStore {
  func rememberDeselectedSelection(from old:CraftDocument,to new:CraftDocument) {
    guard old.id==new.id,old.width==new.width,old.height==new.height else {selectionRecall=nil;return}
    if old.selection != nil,new.selection==nil {selectionRecall=SelectionRecall(old)}
  }
  var canManageSelection:Bool {!geometryBusy && !aiBusy && !hasToneDraft && transformDraft==nil && historyOperation==nil}
  var canModifySelection:Bool {canManageSelection && document.selection != nil}
  var canReselect:Bool {canManageSelection && document.selection==nil && selectionRecall.map{$0.documentID==document.id && $0.width==document.width && $0.height==document.height} == true}
  func beginSelectionModify(_ operation:SelectionModification.Kind) {
    guard canModifySelection else{return};finishNumericField();finishLayerName();selectionModifyDraft = .init(document,operation:operation)
  }
  func cancelSelectionModify(){selectionModifyDraft?.close();selectionModifyDraft=nil}
  func commitSelectionModify() {
    guard let draft=selectionModifyDraft,!draft.busy,!draft.closed else{return}
    do{try draft.settings.validate()}catch{draft.error=error.localizedDescription;return}
    guard document==draft.original else {draft.error="The document changed. Reopen this selection command.";return}
    draft.busy=true;let original=draft.original,settings=draft.settings,prepare=selectionModificationPreparation
    draft.task=Task { [weak self,weak draft] in
      do {
        let worker=Task.detached(priority:.userInitiated){try PreparedEdit(command:prepare(original,settings),document:original)}
        let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,let draft,self.selectionModifyDraft === draft,self.document==original else {throw CraftError.invalid("The document changed during selection refinement.")}
        try self.executeCompositePreparedEdit(result);if self.document != original {self.onChange?(.changeDone)}
        self.selectionModifyDraft=nil;draft.close();self.status=settings.operation.title+" Selection";self.render()
      }catch{if !Task.isCancelled {draft?.error=error.localizedDescription}}
      draft?.busy=false
    }
  }
  func reselectPixels() {
    guard canReselect,let recall=selectionRecall else{return}
    let original=document,generation=layerPanelGeneration,session=sessionGeneration
    geometryBusy=true
    geometryTask=Task { [weak self] in
      defer{if let self,self.layerPanelGeneration==generation {self.geometryBusy=false;self.render()}}
      do {
        let worker=Task.detached(priority:.userInitiated){try PreparedEdit(command:recall.command(in:original),document:original)}
        let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,self.document==original,self.layerPanelGeneration==generation,self.sessionGeneration==session else {throw CraftError.invalid("The document changed before Reselect.")}
        try self.executeCompositePreparedEdit(result);if self.document != original {self.onChange?(.changeDone)};self.status="Reselect"
      }catch{if !Task.isCancelled {self?.error=error.localizedDescription}}
    }
  }
}
struct SelectionModifySheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:SelectionModifyDraft
  var field:String {switch draft.settings.operation {case .border:"Width";case .smooth:"Sample Radius";case .expand:"Expand By";case .contract:"Contract By"}}
  var body:some View {
    VStack(alignment:.leading,spacing:18) {
      Text(draft.settings.operation.title+" Selection").font(.headline)
      HStack {Text(field+":");TextField(field,value:$draft.settings.amount,format:.number).textFieldStyle(.roundedBorder).frame(width:75);Text("pixels")}.disabled(draft.busy)
      Toggle("Apply effect at canvas bounds",isOn:$draft.settings.atCanvasBounds).disabled(draft.busy)
      if let error=draft.error {Text(error).font(.caption).foregroundStyle(.red)}
      HStack {if draft.busy {ProgressView().controlSize(.small)};Spacer();Button("Cancel"){store.cancelSelectionModify()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitSelectionModify()}.keyboardShortcut(.defaultAction).disabled(draft.busy || !(1...draft.settings.operation.maximum).contains(draft.settings.amount))}
    }.padding(24).frame(width:360).onDisappear{draft.close()}
  }
}
extension AppDelegate {
  @objc func borderSelection(){store?.beginSelectionModify(.border)}
  @objc func smoothSelection(){store?.beginSelectionModify(.smooth)}
  @objc func expandSelection(){store?.beginSelectionModify(.expand)}
  @objc func contractSelection(){store?.beginSelectionModify(.contract)}
  @objc func reselectPixels(){store?.reselectPixels()}
}
