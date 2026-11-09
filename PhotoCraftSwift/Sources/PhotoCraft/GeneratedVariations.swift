import AppKit
import Foundation
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging

/// Generated alternatives use an ordinary embedded native document and visibility
/// comps. The parent keeps the existing Smart Object geometry/effects pipeline.
/// This index is descriptive metadata, never provider attestation or executable data.
enum GeneratedVariations {
  static let key="PtGV"
  static let maximumIndexBytes=8*1024*1024
  static let resultKeys=[GeneratedImageStorage.recordKey,GeneratedImageStorage.originalKey,
    ImageGenerationReference.recordKey,GeneratedBackground.contextKey]
  struct Entry:Codable,Equatable,Identifiable,Sendable {
    let id:UUID
    let layerID:UUID
    let record:GenerationRecord
    let metadata:[String:Data]
  }
  struct Index:Codable,Equatable,Sendable {
    var version=1
    var sourceSHA256:String
    var lastDocumentStateID:UUID
    var entries:[Entry]
    func encoded()throws->Data {
      let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
      let bytes=try encoder.encode(self)
      guard bytes.count<=maximumIndexBytes else{throw CraftError.invalid("The generated-variation index exceeds its storage budget.")}
      return bytes
    }
  }
  static func read(_ layer:Layer)throws->Index? {
    guard let data=layer.sourceTags?[key]else{return nil}
    guard data.count<=maximumIndexBytes,let object=layer.smartObject,
      object.mediaType=="application/vnd.photato.document",object.linkedSource==nil,
      object.stackMode==nil,object.rawDevelopment==nil,object.pdfSource==nil else{
      throw CraftError.invalid("The generated-variation source is unavailable or was replaced.")
    }
    guard let raw=try JSONSerialization.jsonObject(with:data)as?[String:Any],
      Set(raw.keys)==["version","sourceSHA256","lastDocumentStateID","entries"],let rows=raw["entries"]as?[[String:Any]],
      rows.allSatisfy({Set($0.keys)==["id","layerID","record","metadata"]}) else{
      throw CraftError.unsupported("Unrepresented generated-variation index fields.")
    }
    let value=try JSONDecoder().decode(Index.self,from:data)
    guard value.version==1,!value.entries.isEmpty,value.entries.count<=LayerComps.maximumComps,
      Set(value.entries.map(\.id)).count==value.entries.count,
      Set(value.entries.map(\.layerID)).count==value.entries.count,
      Set(value.entries.map{$0.record.requestID}).count==value.entries.count,
      value.entries.contains(where:{$0.id==value.lastDocumentStateID}),
      value.sourceSHA256==object.dataFingerprint,
      object.layerComps?.entries.map(\.id)==value.entries.map(\.id),
      object.layerComps?.selectedID.map({id in value.entries.contains{$0.id==id}}) ?? true else{
      throw CraftError.invalid("The generated-variation index no longer matches its source.")
    }
    for (position,entry) in value.entries.enumerated() {
      try entry.record.validate()
      let expected=try JSONSerialization.jsonObject(with:entry.record.encoded())as! [String:Any]
      guard rows.indices.contains(position),let record=rows[position]["record"]as?[String:Any],Set(record.keys)==Set(expected.keys)else{
        throw CraftError.unsupported("Unrepresented generated-variation record fields.")
      }
      guard Set(entry.metadata.keys).isSubset(of:[ImageGenerationReference.recordKey,GeneratedBackground.contextKey]),
        entry.metadata.values.reduce(0,{$0+$1.count})<=16384 else{
        throw CraftError.invalid("Invalid generated-variation context.")
      }
      var context=Layer(name:"Context",content:.fill(.clear));context.sourceTags=entry.metadata
      _ = try ImageGenerationReference.record(in:context);_ = try GeneratedBackground.record(context)
    }
    return value
  }
  static func selected(_ layer:Layer)throws->Entry? {
    guard let index=try read(layer)else{return nil}
    let id=layer.smartObject?.layerComps?.selectedID ?? index.lastDocumentStateID
    guard let entry=index.entries.first(where:{$0.id==id})else{throw CraftError.invalid("The selected generated variation is missing.")}
    return entry
  }
  static func metadata(_ layer:Layer,key:String)throws->Data? {
    try selected(layer)?.metadata[key]
  }
  static func original(_ layer:Layer)throws->(GenerationRecord,Data) {
    guard let entry=try selected(layer),let object=layer.smartObject else{throw CraftError.invalid("Select a generated variation.")}
    let source=try SmartObjectIO.sourceDocument(object)
    guard let child=source.layers.first(where:{$0.id==entry.layerID})else{throw CraftError.invalid("The generated-variation original is missing.")}
    let original=try GeneratedImageStorage.original(child)
    guard original.0==entry.record else{throw CraftError.invalid("The generated-variation original disagrees with its index.")}
    return original
  }
  static func canAppend(_ layer:Layer,in document:CraftDocument)->Bool {
    guard document.colorMode == .rgb,document.restrictedMode==nil,document.inkMode==nil,
      document.videoTimeline==nil,document.animation==nil,!document.isImageLocked(layer.id),
      layer.video==nil,layer.nativeMode==nil,case .raster=layer.content else{return false}
    if layer.sourceTags?[key] != nil{return (try? read(layer)) != nil}
    guard layer.smartObject==nil,let record=try? GeneratedImageStorage.record(layer),
      let original=layer.sourceTags?[GeneratedImageStorage.originalKey] else{return false}
    return original.count==record.originalByteCount
  }
  private static func entry(_ layer:Layer,compID:UUID=UUID())throws->Entry {
    let original=try GeneratedImageStorage.original(layer)
    let metadata=(layer.sourceTags ?? [:]).filter{[ImageGenerationReference.recordKey,GeneratedBackground.contextKey].contains($0.key)}
    return Entry(id:compID,layerID:layer.id,record:original.0,metadata:metadata)
  }
  private static func rebuildComps(_ document:inout CraftDocument,entries:[Entry],selected:UUID)throws {
    var comps=LayerComps()
    for entry in entries {
      for i in document.layers.indices {document.layers[i].visible=document.layers[i].id==entry.layerID}
      let name=String(entry.record.initialPrompt.prefix(80))
      comps.comps.append(LayerComp(id:entry.id,name:name,options:.init(visibility:true,position:false,appearance:false),document:document))
    }
    guard let active=entries.first(where:{$0.id==selected})else{throw CraftError.invalid("Missing generated-variation selection.")}
    for i in document.layers.indices {document.layers[i].visible=document.layers[i].id==active.layerID}
    document.activeLayerID=active.layerID;comps.appliedID=selected;document.layerComps=comps
    try document.validate()
  }
  static func appending(_ accepted:Layer,to targetID:UUID,in parent:CraftDocument)throws->(Layer,Command) {
    try Task.checkCancellation();try parent.validate()
    guard let position=parent.layers.firstIndex(where:{$0.id==targetID}),
      canAppend(parent.layers[position],in:parent),case .raster(let incoming)=accepted.content,
      accepted.smartObject==nil else{throw CraftError.invalid("Select an unlocked generated layer before adding a variation.")}
    var target=parent.layers[position]
    var inner:CraftDocument,index:Index
    if let existing=try read(target),let object=target.smartObject {
      inner=try SmartObjectIO.sourceDocument(object);index=existing
      guard Set(inner.layers.map(\.id))==Set(index.entries.map(\.layerID)),inner.layers.allSatisfy({layer in
        guard case .raster=layer.content else{return false};return layer.smartObject==nil && layer.parentID==nil
      })else{throw CraftError.invalid("The variation contents were edited outside the variation workflow.")}
    }else{
      guard case .raster(let pixels)=target.content else{throw CraftError.invalid("Select generated pixel content.")}
      inner=try CraftDocument(width:pixels.width,height:pixels.height,depth:parent.depth,name:"Generated Variations")
      inner.colorSpace=parent.colorSpace;inner.workingICC=parent.workingICC;inner.profileIsUntagged=parent.profileIsUntagged;inner.resolution=parent.resolution
      var first=Layer(name:"Variation 1",content:.raster(pixels))
      first.sourceTags=(target.sourceTags ?? [:]).filter{resultKeys.contains($0.key)}
      inner.layers=[first];inner.activeLayerID=first.id
      let original=try entry(first)
      index=Index(sourceSHA256:"",lastDocumentStateID:original.id,entries:[original])
    }
    guard index.entries.count<LayerComps.maximumComps else{throw CraftError.invalid("The source Layer Comp limit has been reached.")}
    var added=Layer(name:"Variation \(index.entries.count+1)",content:.raster(incoming))
    added.sourceTags=(accepted.sourceTags ?? [:]).filter{resultKeys.contains($0.key)}
    let next=try entry(added)
    guard !index.entries.contains(where:{$0.record.requestID==next.record.requestID})else{throw CraftError.invalid("That generated result is already a variation.")}
    let converted=try ColorManagement.converted(incoming,from:parent,to:inner)
    let scale=max(Double(inner.width)/Double(converted.width),Double(inner.height)/Double(converted.height))
    let transform=Transform2D.translation((Double(inner.width)-Double(converted.width)*scale)/2,(Double(inner.height)-Double(converted.height)*scale)/2) * .scale(scale,scale)
    added.content = .raster(converted.width==inner.width && converted.height==inner.height ? converted
      : try RasterGeometry.render(converted,transform:transform,bounds:.init(x:0,y:0,width:inner.width,height:inner.height),method:.bicubic,clampEdges:true))
    inner.layers.append(added);index.entries.append(next);index.lastDocumentStateID=next.id
    try rebuildComps(&inner,entries:index.entries,selected:next.id)
    var(object,pixels)=try SmartObjectIO.embedded(document:inner,in:parent,fileName:"Generated Variations.photato")
    object.layerComps?.selectedID=next.id
    index.sourceSHA256=object.dataFingerprint
    target.smartObject=object;target.content = .raster(pixels);target.sourceTags=target.sourceTags ?? [:]
    for key in resultKeys {target.sourceTags?.removeValue(forKey:key)}
    target.sourceTags?[key]=try index.encoded()
    var result=parent;result.layers[position]=target;result.activeLayerID=target.id
    try result.validate();_ = try read(target);try Task.checkCancellation()
    return(target,.linkedSmartObject(try .init(source:parent,result:result,title:"Add Generated Variation")))
  }
  static func deleting(_ variationID:UUID,from targetID:UUID,in parent:CraftDocument)throws->Command {
    try Task.checkCancellation();try parent.validate()
    guard let position=parent.layers.firstIndex(where:{$0.id==targetID}),
      canAppend(parent.layers[position],in:parent),var index=try read(parent.layers[position]),
      let removed=index.entries.firstIndex(where:{$0.id==variationID}),let object=parent.layers[position].smartObject else{
      throw CraftError.invalid("Select an unlocked generated variation to delete.")
    }
    if index.entries.count==1 {return .deleteLayer(targetID)}
    var inner=try SmartObjectIO.sourceDocument(object),target=parent.layers[position]
    let oldSelected=object.layerComps?.selectedID ?? index.lastDocumentStateID
    let removedLayer=index.entries.remove(at:removed).layerID
    inner.layers.removeAll{$0.id==removedLayer}
    let selected=oldSelected==variationID ? index.entries[min(removed,index.entries.count-1)].id:oldSelected
    try rebuildComps(&inner,entries:index.entries,selected:selected)
    var(updated,pixels)=try SmartObjectIO.embedded(document:inner,in:parent,fileName:"Generated Variations.photato")
    updated.layerComps?.selectedID=selected;index.lastDocumentStateID=selected;index.sourceSHA256=updated.dataFingerprint
    target.smartObject=updated;target.content = .raster(pixels);target.sourceTags?[key]=try index.encoded()
    var result=parent;result.layers[position]=target;try result.validate();_ = try read(target)
    return .linkedSmartObject(try .init(source:parent,result:result,title:"Delete Generated Variation"))
  }
  struct Thumbnails:@unchecked Sendable {let images:[UUID:CGImage]}
  static func thumbnails(_ layer:Layer)throws->Thumbnails {
    guard let index=try read(layer),let object=layer.smartObject else{return Thumbnails(images:[:])}
    let inner=try SmartObjectIO.sourceDocument(object)
    var images:[UUID:CGImage]=[:]
    for entry in index.entries {
      try Task.checkCancellation()
      guard let child=inner.layers.first(where:{$0.id==entry.layerID}),case .raster(let pixels)=child.content else{
        throw CraftError.invalid("The generated variation thumbnail source is missing.")
      }
      let scale=min(1,80/Double(max(pixels.width,pixels.height)))
      let preview=try Renderer.resize(pixels,width:max(1,Int(Double(pixels.width)*scale)),height:max(1,Int(Double(pixels.height)*scale)))
      images[entry.id]=try ColorManagement.displayImage(preview,in:inner)
    }
    return Thumbnails(images:images)
  }

}
