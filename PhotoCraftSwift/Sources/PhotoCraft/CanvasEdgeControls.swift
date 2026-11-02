import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

@MainActor @Observable final class TrimDraft:Identifiable {
  let id=UUID(),original:CraftDocument,generation:UUID,session:UUID
  var options=TrimOptions()
  var error:String?
  init(store:EditorStore){original=store.document;generation=store.layerPanelGeneration;session=store.sessionGeneration}
}
extension EditorStore {
  func canUseCanvasEdges(_ operation:CanvasEdgeOperation)->Bool {
    canBeginLayerCreation && !editingComponent && isCompositeColorTarget && !editingMask && !smartFilterMaskEditing && CanvasEdgePreparation.unavailableReason(document,operation:operation)==nil
  }
  func beginTrim(){finishLayerName();guard canUseCanvasEdges(.trim(.init())) else{return};trimDraft=TrimDraft(store:self)}
  func cancelTrim(){trimDraft=nil}
  func commitTrim(_ draft:TrimDraft){
    guard trimDraft === draft,draft.options.hasEdges else{return}
    guard document==draft.original,layerPanelGeneration==draft.generation,sessionGeneration==draft.session else{draft.error="The source changed. Cancel and reopen Trim.";return}
    let operation=CanvasEdgeOperation.trim(draft.options);trimDraft=nil;applyCanvasEdges(operation)
  }
  func applyCanvasEdges(_ operation:CanvasEdgeOperation){
    guard canUseCanvasEdges(operation) else{return}
    let prepare=canvasEdgePreparation,background=backgroundColor
    performGeometry(label:operation.label,prepare:{try prepare($0,operation,background)})
  }
}
struct TrimSheet:View {
  @Bindable var store:EditorStore
  @Bindable var draft:TrimDraft
  var body:some View {
    VStack(alignment:.leading,spacing:16){
      Text("Trim").font(.headline)
      GroupBox("Based On") {
        Picker("Based On",selection:$draft.options.basis){
          Text("Transparent Pixels").tag(TrimOptions.Basis.transparent)
          Text("Top Left Pixel Color").tag(TrimOptions.Basis.topLeft)
          Text("Bottom Right Pixel Color").tag(TrimOptions.Basis.bottomRight)
        }.pickerStyle(.radioGroup).labelsHidden().frame(maxWidth:.infinity,alignment:.leading)
      }
      GroupBox("Trim Away") {HStack{
        Toggle("Top",isOn:$draft.options.top);Toggle("Bottom",isOn:$draft.options.bottom)
        Toggle("Left",isOn:$draft.options.left);Toggle("Right",isOn:$draft.options.right)
      }.padding(4)}
      if let error=draft.error {Text(error).foregroundStyle(.red)}
      HStack{Spacer();Button("Cancel"){store.cancelTrim()}.keyboardShortcut(.cancelAction);Button("OK"){store.commitTrim(draft)}.keyboardShortcut(.defaultAction).disabled(!draft.options.hasEdges)}
    }.padding(20).frame(width:420)
  }
}
extension AppDelegate {
  @objc func trimImage(){store?.beginTrim()}
  @objc func revealAll(){store?.applyCanvasEdges(.revealAll)}
}
