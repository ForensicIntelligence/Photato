import AppKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import SwiftUI

@MainActor extension EditorStore {
  func prepareGeneratedVariation() {
    guard !aiBusy,let layer=activeLayer,GeneratedVariations.canAppend(layer,in:document),
      let record=try? GeneratedImageStorage.record(layer) else{return}
    prompt=record.initialPrompt;imageGenerationIntent = .image;imageGenerationTargetLayerID=layer.id
    imageReference=nil;imageReferenceUse = .inspiration;aiWorkspaceSection = .image;aiError=nil;showAI=true
  }
  func deleteGeneratedVariation(_ id:UUID) {
    guard canChooseSmartObjectComp,let layer=activeLayer else{return}
    performGeometry(label:"Delete Generated Variation",allowLinkedSmartObject:true) { original in
      try GeneratedVariations.deleting(id,from:layer.id,in:original)
    }
  }
}

struct GeneratedVariationControls:View {
  @Bindable var store:EditorStore
  let layer:Layer
  @State private var thumbnails:[UUID:CGImage]=[:]
  @State private var previewError:String?
  private var index:GeneratedVariations.Index? {try? GeneratedVariations.read(layer)}
  private var previewIdentity:String {layer.smartObject?.dataFingerprint ?? "none"}
  var body:some View {
    if let record=try? GeneratedImageStorage.record(layer) {
      VStack(alignment:.leading,spacing:8) {
        Text(record.initialPrompt).font(.caption).lineLimit(3).textSelection(.enabled)
        if let index {
          Text("Variations").font(.caption.weight(.semibold))
          ScrollView {LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:3),spacing:6) {
            ForEach(Array(index.entries.enumerated()),id:\.element.id) {number,entry in
              VStack(spacing:3) {
                Button {store.chooseSmartObjectComp(entry.id)} label:{
                  ZStack {
                    Rectangle().fill(.secondary.opacity(0.15))
                    if let image=thumbnails[entry.id] {Image(nsImage:NSImage(cgImage:image,size:.zero)).resizable().scaledToFit()}
                    else {Image(systemName:"photo").foregroundStyle(.secondary)}
                  }.frame(height:64).overlay(Rectangle().stroke(selected(entry,index:index) ? Color.accentColor:.clear,lineWidth:2))
                }.buttonStyle(.plain).disabled(!store.canChooseSmartObjectComp)
                  .accessibilityLabel("Variation \(number+1)")
                  .accessibilityValue(selected(entry,index:index) ? "Selected":"Not selected")
                  .accessibilityIdentifier("generatedVariations.choose.\(entry.id.uuidString)")
                HStack {
                  Text("\(number+1)").font(.caption2)
                  Spacer(minLength:1)
                  Button {store.deleteGeneratedVariation(entry.id)} label:{Image(systemName:"trash")}
                    .buttonStyle(.plain).disabled(!store.canChooseSmartObjectComp)
                    .help("Delete variation \(number+1)")
                    .accessibilityLabel("Delete variation \(number+1)")
                }
              }
            }
          }}.frame(height:min(230,CGFloat((index.entries.count+2)/3)*86))
        }
        Button("Generate…") {store.prepareGeneratedVariation()}
          .disabled(!LocalAI.imageCapability.available || !store.canStartImageGeneration || !GeneratedVariations.canAppend(layer,in:store.document))
          .accessibilityLabel("Generate another variation")
        if let previewError {Text(previewError).font(.caption2).foregroundStyle(.secondary)}
      }.padding(.vertical,8)
      .task(id:previewIdentity) {
        let source=layer
        let task=Task.detached(priority:.utility){try GeneratedVariations.thumbnails(source)}
        do {
          let result=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
          try Task.checkCancellation();thumbnails=result.images;previewError=nil
        }catch {if !(error is CancellationError){previewError=error.localizedDescription}}
      }
    }else if layer.sourceTags?[GeneratedVariations.key] != nil {
      Label("Variation data unavailable",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
    }
  }
  private func selected(_ entry:GeneratedVariations.Entry,index:GeneratedVariations.Index)->Bool {
    (layer.smartObject?.layerComps?.selectedID ?? index.lastDocumentStateID)==entry.id
  }
}

enum GeneratedVariationAPI {
  static var stateSchema:[String:Any] {
    ["anyOf":[["type":"null"],BrushAPI.object([
      "layerID":VariablesAPI.uuid,"selectedCompID":VariablesAPI.uuid,
      "entries":["type":"array","minItems":1,"maxItems":LayerComps.maximumComps,"items":BrushAPI.object([
        "compID":VariablesAPI.uuid,"requestID":VariablesAPI.uuid,"initialPrompt":["type":"string"],
        "originalSHA256":["type":"string","pattern":"^[0-9a-f]{64}$"]],required:["compID","requestID","initialPrompt","originalSHA256"]) ]
    ],required:["layerID","selectedCompID","entries"])]]
  }
  static var capabilities:[String:Any] {
    ["prepare":"POST document/ai prepare with targetLayerID equal to the active generated layer; omitted/null retains new-layer placement. Native approval still starts every model request.",
     "selectionCommand":"smartObject.layerComp","selection":"Use a reported compID. Selection remains available without any model or network and shares existing source-bound native/API history preparation.",
     "deleteOperation":"deleteVariation","storage":"Embedded native Smart Object with one generated original and working raster per source layer, and visibility-only Layer Comps. Descriptive record index PtGV is checked against source bytes. Existing Smart Object64MiB encoded/256MiB owned-content and native Layer Comp limits apply. No automatic purge or fabricated model/seed.",
     "identity":"Adding/deleting a variation gives that instance a new embedded source identity, preserving other duplicated instances. Switching retains parent transform/mask/style/warp/filter state. Native archives retain all alternatives and original bytes.",
     "processing":"New images fit the original variant rectangle using the existing color conversion and bicubic cover placement. Provider dimensions/identity/reference conditioning and output equality are not guaranteed.",
     "remaining":"Native PSD generative-layer exchange, Generate Similar conditioning, Enhance Detail, voting/favorites, broad source-contents edits, provider output/default/platform/performance qualification and full AI07 remain open.",
     "adobe":"The pinned Firefly contract has no interactive system-result variation-layer endpoint. Existing compatible resource jobs remain separate; no route or proprietary model is invented."]
  }
  static func state(_ layer:Layer?)->Any {
    guard let layer,let index=try? GeneratedVariations.read(layer)else{return NSNull()}
    return ["layerID":layer.id.uuidString,"selectedCompID":(layer.smartObject?.layerComps?.selectedID ?? index.lastDocumentStateID).uuidString,
      "entries":index.entries.map{["compID":$0.id.uuidString,"requestID":$0.record.requestID.uuidString,
        "initialPrompt":$0.record.initialPrompt,"originalSHA256":$0.record.originalSHA256]}]as[String:Any]
  }
}
